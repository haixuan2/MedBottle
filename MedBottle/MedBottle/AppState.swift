import Foundation

enum MedicationShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case tablet
    case pill
    case capsule
    case softgel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tablet: "Tablet"
        case .pill: "Pill"
        case .capsule: "Capsule"
        case .softgel: "Softgel"
        }
    }
}

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
    var medicationShape: MedicationShape
    var classification: MedicationClassification
    var reminders: [Reminder]
    var lastTakenAt: Date?

    var remainingText: String {
        "\(tabletsRemaining) tablet\(tabletsRemaining == 1 ? "" : "s")"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tabletsRemaining
        case tabletsPerDose
        case bottleColorHex
        case medicationShape
        case classification
        case reminders
        case lastTakenAt
    }

    init(
        id: UUID,
        name: String,
        tabletsRemaining: Int,
        tabletsPerDose: Int,
        bottleColorHex: String,
        medicationShape: MedicationShape,
        classification: MedicationClassification = .prescription,
        reminders: [Reminder] = [],
        lastTakenAt: Date?
    ) {
        self.id = id
        self.name = name
        self.tabletsRemaining = tabletsRemaining
        self.tabletsPerDose = tabletsPerDose
        self.bottleColorHex = bottleColorHex
        self.medicationShape = medicationShape
        self.classification = classification
        self.reminders = reminders
        self.lastTakenAt = lastTakenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tabletsRemaining = try container.decode(Int.self, forKey: .tabletsRemaining)
        tabletsPerDose = try container.decode(Int.self, forKey: .tabletsPerDose)
        bottleColorHex = try container.decode(String.self, forKey: .bottleColorHex)
        medicationShape = try container.decodeIfPresent(MedicationShape.self, forKey: .medicationShape) ?? .tablet
        classification = try container.decodeIfPresent(MedicationClassification.self, forKey: .classification) ?? .prescription
        reminders = try container.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
        lastTakenAt = try container.decodeIfPresent(Date.self, forKey: .lastTakenAt)
    }
}

struct DoseRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var medicationID: UUID
    var medicationName: String
    var takenAt: Date
    var tabletCount: Int
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
                    medicationShape: .tablet,
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

    func logDose(forMedicationID medicationID: Medication.ID, dosageAmount: Int, takenAt: Date = Date()) {
        guard let index = medications.firstIndex(where: { $0.id == medicationID }) else { return }
        let dose = max(1, dosageAmount)
        medications[index].tabletsRemaining = max(0, medications[index].tabletsRemaining - dose)
        medications[index].lastTakenAt = takenAt
        doseRecords.insert(
            DoseRecord(
                id: UUID(),
                medicationID: medications[index].id,
                medicationName: medications[index].name,
                takenAt: takenAt,
                tabletCount: dose
            ),
            at: 0
        )
    }

    func addMedication(
        name: String,
        tablets: Int,
        dose: Int,
        colorHex: String,
        shape: MedicationShape,
        classification: MedicationClassification,
        reminders: [Medication.Reminder] = []
    ) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        let medication = Medication(
            id: UUID(),
            name: cleanedName,
            tabletsRemaining: max(0, tablets),
            tabletsPerDose: max(1, dose),
            bottleColorHex: colorHex,
            medicationShape: shape,
            classification: classification,
            reminders: sanitizedReminders(reminders),
            lastTakenAt: nil
        )
        medications.append(medication)
        NotificationManager.shared.scheduleReminders(for: medication)
    }

    func updateMedication(_ medication: Medication) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        let previousMedication = medications[index]
        var updatedMedication = medication
        updatedMedication.name = medication.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedMedication.tabletsRemaining = max(0, medication.tabletsRemaining)
        updatedMedication.tabletsPerDose = max(1, medication.tabletsPerDose)
        updatedMedication.reminders = sanitizedReminders(medication.reminders)
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

    func deleteDoseRecords(withIDs recordIDs: Set<DoseRecord.ID>) {
        let deletedRecords = doseRecords.filter { recordIDs.contains($0.id) }
        guard !deletedRecords.isEmpty else { return }

        for record in deletedRecords {
            guard let medicationIndex = medications.firstIndex(where: { $0.id == record.medicationID }) else {
                continue
            }

            medications[medicationIndex].tabletsRemaining += max(1, record.tabletCount)
            medications[medicationIndex].lastTakenAt = latestDoseDate(
                forMedicationID: record.medicationID,
                excluding: recordIDs
            )
        }

        doseRecords.removeAll { recordIDs.contains($0.id) }
    }

    func refill(_ medication: Medication, to count: Int) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        medications[index].tabletsRemaining = max(0, count)
    }

    private func latestDoseDate(forMedicationID medicationID: Medication.ID, excluding recordIDs: Set<DoseRecord.ID>) -> Date? {
        doseRecords
            .filter { $0.medicationID == medicationID && !recordIDs.contains($0.id) }
            .map(\.takenAt)
            .max()
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
            updatedReminder.dosageAmount = max(1, reminder.dosageAmount)
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
        medications[index].lastTakenAt = takenAt
        doseRecords.insert(
            DoseRecord(
                id: UUID(),
                medicationID: medications[index].id,
                medicationName: medications[index].name,
                takenAt: takenAt,
                tabletCount: dose
            ),
            at: 0
        )

        if let medicationData = try? JSONEncoder().encode(medications) {
            UserDefaults.standard.set(medicationData, forKey: medicationsStorageKey)
        }

        if let recordsData = try? JSONEncoder().encode(doseRecords) {
            UserDefaults.standard.set(recordsData, forKey: doseRecordsStorageKey)
        }
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
