import Foundation
import SwiftData

@Model
final class PersistentMedication {
    @Attribute(.unique) var id: UUID
    var name: String
    var tabletsRemaining: Int
    var tabletsPerDose: Int
    var bottleColorHex: String
    var classificationRawValue: String
    var lastTakenAt: Date?
    @Relationship(deleteRule: .cascade) var reminders: [PersistentMedicationReminder]

    init(
        id: UUID = UUID(),
        name: String,
        tabletsRemaining: Int,
        tabletsPerDose: Int,
        bottleColorHex: String,
        classification: MedicationClassification,
        reminders: [PersistentMedicationReminder] = [],
        lastTakenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.tabletsRemaining = MedicationQuantityLimits.tabletCount.clamping(tabletsRemaining)
        self.tabletsPerDose = MedicationQuantityLimits.doseCount.clamping(tabletsPerDose)
        self.bottleColorHex = bottleColorHex
        self.classificationRawValue = classification.rawValue
        self.reminders = reminders
        self.lastTakenAt = lastTakenAt
    }
}

@Model
final class PersistentMedicationReminder {
    @Attribute(.unique) var id: UUID
    var time: Date
    var frequencyRawValue: String
    var weekdayRawValues: [Int]
    var isActive: Bool
    var dosageAmount: Int

    init(
        id: UUID = UUID(),
        time: Date = Date(),
        frequency: Medication.ReminderFrequency = .daily,
        weekdays: Set<Medication.Weekday> = Set(Medication.Weekday.allCases),
        isActive: Bool = true,
        dosageAmount: Int = 1
    ) {
        self.id = id
        self.time = time
        self.frequencyRawValue = frequency.rawValue
        self.weekdayRawValues = weekdays.map(\.rawValue).sorted()
        self.isActive = isActive
        self.dosageAmount = MedicationQuantityLimits.doseCount.clamping(dosageAmount)
    }
}

@Model
final class PersistentDoseRecord {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var medicationName: String
    var takenAt: Date
    var tabletCount: Int

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        medicationName: String,
        takenAt: Date = Date(),
        tabletCount: Int
    ) {
        self.id = id
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.takenAt = takenAt
        self.tabletCount = max(1, tabletCount)
    }
}

enum MedicationPersistenceError: LocalizedError, Equatable {
    case medicationNotFound
    case outOfStock

    var errorDescription: String? {
        switch self {
        case .medicationNotFound:
            "This medication could not be found."
        case .outOfStock:
            "This bottle is empty. Refill it before logging another dose."
        }
    }
}

@MainActor
protocol ActiveMedicationPersisting {
    func medication(id medicationID: Medication.ID) throws -> Medication
    func doseRecords(forMedicationID medicationID: Medication.ID) throws -> [DoseRecord]
    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date) throws -> Medication
    func deleteMedicationPreservingDoseHistory(id medicationID: Medication.ID) throws
}

@MainActor
struct SwiftDataActiveMedicationStore: ActiveMedicationPersisting {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func medication(id medicationID: Medication.ID) throws -> Medication {
        try persistentMedication(id: medicationID).toMedication()
    }

    func doseRecords(forMedicationID medicationID: Medication.ID) throws -> [DoseRecord] {
        try modelContext.fetch(FetchDescriptor<PersistentDoseRecord>())
            .filter { $0.medicationID == medicationID }
            .sorted { $0.takenAt > $1.takenAt }
            .map { $0.toDoseRecord() }
    }

    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date) throws -> Medication {
        let medication = try persistentMedication(id: medicationID)
        guard medication.tabletsRemaining > 0 else {
            throw MedicationPersistenceError.outOfStock
        }

        let dose = max(1, dosageAmount)
        medication.tabletsRemaining = max(0, medication.tabletsRemaining - dose)
        medication.lastTakenAt = try latestDoseDate(
            forMedicationID: medicationID,
            currentLastTakenAt: medication.lastTakenAt,
            including: takenAt
        )

        modelContext.insert(
            PersistentDoseRecord(
                medicationID: medication.id,
                medicationName: medication.name,
                takenAt: takenAt,
                tabletCount: dose
            )
        )
        try modelContext.save()

        return medication.toMedication()
    }

    func deleteMedicationPreservingDoseHistory(id medicationID: Medication.ID) throws {
        let medication = try persistentMedication(id: medicationID)
        modelContext.delete(medication)
        try modelContext.save()
    }

    private func persistentMedication(id medicationID: Medication.ID) throws -> PersistentMedication {
        guard let medication = try modelContext.fetch(FetchDescriptor<PersistentMedication>())
            .first(where: { $0.id == medicationID }) else {
            throw MedicationPersistenceError.medicationNotFound
        }

        return medication
    }

    private func latestDoseDate(
        forMedicationID medicationID: Medication.ID,
        currentLastTakenAt: Date?,
        including takenAt: Date
    ) throws -> Date {
        (
            try modelContext.fetch(FetchDescriptor<PersistentDoseRecord>())
                .filter { $0.medicationID == medicationID }
                .map(\.takenAt)
            + [currentLastTakenAt, takenAt].compactMap { $0 }
        )
        .max() ?? takenAt
    }
}

extension PersistentMedication {
    convenience init(medication: Medication) {
        self.init(
            id: medication.id,
            name: medication.name,
            tabletsRemaining: medication.tabletsRemaining,
            tabletsPerDose: medication.tabletsPerDose,
            bottleColorHex: medication.bottleColorHex,
            classification: medication.classification,
            reminders: medication.reminders.map(PersistentMedicationReminder.init(reminder:)),
            lastTakenAt: medication.lastTakenAt
        )
    }

    var classification: MedicationClassification {
        MedicationClassification(rawValue: classificationRawValue) ?? .prescription
    }

    func update(from medication: Medication) {
        name = medication.name
        tabletsRemaining = MedicationQuantityLimits.tabletCount.clamping(medication.tabletsRemaining)
        tabletsPerDose = MedicationQuantityLimits.doseCount.clamping(medication.tabletsPerDose)
        bottleColorHex = medication.bottleColorHex
        classificationRawValue = medication.classification.rawValue
        lastTakenAt = medication.lastTakenAt
        reminders = medication.reminders.map(PersistentMedicationReminder.init(reminder:))
    }

    func toMedication() -> Medication {
        Medication(
            id: id,
            name: name,
            tabletsRemaining: tabletsRemaining,
            tabletsPerDose: tabletsPerDose,
            bottleColorHex: bottleColorHex,
            classification: classification,
            reminders: reminders.map { $0.toReminder() },
            lastTakenAt: lastTakenAt
        )
    }
}

extension PersistentMedicationReminder {
    convenience init(reminder: Medication.Reminder) {
        self.init(
            id: reminder.id,
            time: reminder.time,
            frequency: reminder.frequency,
            weekdays: reminder.weekdays,
            isActive: reminder.isActive,
            dosageAmount: reminder.dosageAmount
        )
    }

    var frequency: Medication.ReminderFrequency {
        Medication.ReminderFrequency(rawValue: frequencyRawValue) ?? .daily
    }

    var weekdays: Set<Medication.Weekday> {
        let decoded = weekdayRawValues.compactMap(Medication.Weekday.init(rawValue:))
        return decoded.isEmpty ? Set(Medication.Weekday.allCases) : Set(decoded)
    }

    func toReminder() -> Medication.Reminder {
        Medication.Reminder(
            id: id,
            time: time,
            frequency: frequency,
            weekdays: weekdays,
            isActive: isActive,
            dosageAmount: dosageAmount
        )
    }
}

extension PersistentDoseRecord {
    convenience init(doseRecord: DoseRecord) {
        self.init(
            id: doseRecord.id,
            medicationID: doseRecord.medicationID,
            medicationName: doseRecord.medicationName,
            takenAt: doseRecord.takenAt,
            tabletCount: doseRecord.tabletCount
        )
    }

    func toDoseRecord() -> DoseRecord {
        DoseRecord(
            id: id,
            medicationID: medicationID,
            medicationName: medicationName,
            takenAt: takenAt,
            tabletCount: tabletCount
        )
    }
}

enum MedicationStockLevel: String, Codable, Hashable, Sendable {
    case ready
    case low
    case empty
}

struct MedicationHeroContent: Identifiable, Hashable, Sendable {
    var id: Medication.ID
    var name: String
    var classificationText: String
    var bottleColorHex: String
}

/// How a single calendar day scored against what was scheduled for it.
enum MedicationDayAdherence: String, Hashable, Sendable {
    case complete   // logged >= expected
    case partial    // 0 < logged < expected
    case missed     // nothing logged on a past day that expected doses
    case none       // nothing was expected, or the day has not finished yet
}

struct MedicationDayStatus: Hashable, Sendable {
    var expectedDoses: Int
    var loggedDoses: Int
    var adherence: MedicationDayAdherence

    /// ", 1 of 2 doses" — appended to the day cell's accessibility label.
    var accessibilitySuffix: String {
        guard expectedDoses > 0 else {
            return loggedDoses > 0 ? ", \(loggedDoses) dose\(loggedDoses == 1 ? "" : "s")" : ""
        }
        return ", \(loggedDoses) of \(expectedDoses) doses"
    }
}

/// Answers "did I take it today?" for a single medication.
enum MedicationDoseVerdict: String, Hashable, Sendable {
    case takenToday      // a dose was logged today
    case dueNow          // scheduled time has passed today, nothing logged
    case upcoming        // scheduled later today, nothing logged yet
    case noSchedule      // as-needed or no active reminder
}

struct MedicationTodayStatus: Hashable, Sendable {
    var verdict: MedicationDoseVerdict
    var title: String        // "Taken today"
    var detail: String       // "14 doses · latest 2:30 PM"
    var systemImage: String
    /// What is coming, not what happened: "Next tomorrow 8:30 AM · 1 tablet". This card
    /// is the only place the schedule appears, so it has to answer both questions.
    var scheduleDetail: String = ""

    var accessibilityLabel: String {
        scheduleDetail.isEmpty ? "\(title). \(detail)" : "\(title). \(detail). \(scheduleDetail)"
    }
}

struct MedicationStockStatus: Hashable, Sendable {
    /// Days of supply at which a bottle counts as low. The reorder prompt and the low
    /// state are the same threshold, so they cannot drift apart.
    static let refillLeadDays = 7

    var level: MedicationStockLevel
    var title: String
    var message: String
    var remainingCount: Int
    var remainingDoses: Int
    /// Whole days of supply left. `nil` when nothing is scheduled.
    var daysRemaining: Int?
    /// Day the bottle empties. `nil` when nothing is scheduled.
    var runsOutDate: Date?
    /// "18 days left" | "30 tablets left"
    var supplyHeadline: String
    /// "Runs out Aug 24" | "No schedule set"
    var supplyDetail: String
    /// Day to order by to land the refill before the bottle empties. `nil` when nothing
    /// is scheduled, or when that day has already passed — then the card is urgent, not
    /// forward-looking.
    var reorderByDate: Date?

    init(
        level: MedicationStockLevel,
        title: String,
        message: String,
        remainingCount: Int,
        remainingDoses: Int,
        daysRemaining: Int? = nil,
        runsOutDate: Date? = nil,
        supplyHeadline: String = "",
        supplyDetail: String = "",
        reorderByDate: Date? = nil
    ) {
        self.level = level
        self.title = title
        self.message = message
        self.remainingCount = remainingCount
        self.remainingDoses = remainingDoses
        self.daysRemaining = daysRemaining
        self.runsOutDate = runsOutDate
        self.supplyHeadline = supplyHeadline
        self.supplyDetail = supplyDetail
        self.reorderByDate = reorderByDate
    }
}

struct MedicationDetailMetric: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case remaining
        case dose
        case lastTaken
        case doseHistory
    }

    var id: Kind { kind }
    var kind: Kind
    var title: String
    var value: String
    var subtitle: String?
}

struct MedicationReminderSummary: Identifiable, Hashable, Sendable {
    var id: Medication.Reminder.ID
    var title: String
    var scheduleText: String
    var doseText: String
    var nextOccurrenceText: String?
    var isActive: Bool
}

struct MedicationReminderOverview: Hashable, Sendable {
    var title: String
    var subtitle: String
    var activeCount: Int
    var nextReminderText: String?
    /// Next scheduled occurrence. Formatting belongs to the view.
    var nextReminderDate: Date?
    var reminders: [MedicationReminderSummary]

    init(
        title: String,
        subtitle: String,
        activeCount: Int,
        nextReminderText: String? = nil,
        nextReminderDate: Date? = nil,
        reminders: [MedicationReminderSummary]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.activeCount = activeCount
        self.nextReminderText = nextReminderText
        self.nextReminderDate = nextReminderDate
        self.reminders = reminders
    }
}

struct MedicationDetailActions: Hashable, Sendable {
    var canLogDose: Bool
    var canRefill: Bool
    var primaryTitle: String
    var primarySystemImage: String
    var refillTitle: String
    var refillSystemImage: String
    var defaultRefillCount: Int
    /// Drives the outlined "Log another dose" variant.
    var isDoseLoggedToday: Bool

    init(
        canLogDose: Bool,
        canRefill: Bool,
        primaryTitle: String,
        primarySystemImage: String,
        refillTitle: String,
        refillSystemImage: String,
        defaultRefillCount: Int,
        isDoseLoggedToday: Bool = false
    ) {
        self.canLogDose = canLogDose
        self.canRefill = canRefill
        self.primaryTitle = primaryTitle
        self.primarySystemImage = primarySystemImage
        self.refillTitle = refillTitle
        self.refillSystemImage = refillSystemImage
        self.defaultRefillCount = defaultRefillCount
        self.isDoseLoggedToday = isDoseLoggedToday
    }
}

enum MedicationQuantityInputError: LocalizedError, Equatable, Sendable {
    case empty
    case invalidNumber
    case belowMinimum(Int)
    case aboveMaximum(Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            "Enter a quantity."
        case .invalidNumber:
            "Enter a whole number."
        case .belowMinimum(let minimum):
            "Enter a quantity of at least \(minimum)."
        case .aboveMaximum(let maximum):
            "Enter a quantity of \(maximum) or fewer."
        }
    }
}

struct MedicationQuantityInputConfiguration: Hashable, Sendable {
    var range: ClosedRange<Int>
    var step: Int
    var unitSingular: String
    var unitPlural: String

    init(
        range: ClosedRange<Int>,
        step: Int = 1,
        unitSingular: String = "tablet",
        unitPlural: String = "tablets"
    ) {
        self.range = range
        self.step = max(1, step)
        self.unitSingular = unitSingular
        self.unitPlural = unitPlural
    }

    static let tabletCount = MedicationQuantityInputConfiguration(
        range: MedicationQuantityLimits.tabletCount
    )

    static let doseCount = MedicationQuantityInputConfiguration(
        range: MedicationQuantityLimits.doseCount
    )

    func makeState(value: Int) -> MedicationQuantityInputState {
        makeState(text: String(range.clamping(value)))
    }

    func incrementedState(from state: MedicationQuantityInputState) -> MedicationQuantityInputState {
        guard let value = state.value else {
            return makeState(value: correctionValue(for: state))
        }

        return makeState(value: min(value + step, range.upperBound))
    }

    func decrementedState(from state: MedicationQuantityInputState) -> MedicationQuantityInputState {
        guard let value = state.value else {
            return makeState(value: correctionValue(for: state))
        }

        return makeState(value: max(value - step, range.lowerBound))
    }

    func makeState(text: String) -> MedicationQuantityInputState {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return MedicationQuantityInputState(
                text: text,
                value: nil,
                validationError: .empty,
                configuration: self
            )
        }

        guard trimmedText.allSatisfy(\.isNumber), let parsedValue = Int(trimmedText) else {
            return MedicationQuantityInputState(
                text: text,
                value: nil,
                validationError: .invalidNumber,
                configuration: self
            )
        }

        guard parsedValue >= range.lowerBound else {
            return MedicationQuantityInputState(
                text: text,
                value: nil,
                validationError: .belowMinimum(range.lowerBound),
                configuration: self
            )
        }

        guard parsedValue <= range.upperBound else {
            return MedicationQuantityInputState(
                text: text,
                value: nil,
                validationError: .aboveMaximum(range.upperBound),
                configuration: self
            )
        }

        return MedicationQuantityInputState(
            text: text,
            value: parsedValue,
            validationError: nil,
            configuration: self
        )
    }

    private func correctionValue(for state: MedicationQuantityInputState) -> Int {
        switch state.validationError {
        case .some(.aboveMaximum):
            range.upperBound
        case .some(.belowMinimum):
            range.lowerBound
        case .some(.empty), .some(.invalidNumber), nil:
            range.lowerBound
        }
    }
}

struct MedicationQuantityInputState: Equatable, Sendable {
    var text: String
    var value: Int?
    var validationError: MedicationQuantityInputError?
    var configuration: MedicationQuantityInputConfiguration

    var isValid: Bool {
        value != nil && validationError == nil
    }

    var canDecrement: Bool {
        guard let value else { return false }
        return value > configuration.range.lowerBound
    }

    var canIncrement: Bool {
        guard let value else { return false }
        return value < configuration.range.upperBound
    }

    var unitText: String {
        value == 1 ? configuration.unitSingular : configuration.unitPlural
    }

    var accessibilityValue: String {
        guard let value else { return text }
        return "\(value) \(unitText)"
    }
}

struct MedicationDetailSnapshot: Identifiable, Equatable, Sendable {
    var id: Medication.ID { medication.id }
    var medication: Medication
    var hero: MedicationHeroContent
    var todayStatus: MedicationTodayStatus
    var stockStatus: MedicationStockStatus
    var metrics: [MedicationDetailMetric]
    var reminderOverview: MedicationReminderOverview
    var actions: MedicationDetailActions
    var recentDoseRecords: [DoseRecord]
}
