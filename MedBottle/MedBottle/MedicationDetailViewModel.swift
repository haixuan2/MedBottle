import Combine
import Foundation

enum MedicationDetailError: LocalizedError, Equatable {
    case medicationNotFound
    case storeUnavailable
    case outOfStock
    case invalidRefillCount
    case futureDoseDate

    var errorDescription: String? {
        switch self {
        case .medicationNotFound:
            "This medication could not be found."
        case .storeUnavailable:
            "Medication data is not available right now."
        case .outOfStock:
            "This bottle is empty. Refill it before logging another dose."
        case .invalidRefillCount:
            "Enter a refill amount between \(MedicationQuantityLimits.tabletCount.lowerBound) and \(MedicationQuantityLimits.tabletCount.upperBound) tablets."
        case .futureDoseDate:
            "Choose a dose time that has already passed."
        }
    }
}

enum MedicationSelectionError: LocalizedError, Equatable {
    case emptyMedicationList
    case medicationNotFound
    case indexOutOfBounds
    case alreadyAtFirstMedication
    case alreadyAtLastMedication

    var errorDescription: String? {
        switch self {
        case .emptyMedicationList:
            "No medications are available to select."
        case .medicationNotFound:
            "This medication could not be found."
        case .indexOutOfBounds:
            "That medication position is no longer available."
        case .alreadyAtFirstMedication:
            "You are already viewing the first medication."
        case .alreadyAtLastMedication:
            "You are already viewing the last medication."
        }
    }
}

@MainActor
protocol MedicationSelectionRepository: AnyObject {
    var medications: [Medication] { get }
    var medicationsPublisher: AnyPublisher<[Medication], Never> { get }
}

extension MedicationStore: MedicationSelectionRepository {
    var medicationsPublisher: AnyPublisher<[Medication], Never> {
        $medications.eraseToAnyPublisher()
    }
}

@MainActor
final class MedicationSelectionViewModel: ObservableObject {
    @Published private(set) var medications: [Medication]
    @Published private(set) var selectedMedicationID: Medication.ID?
    @Published private(set) var selectedMedication: Medication?
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var errorMessage: String?

    var pageCount: Int {
        medications.count
    }

    var canMovePrevious: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > 0
    }

    var canMoveNext: Bool {
        guard let selectedIndex, !medications.isEmpty else { return false }
        return selectedIndex < medications.index(before: medications.endIndex)
    }

    private let repository: MedicationSelectionRepository
    private var cancellables: Set<AnyCancellable> = []
    private var lastKnownSelectedIndex: Int?

    init(
        repository: MedicationSelectionRepository,
        initiallySelectedID: Medication.ID? = nil
    ) {
        self.repository = repository
        self.medications = repository.medications

        reconcileSelection(
            with: repository.medications,
            preferredMedicationID: initiallySelectedID,
            shouldClearError: false
        )

        repository.medicationsPublisher
            .sink { [weak self] medications in
                Task { @MainActor in
                    self?.reconcileSelection(with: medications)
                }
            }
            .store(in: &cancellables)
    }

    convenience init(
        store: MedicationStore,
        initiallySelectedID: Medication.ID? = nil
    ) {
        self.init(
            repository: store,
            initiallySelectedID: initiallySelectedID
        )
    }

    @discardableResult
    func selectMedication(id medicationID: Medication.ID) -> Result<Medication, MedicationSelectionError> {
        guard medications.firstIndex(where: { $0.id == medicationID }) != nil else {
            return fail(with: .medicationNotFound)
        }

        return selectExistingMedication(id: medicationID)
    }

    @discardableResult
    func selectMedication(at index: Int) -> Result<Medication, MedicationSelectionError> {
        guard medications.indices.contains(index) else {
            return fail(with: medications.isEmpty ? .emptyMedicationList : .indexOutOfBounds)
        }

        return selectExistingMedication(id: medications[index].id)
    }

    @discardableResult
    func movePrevious() -> Result<Medication, MedicationSelectionError> {
        guard !medications.isEmpty else {
            return fail(with: .emptyMedicationList)
        }

        guard let selectedIndex else {
            return selectMedication(at: 0)
        }

        guard selectedIndex > 0 else {
            return fail(with: .alreadyAtFirstMedication)
        }

        return selectMedication(at: selectedIndex - 1)
    }

    @discardableResult
    func moveNext() -> Result<Medication, MedicationSelectionError> {
        guard !medications.isEmpty else {
            return fail(with: .emptyMedicationList)
        }

        guard let selectedIndex else {
            return selectMedication(at: 0)
        }

        guard selectedIndex < medications.index(before: medications.endIndex) else {
            return fail(with: .alreadyAtLastMedication)
        }

        return selectMedication(at: selectedIndex + 1)
    }

    func clearError() {
        errorMessage = nil
    }

    private func reconcileSelection(
        with medications: [Medication],
        preferredMedicationID: Medication.ID? = nil,
        shouldClearError: Bool = true
    ) {
        let previousSelectedID = selectedMedicationID
        let previousSelectedIndex = selectedIndex ?? lastKnownSelectedIndex
        self.medications = medications

        guard !medications.isEmpty else {
            setSelection(id: nil, index: nil, medication: nil)
            if shouldClearError {
                errorMessage = nil
            }
            return
        }

        if let preferredMedicationID,
           let preferredIndex = medications.firstIndex(where: { $0.id == preferredMedicationID }) {
            setSelection(
                id: preferredMedicationID,
                index: preferredIndex,
                medication: medications[preferredIndex]
            )
        } else if let previousSelectedID,
                  let currentIndex = medications.firstIndex(where: { $0.id == previousSelectedID }) {
            setSelection(
                id: previousSelectedID,
                index: currentIndex,
                medication: medications[currentIndex]
            )
        } else {
            let fallbackIndex = previousSelectedIndex.map { min(max($0, 0), medications.index(before: medications.endIndex)) } ?? 0
            setSelection(
                id: medications[fallbackIndex].id,
                index: fallbackIndex,
                medication: medications[fallbackIndex]
            )
        }

        if shouldClearError {
            errorMessage = nil
        }
    }

    private func selectExistingMedication(id medicationID: Medication.ID) -> Result<Medication, MedicationSelectionError> {
        guard let index = medications.firstIndex(where: { $0.id == medicationID }) else {
            return fail(with: .medicationNotFound)
        }

        let medication = medications[index]
        setSelection(id: medicationID, index: index, medication: medication)
        errorMessage = nil
        return .success(medication)
    }

    private func setSelection(
        id medicationID: Medication.ID?,
        index: Int?,
        medication: Medication?
    ) {
        selectedMedicationID = medicationID
        selectedIndex = index
        selectedMedication = medication
        lastKnownSelectedIndex = index
    }

    private func fail(with error: MedicationSelectionError) -> Result<Medication, MedicationSelectionError> {
        errorMessage = error.localizedDescription
        return .failure(error)
    }
}

@MainActor
protocol MedicationDetailRepository {
    func medication(id: Medication.ID) async throws -> Medication
    func doseRecords(forMedicationID medicationID: Medication.ID) async throws -> [DoseRecord]
    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date) async throws -> Medication
    func refill(medicationID: Medication.ID, to count: Int) async throws -> Medication
}

@MainActor
final class MedicationStoreDetailRepository: MedicationDetailRepository {
    private weak var store: MedicationStore?

    init(store: MedicationStore) {
        self.store = store
    }

    func medication(id: Medication.ID) async throws -> Medication {
        try currentMedication(id: id)
    }

    func doseRecords(forMedicationID medicationID: Medication.ID) async throws -> [DoseRecord] {
        guard let store else { throw MedicationDetailError.storeUnavailable }
        return store.doseRecords
            .filter { $0.medicationID == medicationID }
            .sorted { $0.takenAt > $1.takenAt }
    }

    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date = Date()) async throws -> Medication {
        guard let store else { throw MedicationDetailError.storeUnavailable }
        let medication = try currentMedication(id: medicationID)

        guard medication.tabletsRemaining > 0 else {
            throw MedicationDetailError.outOfStock
        }

        store.logDose(
            forMedicationID: medicationID,
            dosageAmount: max(1, dosageAmount),
            takenAt: takenAt
        )
        return try currentMedication(id: medicationID)
    }

    func refill(medicationID: Medication.ID, to count: Int) async throws -> Medication {
        guard let store else { throw MedicationDetailError.storeUnavailable }
        guard MedicationQuantityLimits.tabletCount.contains(count) else {
            throw MedicationDetailError.invalidRefillCount
        }

        let medication = try currentMedication(id: medicationID)
        store.refill(medication, to: count)
        return try currentMedication(id: medicationID)
    }

    private func currentMedication(id: Medication.ID) throws -> Medication {
        guard let store else { throw MedicationDetailError.storeUnavailable }
        guard let medication = store.medications.first(where: { $0.id == id }) else {
            throw MedicationDetailError.medicationNotFound
        }
        return medication
    }
}

@MainActor
final class MedicationQuantityInputViewModel: ObservableObject {
    @Published private(set) var state: MedicationQuantityInputState

    private let configuration: MedicationQuantityInputConfiguration

    init(
        configuration: MedicationQuantityInputConfiguration = .tabletCount,
        initialValue: Int
    ) {
        self.configuration = configuration
        self.state = configuration.makeState(value: initialValue)
    }

    var text: String {
        state.text
    }

    var value: Int? {
        state.value
    }

    var errorMessage: String? {
        state.validationError?.localizedDescription
    }

    func setText(_ text: String) {
        state = configuration.makeState(text: text)
    }

    func setValue(_ value: Int) {
        state = configuration.makeState(value: value)
    }

    func increment() {
        state = configuration.incrementedState(from: state)
    }

    func decrement() {
        state = configuration.decrementedState(from: state)
    }

    func validatedValue() -> Result<Int, MedicationQuantityInputError> {
        if let value = state.value {
            return .success(value)
        }

        return .failure(state.validationError ?? .empty)
    }
}

@MainActor
final class MedicationDetailViewModel: ObservableObject {
    @Published private(set) var snapshot: MedicationDetailSnapshot?
    @Published private(set) var refillQuantity: MedicationQuantityInputState
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let medicationID: Medication.ID
    private let repository: MedicationDetailRepository
    private let snapshotBuilder: MedicationDetailSnapshotBuilding
    private let refillQuantityConfiguration: MedicationQuantityInputConfiguration
    private let now: @Sendable () -> Date
    private var hasEditedRefillQuantity = false

    var latestAllowedManualDoseDate: Date {
        now()
    }

    init(
        medicationID: Medication.ID,
        repository: MedicationDetailRepository,
        snapshotBuilder: MedicationDetailSnapshotBuilding = MedicationDetailSnapshotBuilder(),
        refillQuantityConfiguration: MedicationQuantityInputConfiguration = .tabletCount,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.medicationID = medicationID
        self.repository = repository
        self.snapshotBuilder = snapshotBuilder
        self.refillQuantityConfiguration = refillQuantityConfiguration
        self.now = now
        self.refillQuantity = refillQuantityConfiguration.makeState(value: refillQuantityConfiguration.range.lowerBound)
    }

    convenience init(
        medication: Medication,
        store: MedicationStore,
        snapshotBuilder: MedicationDetailSnapshotBuilding = MedicationDetailSnapshotBuilder()
    ) {
        self.init(
            medicationID: medication.id,
            repository: MedicationStoreDetailRepository(store: store),
            snapshotBuilder: snapshotBuilder
        )
    }

    func load() {
        Task { await refresh() }
    }

    func refresh() async {
        await performLoadingOperation {
            try await loadSnapshot()
        }
    }

    func logDose() {
        Task { await logDose() }
    }

    func logDose() async {
        await logDose(takenAt: now())
    }

    func logManualDose(takenAt: Date) {
        Task { await logManualDose(takenAt: takenAt) }
    }

    func logManualDose(takenAt: Date) async {
        await logDose(takenAt: takenAt)
    }

    func logDose(takenAt: Date) async {
        guard takenAt <= now() else {
            errorMessage = MedicationDetailError.futureDoseDate.localizedDescription
            return
        }

        await performLoadingOperation {
            let currentMedication = try await repository.medication(id: medicationID)
            _ = try await repository.logDose(
                medicationID: medicationID,
                dosageAmount: currentMedication.tabletsPerDose,
                takenAt: takenAt
            )
            return try await loadSnapshot()
        }
    }

    func refill(to count: Int) {
        Task { await refill(to: count) }
    }

    func refill(to count: Int) async {
        await performLoadingOperation {
            _ = try await repository.refill(medicationID: medicationID, to: count)
            return try await loadSnapshot()
        }

        if errorMessage == nil, let snapshot {
            resetRefillQuantity(to: snapshot.medication.tabletsRemaining)
        }
    }

    func setRefillQuantityText(_ text: String) {
        hasEditedRefillQuantity = true
        refillQuantity = refillQuantityConfiguration.makeState(text: text)
    }

    func incrementRefillQuantity() {
        hasEditedRefillQuantity = true
        refillQuantity = refillQuantityConfiguration.incrementedState(from: refillQuantity)
    }

    func decrementRefillQuantity() {
        hasEditedRefillQuantity = true
        refillQuantity = refillQuantityConfiguration.decrementedState(from: refillQuantity)
    }

    func resetRefillQuantity() {
        let count = snapshot?.medication.tabletsRemaining ?? refillQuantityConfiguration.range.lowerBound
        resetRefillQuantity(to: count)
    }

    func refillUsingQuantityInput() {
        Task { await refillUsingQuantityInput() }
    }

    func refillUsingQuantityInput() async {
        switch validatedRefillQuantity() {
        case .success(let count):
            await refill(to: count)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func loadSnapshot() async throws -> MedicationDetailSnapshot {
        let medication = try await repository.medication(id: medicationID)
        let doseRecords = try await repository.doseRecords(forMedicationID: medicationID)
        return snapshotBuilder.makeSnapshot(medication: medication, doseRecords: doseRecords)
    }

    private func performLoadingOperation(_ operation: () async throws -> MedicationDetailSnapshot) async {
        isLoading = true
        errorMessage = nil

        do {
            snapshot = try await operation()
            syncRefillQuantityIfNeeded()
        } catch let error as MedicationDetailError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Something went wrong while updating this medication."
        }

        isLoading = false
    }

    private func validatedRefillQuantity() -> Result<Int, MedicationQuantityInputError> {
        if let value = refillQuantity.value {
            return .success(value)
        }

        return .failure(refillQuantity.validationError ?? .empty)
    }

    private func syncRefillQuantityIfNeeded() {
        guard !hasEditedRefillQuantity, let snapshot else { return }
        refillQuantity = refillQuantityConfiguration.makeState(value: snapshot.medication.tabletsRemaining)
    }

    private func resetRefillQuantity(to count: Int) {
        hasEditedRefillQuantity = false
        refillQuantity = refillQuantityConfiguration.makeState(value: count)
    }
}

protocol MedicationDetailSnapshotBuilding: Sendable {
    func makeSnapshot(medication: Medication, doseRecords: [DoseRecord]) -> MedicationDetailSnapshot
}

struct MedicationDetailSnapshotBuilder: MedicationDetailSnapshotBuilding {
    var calendar: Calendar
    var now: @Sendable () -> Date

    init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    func makeSnapshot(medication: Medication, doseRecords: [DoseRecord]) -> MedicationDetailSnapshot {
        let sortedDoseRecords = doseRecords.sorted { $0.takenAt > $1.takenAt }
        let stockStatus = makeStockStatus(for: medication)

        return MedicationDetailSnapshot(
            medication: medication,
            hero: MedicationHeroContent(
                id: medication.id,
                name: medication.name,
                classificationText: medication.classification.title,
                shapeText: medication.medicationShape.title,
                bottleColorHex: medication.bottleColorHex
            ),
            stockStatus: stockStatus,
            metrics: makeMetrics(for: medication, doseRecords: sortedDoseRecords, stockStatus: stockStatus),
            reminderOverview: makeReminderOverview(for: medication),
            actions: makeActions(for: medication),
            recentDoseRecords: Array(sortedDoseRecords.prefix(5))
        )
    }

    private func makeStockStatus(for medication: Medication) -> MedicationStockStatus {
        let remaining = max(0, medication.tabletsRemaining)
        let dose = max(1, medication.tabletsPerDose)
        let fullDoses = remaining / dose

        if remaining == 0 {
            return MedicationStockStatus(
                level: .empty,
                title: "Empty",
                message: "Refill this bottle before the next dose.",
                remainingCount: 0,
                remainingDoses: 0
            )
        }

        if fullDoses <= 3 {
            return MedicationStockStatus(
                level: .low,
                title: "Low stock",
                message: fullDoses == 0 ? "Less than one full dose remains." : "\(fullDoses) full dose\(fullDoses == 1 ? "" : "s") left.",
                remainingCount: remaining,
                remainingDoses: fullDoses
            )
        }

        return MedicationStockStatus(
            level: .ready,
            title: "On hand",
            message: "\(fullDoses) full doses available.",
            remainingCount: remaining,
            remainingDoses: fullDoses
        )
    }

    private func makeMetrics(
        for medication: Medication,
        doseRecords: [DoseRecord],
        stockStatus: MedicationStockStatus
    ) -> [MedicationDetailMetric] {
        [
            MedicationDetailMetric(
                kind: .remaining,
                title: "Remaining",
                value: "\(stockStatus.remainingCount)",
                subtitle: tabletText(stockStatus.remainingCount)
            ),
            MedicationDetailMetric(
                kind: .dose,
                title: "Dose",
                value: "\(max(1, medication.tabletsPerDose))",
                subtitle: "tablets per dose"
            ),
            MedicationDetailMetric(
                kind: .lastTaken,
                title: "Last taken",
                value: lastTakenText(for: medication.lastTakenAt),
                subtitle: medication.lastTakenAt == nil ? "No doses logged" : nil
            ),
            MedicationDetailMetric(
                kind: .doseHistory,
                title: "History",
                value: "\(doseRecords.count)",
                subtitle: doseRecords.count == 1 ? "logged dose" : "logged doses"
            )
        ]
    }

    private func makeReminderOverview(for medication: Medication) -> MedicationReminderOverview {
        let summaries = medication.reminders
            .sorted { $0.time < $1.time }
            .map(makeReminderSummary)
        let activeSummaries = summaries.filter(\.isActive)
        let nextReminder = medication.reminders
            .filter { $0.isActive && $0.frequency != .asNeeded }
            .compactMap { $0.detailNextOccurrence(from: now(), calendar: calendar) }
            .min()

        return MedicationReminderOverview(
            title: reminderTitle(activeCount: activeSummaries.count, totalCount: summaries.count),
            subtitle: reminderSubtitle(activeCount: activeSummaries.count, totalCount: summaries.count),
            activeCount: activeSummaries.count,
            nextReminderText: nextReminder.map { "Next: \(shortDateTime($0))" },
            reminders: summaries
        )
    }

    private func makeReminderSummary(_ reminder: Medication.Reminder) -> MedicationReminderSummary {
        let nextOccurrence = reminder.detailNextOccurrence(from: now(), calendar: calendar)
        let doseAmount = max(1, reminder.dosageAmount)

        return MedicationReminderSummary(
            id: reminder.id,
            title: reminder.isActive ? reminder.frequency.title : "Paused",
            scheduleText: scheduleText(for: reminder),
            doseText: "\(doseAmount) tablet\(doseAmount == 1 ? "" : "s")",
            nextOccurrenceText: nextOccurrence.map(shortDateTime),
            isActive: reminder.isActive
        )
    }

    private func makeActions(for medication: Medication) -> MedicationDetailActions {
        let canLogDose = medication.tabletsRemaining > 0
        let defaultRefillCount = max(30, medication.tabletsRemaining + max(1, medication.tabletsPerDose) * 30)

        return MedicationDetailActions(
            canLogDose: canLogDose,
            canRefill: true,
            primaryTitle: canLogDose ? "Log dose" : "Refill bottle",
            primarySystemImage: canLogDose ? "checkmark" : "arrow.triangle.2.circlepath",
            refillTitle: "Refill",
            refillSystemImage: "plus.circle",
            defaultRefillCount: defaultRefillCount
        )
    }

    private func scheduleText(for reminder: Medication.Reminder) -> String {
        let timeText = reminder.time.formatted(date: .omitted, time: .shortened)

        switch reminder.frequency {
        case .daily:
            return "Everyday at \(timeText)"
        case .specificDays:
            let days = reminder.weekdays
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.shortTitle)
                .joined(separator: ", ")
            return "\(days.isEmpty ? "Custom days" : days) at \(timeText)"
        case .asNeeded:
            return "As needed"
        }
    }

    private func lastTakenText(for date: Date?) -> String {
        guard let date else { return "Not yet" }

        if calendar.isDateInToday(date) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday, \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func shortDateTime(_ date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today at \(date.formatted(date: .omitted, time: .shortened))"
        }

        if calendar.isDateInTomorrow(date) {
            return "Tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func reminderTitle(activeCount: Int, totalCount: Int) -> String {
        if totalCount == 0 { return "No reminders" }
        if activeCount == 0 { return "Reminders paused" }
        return activeCount == 1 ? "1 active reminder" : "\(activeCount) active reminders"
    }

    private func reminderSubtitle(activeCount: Int, totalCount: Int) -> String {
        if totalCount == 0 { return "No schedule has been set." }
        if activeCount == 0 { return "All reminders are currently paused." }
        return "Medication reminders are ready."
    }

    private func tabletText(_ count: Int) -> String {
        count == 1 ? "tablet" : "tablets"
    }
}

private extension Medication.Reminder {
    func detailNextOccurrence(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isActive, frequency != .asNeeded else { return nil }

        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }

        let validWeekdays: Set<Medication.Weekday>
        switch frequency {
        case .daily:
            validWeekdays = Set(Medication.Weekday.allCases)
        case .specificDays:
            validWeekdays = weekdays.isEmpty ? Set(Medication.Weekday.allCases) : weekdays
        case .asNeeded:
            return nil
        }

        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  let weekday = Medication.Weekday(rawValue: calendar.component(.weekday, from: day)),
                  validWeekdays.contains(weekday),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  candidate >= now else {
                continue
            }

            return candidate
        }

        return nil
    }
}
