import Foundation

struct MedicationSearchResult: Identifiable, Equatable, Sendable {
    let rxcui: String
    let name: String
    let shape: MedicationShape

    var id: String { rxcui }
}

struct MedicationSelectionDetails: Equatable, Sendable {
    let name: String
    let shape: MedicationShape
    let classification: MedicationClassification
}

protocol MedicationSearchServicing: Sendable {
    func search(term: String) async throws -> [MedicationSearchResult]
    func details(for result: MedicationSearchResult) async throws -> MedicationSelectionDetails
}

enum MedicationSearchDebug {
    static let isEnabled = true

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("[MedicationSearch] \(message)")
    }

    static func logDecodingError(_ error: DecodingError, url: URL, data: Data) {
        let preview = String(data: data.prefix(1_000), encoding: .utf8) ?? "<non-UTF8 response>"

        switch error {
        case let .keyNotFound(key, context):
            log("DecodingError.keyNotFound '\(key.stringValue)' at \(context.codingPath.debugPath) for \(url.absoluteString). \(context.debugDescription). Body: \(preview)")
        case let .typeMismatch(type, context):
            log("DecodingError.typeMismatch expected \(type) at \(context.codingPath.debugPath) for \(url.absoluteString). \(context.debugDescription). Body: \(preview)")
        case let .valueNotFound(type, context):
            log("DecodingError.valueNotFound expected \(type) at \(context.codingPath.debugPath) for \(url.absoluteString). \(context.debugDescription). Body: \(preview)")
        case let .dataCorrupted(context):
            log("DecodingError.dataCorrupted at \(context.codingPath.debugPath) for \(url.absoluteString). \(context.debugDescription). Body: \(preview)")
        @unknown default:
            log("Unknown DecodingError for \(url.absoluteString). Body: \(preview)")
        }
    }
}

private extension Array where Element == CodingKey {
    var debugPath: String {
        guard !isEmpty else { return "<root>" }
        return map(\.stringValue).joined(separator: ".")
    }
}

@MainActor
final class MedicationSearchManager: ObservableObject {
    @Published private(set) var results: [MedicationSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isResolvingSelection = false
    @Published private(set) var message: String?

    private let service: MedicationSearchServicing
    private var searchTask: Task<Void, Never>?

    init(service: MedicationSearchServicing = RxNavMedicationSearchService()) {
        self.service = service
    }

    deinit {
        searchTask?.cancel()
    }

    func scheduleSearch(for term: String) {
        searchTask?.cancel()

        let searchTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        MedicationSearchDebug.log("scheduleSearch term='\(term)' trimmed='\(searchTerm)' length=\(searchTerm.count)")

        guard searchTerm.count >= 2 else {
            results = []
            message = nil
            isSearching = false
            return
        }

        isSearching = true
        message = nil

        let service = service
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                MedicationSearchDebug.log("debounce fired for '\(searchTerm)'")
                let foundResults = try await service.search(term: searchTerm)

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.results = foundResults
                    self?.message = foundResults.isEmpty ? "No results found" : nil
                    self?.isSearching = false
                }
            } catch is CancellationError {
                MedicationSearchDebug.log("search cancelled for '\(searchTerm)'")
            } catch {
                MedicationSearchDebug.log("search failed for '\(searchTerm)': \(error)")
                await MainActor.run {
                    self?.results = []
                    self?.message = "No results found"
                    self?.isSearching = false
                }
            }
        }
    }

    func details(for result: MedicationSearchResult) async -> MedicationSelectionDetails {
        isResolvingSelection = true
        defer { isResolvingSelection = false }

        do {
            return try await service.details(for: result)
        } catch {
            return MedicationSelectionDetails(
                name: result.name,
                shape: result.shape,
                classification: .prescription
            )
        }
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
        message = nil
        isSearching = false
    }
}

actor RxNavMedicationSearchService: MedicationSearchServicing {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let rxNavBaseURL = URL(string: "https://rxnav.nlm.nih.gov/REST")!
    private let openFDABaseURL = URL(string: "https://api.fda.gov/drug/label.json")!
    private let maxResults = 12

    private var cachedDisplayTerms: [String]?

    init(session: URLSession = .medicationSearchSession) {
        self.session = session
    }

    func search(term: String) async throws -> [MedicationSearchResult] {
        let approximateCandidates = try await approximateCandidates(for: term)
        let primaryResults = try await productResults(from: approximateCandidates, originalTerm: term)

        if !primaryResults.isEmpty {
            MedicationSearchDebug.log("search term='\(term)' returning \(primaryResults.count) result(s) from approximateTerm/getDrugs")
            return primaryResults
        }

        MedicationSearchDebug.log("approximateTerm returned no usable products for '\(term)'; trying displaynames prefix fallback")
        let fallbackResults = try await displayNamePrefixResults(for: term)
        MedicationSearchDebug.log("search term='\(term)' returning \(fallbackResults.count) result(s) from displaynames fallback")
        return fallbackResults
    }

    private func approximateCandidates(for term: String) async throws -> [RxNormCandidate] {
        guard let url = rxNavURL(path: "approximateTerm.json", queryItems: [
            ("term", term),
            ("maxEntries", "\(maxResults)"),
            ("option", "1")
        ]) else { return [] }

        let response = try await decodedResponse(RxNormApproximateResponse.self, from: url)
        let candidates = response.approximateGroup?.candidate ?? []
        MedicationSearchDebug.log("approximateTerm decoded \(candidates.count) candidate(s) for '\(term)'")
        return candidates
    }

    private func productResults(from candidates: [RxNormCandidate], originalTerm: String) async throws -> [MedicationSearchResult] {
        var seenRXCUIs = Set<String>()
        var results: [MedicationSearchResult] = []

        for candidate in candidates {
            guard
                let rxcui = candidate.rxcui,
                let name = candidate.name,
                !rxcui.isEmpty,
                !name.isEmpty,
                seenRXCUIs.insert(rxcui).inserted
            else {
                MedicationSearchDebug.log("dropping approximate candidate without usable rxcui/name: \(candidate)")
                continue
            }

            let products = try await drugs(for: name)
            if products.isEmpty {
                results.append(
                    MedicationSearchResult(
                        rxcui: rxcui,
                        name: name,
                        shape: MedicationShape.fromRxNormText(name)
                    )
                )
            } else {
                for product in products {
                    guard let result = medicationResult(from: product), seenRXCUIs.insert(result.rxcui).inserted else {
                        MedicationSearchDebug.log("dropping drug product without usable rxcui/name: \(product)")
                        continue
                    }
                    results.append(result)
                }
            }

            if results.count >= maxResults { break }
        }

        MedicationSearchDebug.log("productResults produced \(results.count) result(s) for '\(originalTerm)'")
        return Array(results.prefix(maxResults))
    }

    private func displayNamePrefixResults(for term: String) async throws -> [MedicationSearchResult] {
        guard term.count >= 4 else { return [] }

        let normalizedTerm = term.lowercased()
        let matchingTerms = try await displayTerms()
            .filter { $0.lowercased().contains(normalizedTerm) }
            .prefix(6)

        MedicationSearchDebug.log("displaynames fallback matched terms for '\(term)': \(Array(matchingTerms))")

        var seenRXCUIs = Set<String>()
        var results: [MedicationSearchResult] = []

        for displayTerm in matchingTerms {
            let products = try await drugs(for: displayTerm)
            for product in products {
                guard let result = medicationResult(from: product), seenRXCUIs.insert(result.rxcui).inserted else {
                    MedicationSearchDebug.log("dropping displaynames product without usable rxcui/name: \(product)")
                    continue
                }
                results.append(result)
            }

            if results.count >= maxResults { break }
        }

        return Array(results.prefix(maxResults))
    }

    private func displayTerms() async throws -> [String] {
        if let cachedDisplayTerms {
            return cachedDisplayTerms
        }

        guard let url = rxNavURL(path: "displaynames.json", queryItems: []) else { return [] }
        let response = try await decodedResponse(RxNormDisplayTermsResponse.self, from: url)
        let terms = response.displayTermsList?.term ?? []
        cachedDisplayTerms = terms
        MedicationSearchDebug.log("displaynames decoded \(terms.count) term(s)")
        return terms
    }

    private func drugs(for name: String) async throws -> [RxNormConceptProperty] {
        guard let url = rxNavURL(path: "drugs.json", queryItems: [("name", name)]) else { return [] }

        let response = try await decodedResponse(RxNormDrugsResponse.self, from: url)
        let products = response.drugGroup?.conceptGroup?
            .filter { group in
                group.tty == "SCD" || group.tty == "SBD" || group.tty == "GPCK" || group.tty == "BPCK"
            }
            .flatMap { $0.conceptProperties ?? [] } ?? []

        MedicationSearchDebug.log("drugs name='\(name)' decoded \(products.count) product(s)")
        return products
    }

    private func rxNavURL(path: String, queryItems: [(String, String)]) -> URL? {
        let query = queryItems
            .map { name, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(name)=\(encodedValue)"
            }
            .joined(separator: "&")

        let urlString = query.isEmpty
            ? "\(rxNavBaseURL.absoluteString)/\(path)"
            : "\(rxNavBaseURL.absoluteString)/\(path)?\(query)"

        MedicationSearchDebug.log("constructed RxNav URL: \(urlString)")
        return URL(string: urlString)
    }

    private func medicationResult(from product: RxNormConceptProperty) -> MedicationSearchResult? {
        guard let rxcui = product.rxcui, let name = product.name, !rxcui.isEmpty, !name.isEmpty else {
            return nil
        }

        return MedicationSearchResult(
            rxcui: rxcui,
            name: name,
            shape: MedicationShape.fromRxNormText(name)
        )
    }

    private func medicationResult(from candidate: RxNormCandidate) -> MedicationSearchResult? {
        guard let rxcui = candidate.rxcui, let name = candidate.name, !rxcui.isEmpty, !name.isEmpty else {
            return nil
        }

        return MedicationSearchResult(
            rxcui: rxcui,
            name: name,
            shape: MedicationShape.fromRxNormText(name)
        )
    }

    func details(for result: MedicationSearchResult) async throws -> MedicationSelectionDetails {
        async let properties = rxNormProperties(for: result.rxcui)
        async let classification = classification(for: result.rxcui)

        let propertyText = try await properties.joined(separator: " ")
        let detectedClassification = await classification ?? .prescription
        let shape = MedicationShape.fromRxNormText([result.name, propertyText].joined(separator: " "))

        return MedicationSelectionDetails(
            name: result.name,
            shape: shape,
            classification: detectedClassification
        )
    }

    private func rxNormProperties(for rxcui: String) async throws -> [String] {
        guard let url = rxNavURL(path: "rxcui/\(rxcui)/allProperties.json", queryItems: [("prop", "all")]) else { return [] }

        let response = try await decodedResponse(RxNormPropertiesResponse.self, from: url)
        return response.propConceptGroup?.propConcept?.flatMap { property in
            [property.propName, property.propValue].compactMap { $0 }
        } ?? []
    }

    private func classification(for rxcui: String) async -> MedicationClassification? {
        var components = URLComponents(url: openFDABaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search", value: "openfda.rxcui:\"\(rxcui)\""),
            URLQueryItem(name: "limit", value: "5")
        ]

        guard let url = components?.url else { return nil }
        MedicationSearchDebug.log("constructed openFDA URL: \(url.absoluteString)")

        do {
            let response = try await decodedResponse(OpenFDALabelResponse.self, from: url)
            let productTypes = (response.results ?? [])
                .flatMap { $0.openfda?.productType ?? [] }
                .map { $0.lowercased() }

            let hasPrescription = productTypes.contains { $0.contains("prescription") }
            let hasOTC = productTypes.contains { $0.contains("otc") || $0.contains("over") && $0.contains("counter") }

            if hasPrescription { return .prescription }
            if hasOTC { return .otc }
            return nil
        } catch {
            return nil
        }
    }

    private func decodedResponse<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        MedicationSearchDebug.log("requesting URL: \(url.absoluteString)")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(from: url)
        } catch {
            MedicationSearchDebug.log("URLSession failed for \(url.absoluteString): \(error)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            if let httpResponse = response as? HTTPURLResponse {
                let body = String(data: data.prefix(1_000), encoding: .utf8) ?? "<non-UTF8 response>"
                MedicationSearchDebug.log("HTTP \(httpResponse.statusCode) for \(url.absoluteString). Body: \(body)")
            } else {
                MedicationSearchDebug.log("Non-HTTP response for \(url.absoluteString): \(response)")
            }
            throw URLError(.badServerResponse)
        }

        MedicationSearchDebug.log("HTTP \(httpResponse.statusCode) for \(url.absoluteString)")

        do {
            return try decoder.decode(type, from: data)
        } catch let decodingError as DecodingError {
            MedicationSearchDebug.logDecodingError(decodingError, url: url, data: data)
            throw decodingError
        } catch {
            let preview = String(data: data.prefix(1_000), encoding: .utf8) ?? "<non-UTF8 response>"
            MedicationSearchDebug.log("Decode failed for \(url.absoluteString): \(error). Body: \(preview)")
            throw error
        }
    }
}

private extension URLSession {
    static var medicationSearchSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

extension MedicationShape {
    static func fromRxNormText(_ text: String) -> MedicationShape {
        let normalized = text.lowercased()

        if normalized.contains("softgel")
            || normalized.contains("soft gel")
            || normalized.contains("gelcap")
            || normalized.contains("gel cap")
            || normalized.contains("liquid filled capsule")
            || normalized.contains("liquid-filled capsule") {
            return .softgel
        }

        if normalized.contains("capsule") {
            return .capsule
        }

        if normalized.contains("tablet")
            || normalized.contains("caplet")
            || normalized.contains("chewable")
            || normalized.contains("orally disintegrating") {
            return .tablet
        }

        if normalized.contains("pill") || normalized.contains("pellet") {
            return .pill
        }

        return .tablet
    }
}

private struct RxNormApproximateResponse: Decodable {
    let approximateGroup: RxNormApproximateGroup?
}

private struct RxNormApproximateGroup: Decodable {
    let inputTerm: String?
    let candidate: [RxNormCandidate]?
}

private struct RxNormCandidate: Decodable, CustomStringConvertible {
    let rxcui: String?
    let rxaui: String?
    let score: String?
    let rank: String?
    let name: String?
    let source: String?

    var description: String {
        "RxNormCandidate(rxcui: \(rxcui ?? "nil"), rxaui: \(rxaui ?? "nil"), score: \(score ?? "nil"), rank: \(rank ?? "nil"), name: \(name ?? "nil"), source: \(source ?? "nil"))"
    }
}

private struct RxNormDisplayTermsResponse: Decodable {
    let displayTermsList: RxNormDisplayTermsList?
}

private struct RxNormDisplayTermsList: Decodable {
    let term: [String]?
}

private struct RxNormDrugsResponse: Decodable {
    let drugGroup: RxNormDrugGroup?
}

private struct RxNormDrugGroup: Decodable {
    let name: String?
    let conceptGroup: [RxNormConceptGroup]?
}

private struct RxNormConceptGroup: Decodable {
    let tty: String?
    let conceptProperties: [RxNormConceptProperty]?
}

private struct RxNormConceptProperty: Decodable, CustomStringConvertible {
    let rxcui: String?
    let name: String?
    let synonym: String?
    let tty: String?
    let language: String?
    let suppress: String?
    let umlscui: String?

    var description: String {
        "RxNormConceptProperty(rxcui: \(rxcui ?? "nil"), name: \(name ?? "nil"), tty: \(tty ?? "nil"))"
    }
}

private struct RxNormPropertiesResponse: Decodable {
    let propConceptGroup: RxNormPropertyConceptGroup?
}

private struct RxNormPropertyConceptGroup: Decodable {
    let propConcept: [RxNormPropertyConcept]?
}

private struct RxNormPropertyConcept: Decodable {
    let propName: String?
    let propValue: String?
}

private struct OpenFDALabelResponse: Decodable {
    let results: [OpenFDALabelResult]?
}

private struct OpenFDALabelResult: Decodable {
    let openfda: OpenFDAFields?
}

private struct OpenFDAFields: Decodable {
    let productType: [String]?

    enum CodingKeys: String, CodingKey {
        case productType = "product_type"
    }
}
