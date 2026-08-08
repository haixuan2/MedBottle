import Foundation

enum MedicationClassification: String, Codable, CaseIterable, Identifiable, Sendable {
    case prescription
    case otc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prescription: "Prescription"
        case .otc: "OTC"
        }
    }
}

struct Medication: Identifiable, Codable, Equatable, Sendable {
    enum ReminderFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
        case daily
        case specificDays
        case asNeeded

        var id: String { rawValue }

        var title: String {
            switch self {
            case .daily: "Everyday"
            case .specificDays: "Custom Days"
            case .asNeeded: "As Needed"
            }
        }
    }

    enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
        case sunday = 1
        case monday
        case tuesday
        case wednesday
        case thursday
        case friday
        case saturday

        var id: Int { rawValue }

        var shortTitle: String {
            switch self {
            case .sunday: "Sun"
            case .monday: "Mon"
            case .tuesday: "Tue"
            case .wednesday: "Wed"
            case .thursday: "Thu"
            case .friday: "Fri"
            case .saturday: "Sat"
            }
        }
    }

    struct Reminder: Identifiable, Codable, Equatable, Sendable {
        var id: UUID
        var time: Date
        var frequency: ReminderFrequency
        var weekdays: Set<Weekday>
        var isActive: Bool
        var dosageAmount: Int

        init(
            id: UUID = UUID(),
            time: Date = Date(),
            frequency: ReminderFrequency = .daily,
            weekdays: Set<Weekday> = Set(Weekday.allCases),
            isActive: Bool = true,
            dosageAmount: Int = 1
        ) {
            self.id = id
            self.time = time
            self.frequency = frequency
            self.weekdays = weekdays
            self.isActive = isActive
            self.dosageAmount = dosageAmount
        }
    }

    var id: UUID
    var name: String
    var tabletsRemaining: Int
    var tabletsPerDose: Int
    var bottleColorHex: String
    var classification: MedicationClassification
    var reminders: [Reminder]
    var lastTakenAt: Date?
    /// Highest tablet count this bottle has held. The bottle visual reads as a gauge
    /// against this, so a 30-tablet bottle at 15 looks half full.
    var bottleCapacity: Int
    /// RxNorm concept id from search. Nothing reads it yet — drug interactions need it.
    var rxcui: String?

    var remainingText: String {
        "\(tabletsRemaining) tablet\(tabletsRemaining == 1 ? "" : "s")"
    }

    /// 0...1 share of the bottle still filled.
    var fillRatio: Double {
        let capacity = max(1, bottleCapacity)
        return min(1, max(0, Double(tabletsRemaining) / Double(capacity)))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tabletsRemaining
        case tabletsPerDose
        case bottleColorHex
        case classification
        case reminders
        case lastTakenAt
        case bottleCapacity
        case rxcui
    }

    init(
        id: UUID,
        name: String,
        tabletsRemaining: Int,
        tabletsPerDose: Int,
        bottleColorHex: String,
        classification: MedicationClassification = .prescription,
        reminders: [Reminder] = [],
        lastTakenAt: Date?,
        bottleCapacity: Int? = nil,
        rxcui: String? = nil
    ) {
        self.id = id
        self.name = name
        self.tabletsRemaining = tabletsRemaining
        self.tabletsPerDose = tabletsPerDose
        self.bottleColorHex = bottleColorHex
        self.classification = classification
        self.reminders = reminders
        self.lastTakenAt = lastTakenAt
        self.bottleCapacity = max(1, bottleCapacity ?? tabletsRemaining)
        self.rxcui = rxcui
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tabletsRemaining = try container.decode(Int.self, forKey: .tabletsRemaining)
        tabletsPerDose = try container.decode(Int.self, forKey: .tabletsPerDose)
        bottleColorHex = try container.decode(String.self, forKey: .bottleColorHex)
        classification = try container.decodeIfPresent(MedicationClassification.self, forKey: .classification) ?? .prescription
        reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
        lastTakenAt = try container.decodeIfPresent(Date.self, forKey: .lastTakenAt)
        // Bottles saved before capacity existed adopt their current count as capacity.
        bottleCapacity = max(1, try container.decodeIfPresent(Int.self, forKey: .bottleCapacity) ?? tabletsRemaining)
        rxcui = try container.decodeIfPresent(String.self, forKey: .rxcui)
    }
}

struct DoseRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var medicationID: UUID
    var medicationName: String
    var takenAt: Date
    var tabletCount: Int
}

enum MedicationQuantityLimits {
    static let tabletCount = 0...500
    static let doseCount = 1...12
}

@MainActor
final class MedicationStore: ObservableObject {
    static let medicationsStorageKey = "medications.v1"
    static let doseRecordsStorageKey = "doseRecords.v1"

    @Published var medications: [Medication] {
        didSet {
            save()
        }
    }
    @Published var doseRecords: [DoseRecord] {
        didSet { saveRecords() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.medicationsStorageKey),
           let decoded = try? JSONDecoder().decode([Medication].self, from: data) {
            medications = decoded
        } else {
            medications = [
                Medication(
                    id: UUID(),
                    name: "Finasteride",
                    tabletsRemaining: 30,
                    tabletsPerDose: 1,
                    bottleColorHex: "D99A00",
                    lastTakenAt: nil
                )
            ]
        }

        if let data = UserDefaults.standard.data(forKey: Self.doseRecordsStorageKey),
           let decoded = try? JSONDecoder().decode([DoseRecord].self, from: data) {
            doseRecords = decoded
        } else {
            doseRecords = []
        }
    }

    func logDose(for medication: Medication) {
        logDose(forMedicationID: medication.id, dosageAmount: medication.tabletsPerDose)
    }

    @discardableResult
    func logDose(forMedicationID medicationID: Medication.ID, dosageAmount: Int, takenAt: Date = Date()) -> DoseRecord? {
        guard let index = medications.firstIndex(where: { $0.id == medicationID }) else { return nil }
        let dose = max(1, dosageAmount)
        medications[index].tabletsRemaining = max(0, medications[index].tabletsRemaining - dose)
        medications[index].lastTakenAt = latestDoseDate(
            forMedicationID: medicationID,
            currentLastTakenAt: medications[index].lastTakenAt,
            including: takenAt
        )
        let record = DoseRecord(
            id: UUID(),
            medicationID: medications[index].id,
            medicationName: medications[index].name,
            takenAt: takenAt,
            tabletCount: dose
        )
        doseRecords = (doseRecords + [record]).sorted { $0.takenAt > $1.takenAt }
        return record
    }

    /// Reverses a single logged dose: removes the record, restores the exact pre-log bottle
    /// count, and recomputes `lastTakenAt` from the records that survive.
    func undoDose(
        medicationID: Medication.ID,
        recordID: DoseRecord.ID,
        restoringTabletsTo count: Int
    ) {
        guard let index = medications.firstIndex(where: { $0.id == medicationID }),
              doseRecords.contains(where: { $0.id == recordID }) else {
            return
        }

        doseRecords.removeAll { $0.id == recordID }
        medications[index].tabletsRemaining = MedicationQuantityLimits.tabletCount.clamping(count)
        medications[index].lastTakenAt = latestDoseDate(
            forMedicationID: medicationID,
            excluding: []
        )
    }

    @discardableResult
    func addMedication(
        name: String,
        tablets: Int,
        dose: Int,
        colorHex: String,
        classification: MedicationClassification,
        reminders: [Medication.Reminder] = [],
        rxcui: String? = nil
    ) -> Medication? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return nil }

        let clampedTablets = MedicationQuantityLimits.tabletCount.clamping(tablets)
        let medication = Medication(
            id: UUID(),
            name: cleanedName,
            tabletsRemaining: clampedTablets,
            tabletsPerDose: MedicationQuantityLimits.doseCount.clamping(dose),
            bottleColorHex: colorHex,
            classification: classification,
            reminders: sanitizedReminders(reminders),
            lastTakenAt: nil,
            bottleCapacity: clampedTablets,
            rxcui: rxcui
        )
        medications.append(medication)
        NotificationManager.shared.scheduleReminders(for: medication)
        return medication
    }

    func updateMedication(_ medication: Medication) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        let previousMedication = medications[index]
        var updatedMedication = medication
        updatedMedication.name = medication.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedMedication.tabletsRemaining = MedicationQuantityLimits.tabletCount.clamping(medication.tabletsRemaining)
        updatedMedication.tabletsPerDose = MedicationQuantityLimits.doseCount.clamping(medication.tabletsPerDose)
        updatedMedication.reminders = sanitizedReminders(medication.reminders)
        updatedMedication.bottleCapacity = max(medication.bottleCapacity, updatedMedication.tabletsRemaining)
        medications[index] = updatedMedication

        if previousMedication.reminderScheduleSignature != updatedMedication.reminderScheduleSignature {
            NotificationManager.shared.scheduleReminders(for: updatedMedication)
        }
    }

    func deleteMedications(at offsets: IndexSet, selectedID: Medication.ID?) -> Medication.ID? {
        let validOffsets = offsets.filter { medications.indices.contains($0) }
        guard !validOffsets.isEmpty else { return selectedID }

        let preservedDoseRecords = doseRecords
        let deletedIDs = Set(validOffsets.map { medications[$0].id })
        deletedIDs.forEach { NotificationManager.shared.removeReminders(for: $0) }
        let replacementSelection = replacementSelection(
            afterDeleting: validOffsets,
            selectedID: selectedID,
            deletedIDs: deletedIDs
        )

        for offset in validOffsets.sorted(by: >) {
            medications.remove(at: offset)
        }

        if doseRecords != preservedDoseRecords {
            doseRecords = preservedDoseRecords
        }

        return replacementSelection
    }

    /// - Parameter returningTablets: when `true` the deleted doses are added back to the
    ///   bottle. The user chooses this explicitly in the delete confirmation, because a
    ///   mistyped record and a dose that was never taken need opposite outcomes.
    func deleteDoseRecords(withIDs recordIDs: Set<DoseRecord.ID>, returningTablets: Bool = true) {
        let deletedRecords = doseRecords.filter { recordIDs.contains($0.id) }
        guard !deletedRecords.isEmpty else { return }

        for record in deletedRecords {
            guard let medicationIndex = medications.firstIndex(where: { $0.id == record.medicationID }) else {
                continue
            }

            if returningTablets {
                let restored = medications[medicationIndex].tabletsRemaining + max(1, record.tabletCount)
                medications[medicationIndex].tabletsRemaining = MedicationQuantityLimits.tabletCount.clamping(restored)
            }

            medications[medicationIndex].lastTakenAt = latestDoseDate(
                forMedicationID: record.medicationID,
                excluding: recordIDs
            )
        }

        doseRecords.removeAll { recordIDs.contains($0.id) }
    }

    func refill(_ medication: Medication, to count: Int) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        let clamped = MedicationQuantityLimits.tabletCount.clamping(count)
        medications[index].tabletsRemaining = clamped
        // A bigger bottle than we have ever seen becomes the new full mark.
        medications[index].bottleCapacity = max(medications[index].bottleCapacity, clamped)
    }

    private func latestDoseDate(forMedicationID medicationID: Medication.ID, excluding recordIDs: Set<DoseRecord.ID>) -> Date? {
        doseRecords
            .filter { $0.medicationID == medicationID && !recordIDs.contains($0.id) }
            .map(\.takenAt)
            .max()
    }

    private func latestDoseDate(
        forMedicationID medicationID: Medication.ID,
        currentLastTakenAt: Date?,
        including takenAt: Date
    ) -> Date {
        (
            doseRecords
                .filter { $0.medicationID == medicationID }
                .map(\.takenAt)
            + [currentLastTakenAt, takenAt].compactMap { $0 }
        )
        .max() ?? takenAt
    }

    private func replacementSelection(
        afterDeleting offsets: [Int],
        selectedID: Medication.ID?,
        deletedIDs: Set<Medication.ID>
    ) -> Medication.ID? {
        guard let selectedID, deletedIDs.contains(selectedID) else { return selectedID }

        let selectedDeletedOffset = offsets.first(where: { medications[$0].id == selectedID }) ?? offsets.min() ?? 0
        let remainingMedications = medications.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)

        if let nextMedication = remainingMedications.enumerated()
            .first(where: { $0.offset >= selectedDeletedOffset })?
            .element {
            return nextMedication.id
        }

        return remainingMedications.last?.id
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(medications) else { return }
        UserDefaults.standard.set(data, forKey: Self.medicationsStorageKey)
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(doseRecords) else { return }
        UserDefaults.standard.set(data, forKey: Self.doseRecordsStorageKey)
    }

    private func sanitizedReminders(_ reminders: [Medication.Reminder]) -> [Medication.Reminder] {
        reminders.map { reminder in
            var updatedReminder = reminder
            updatedReminder.dosageAmount = MedicationQuantityLimits.doseCount.clamping(reminder.dosageAmount)
            if updatedReminder.frequency == .specificDays && updatedReminder.weekdays.isEmpty {
                updatedReminder.weekdays = Set(Medication.Weekday.allCases)
            }
            return updatedReminder
        }
    }

    func reloadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: Self.medicationsStorageKey),
           let decoded = try? JSONDecoder().decode([Medication].self, from: data),
           decoded != medications {
            medications = decoded
        }

        if let data = UserDefaults.standard.data(forKey: Self.doseRecordsStorageKey),
           let decoded = try? JSONDecoder().decode([DoseRecord].self, from: data),
           decoded != doseRecords {
            doseRecords = decoded
        }
    }

    static func persistNotificationDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date = Date()) {
        var medications: [Medication] = []
        var doseRecords: [DoseRecord] = []

        if let data = UserDefaults.standard.data(forKey: medicationsStorageKey),
           let decoded = try? JSONDecoder().decode([Medication].self, from: data) {
            medications = decoded
        }

        if let data = UserDefaults.standard.data(forKey: doseRecordsStorageKey),
           let decoded = try? JSONDecoder().decode([DoseRecord].self, from: data) {
            doseRecords = decoded
        }

        guard let index = medications.firstIndex(where: { $0.id == medicationID }) else { return }
        let dose = max(1, dosageAmount)
        medications[index].tabletsRemaining = max(0, medications[index].tabletsRemaining - dose)
        medications[index].lastTakenAt = (
            doseRecords
                .filter { $0.medicationID == medicationID }
                .map(\.takenAt)
            + [medications[index].lastTakenAt, takenAt].compactMap { $0 }
        )
        .max()
        let record = DoseRecord(
            id: UUID(),
            medicationID: medications[index].id,
            medicationName: medications[index].name,
            takenAt: takenAt,
            tabletCount: dose
        )
        doseRecords = (doseRecords + [record]).sorted { $0.takenAt > $1.takenAt }

        if let medicationData = try? JSONEncoder().encode(medications) {
            UserDefaults.standard.set(medicationData, forKey: medicationsStorageKey)
        }

        if let recordsData = try? JSONEncoder().encode(doseRecords) {
            UserDefaults.standard.set(recordsData, forKey: doseRecordsStorageKey)
        }
    }
}

extension ClosedRange where Bound == Int {
    func clamping(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

private struct MedicationReminderScheduleSignature: Equatable {
    let name: String
    let reminders: [Medication.Reminder]
}

private extension Medication {
    var reminderScheduleSignature: MedicationReminderScheduleSignature {
        MedicationReminderScheduleSignature(
            name: name,
            reminders: reminders
        )
    }
}
