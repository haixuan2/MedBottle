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

/// Everything undo needs, captured at log time.
struct MedicationDoseLogResult: Equatable, Sendable {
    var medication: Medication
    var record: DoseRecord
    var previousTabletsRemaining: Int
}

@MainActor
protocol MedicationDetailRepository {
    func medication(id: Medication.ID) async throws -> Medication
    func doseRecords(forMedicationID medicationID: Medication.ID) async throws -> [DoseRecord]
    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date) async throws -> MedicationDoseLogResult
    func undoDose(
        medicationID: Medication.ID,
        recordID: DoseRecord.ID,
        restoringTabletsTo count: Int
    ) async throws -> Medication
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
        guard store != nil else { throw MedicationDetailError.storeUnavailable }
        return currentDoseRecords(forMedicationID: medicationID)
    }

    /// The same read without the suspension. The store is in memory, so a screen being
    /// built can have its records now rather than one runloop turn from now.
    func currentDoseRecords(forMedicationID medicationID: Medication.ID) -> [DoseRecord] {
        guard let store else { return [] }
        return store.doseRecords
            .filter { $0.medicationID == medicationID }
            .sorted { $0.takenAt > $1.takenAt }
    }

    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date = Date()) async throws -> MedicationDoseLogResult {
        guard let store else { throw MedicationDetailError.storeUnavailable }
        let medication = try currentMedication(id: medicationID)

        guard medication.tabletsRemaining > 0 else {
            throw MedicationDetailError.outOfStock
        }

        guard let record = store.logDose(
            forMedicationID: medicationID,
            dosageAmount: max(1, dosageAmount),
            takenAt: takenAt
        ) else {
            throw MedicationDetailError.medicationNotFound
        }

        return MedicationDoseLogResult(
            medication: try currentMedication(id: medicationID),
            record: record,
            previousTabletsRemaining: medication.tabletsRemaining
        )
    }

    func undoDose(
        medicationID: Medication.ID,
        recordID: DoseRecord.ID,
        restoringTabletsTo count: Int
    ) async throws -> Medication {
        guard let store else { throw MedicationDetailError.storeUnavailable }
        _ = try currentMedication(id: medicationID)

        store.undoDose(
            medicationID: medicationID,
            recordID: recordID,
            restoringTabletsTo: count
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
    /// The dose that can still be reversed. Cleared automatically after `undoWindow`.
    @Published private(set) var undoableDose: DoseRecord?

    static let undoWindow: Duration = .seconds(5)

    private let medicationID: Medication.ID
    private let repository: MedicationDetailRepository
    private let snapshotBuilder: MedicationDetailSnapshotBuilding
    private let refillQuantityConfiguration: MedicationQuantityInputConfiguration
    private let now: @Sendable () -> Date
    private var hasEditedRefillQuantity = false
    private var undoTabletsRemaining: Int?
    private var undoExpirationTask: Task<Void, Never>?

    var latestAllowedManualDoseDate: Date {
        now()
    }

    init(
        medicationID: Medication.ID,
        repository: MedicationDetailRepository,
        snapshotBuilder: MedicationDetailSnapshotBuilding = MedicationDetailSnapshotBuilder(),
        refillQuantityConfiguration: MedicationQuantityInputConfiguration = .tabletCount,
        initialSnapshot: MedicationDetailSnapshot? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.medicationID = medicationID
        self.repository = repository
        self.snapshotBuilder = snapshotBuilder
        self.refillQuantityConfiguration = refillQuantityConfiguration
        self.now = now
        self.snapshot = initialSnapshot
        self.refillQuantity = refillQuantityConfiguration.makeState(
            value: initialSnapshot?.medication.tabletsRemaining ?? refillQuantityConfiguration.range.lowerBound
        )
    }

    convenience init(
        medication: Medication,
        store: MedicationStore,
        snapshotBuilder: MedicationDetailSnapshotBuilding = MedicationDetailSnapshotBuilder()
    ) {
        let repository = MedicationStoreDetailRepository(store: store)

        self.init(
            medicationID: medication.id,
            repository: repository,
            snapshotBuilder: snapshotBuilder,
            // Paging builds a screen as it scrolls into view. Without a snapshot in
            // hand it would enter showing the loading card and pop to its content a
            // frame later — visible jank on every swipe onto a new medication.
            initialSnapshot: snapshotBuilder.makeSnapshot(
                medication: medication,
                doseRecords: repository.currentDoseRecords(forMedicationID: medication.id)
            )
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

        var logResult: MedicationDoseLogResult?

        await performLoadingOperation {
            let currentMedication = try await repository.medication(id: medicationID)
            logResult = try await repository.logDose(
                medicationID: medicationID,
                dosageAmount: currentMedication.tabletsPerDose,
                takenAt: takenAt
            )
            return try await loadSnapshot()
        }

        guard errorMessage == nil, let logResult else { return }
        armUndo(for: logResult)
    }

    /// Reverses the dose still inside the undo window.
    func undoLastDose() {
        Task { await undoLastDose() }
    }

    func undoLastDose() async {
        guard let undoableDose, let undoTabletsRemaining else { return }

        cancelUndo()

        await performLoadingOperation {
            _ = try await repository.undoDose(
                medicationID: medicationID,
                recordID: undoableDose.id,
                restoringTabletsTo: undoTabletsRemaining
            )
            return try await loadSnapshot()
        }
    }

    /// Call when the detail view disappears so a stale bar cannot outlive the screen.
    func cancelUndo() {
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
        undoableDose = nil
        undoTabletsRemaining = nil
    }

    private func armUndo(for logResult: MedicationDoseLogResult) {
        undoExpirationTask?.cancel()
        undoableDose = logResult.record
        undoTabletsRemaining = logResult.previousTabletsRemaining

        let recordID = logResult.record.id
        undoExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            guard let self, undoableDose?.id == recordID else { return }
            cancelUndo()
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

/// Scores logged doses against what the active reminders expected, per day.
/// Shared by the calendar's day markers and the streak in the day summary.
struct MedicationAdherenceCalculator {
    var calendar: Calendar
    var now: @Sendable () -> Date

    init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    /// Scheduled occurrences — a reminder for 2 tablets is still one dose.
    func expectedDoseCount(for medications: [Medication], on date: Date) -> Int {
        guard let weekday = Medication.Weekday(rawValue: calendar.component(.weekday, from: date)) else {
            return 0
        }

        return medications.reduce(0) { total, medication in
            total + medication.reminders.filter { reminder in
                guard reminder.isActive else { return false }

                switch reminder.frequency {
                case .daily:
                    return true
                case .specificDays:
                    return reminder.weekdays.isEmpty || reminder.weekdays.contains(weekday)
                case .asNeeded:
                    return false
                }
            }.count
        }
    }

    func dayStatus(expectedDoses: Int, loggedDoses: Int, on date: Date) -> MedicationDayStatus {
        let adherence: MedicationDayAdherence

        if expectedDoses == 0 {
            adherence = .none
        } else if loggedDoses >= expectedDoses {
            adherence = .complete
        } else if loggedDoses > 0 {
            adherence = .partial
        } else if calendar.startOfDay(for: date) < calendar.startOfDay(for: now()) {
            adherence = .missed
        } else {
            // Today is still in progress — not missed yet.
            adherence = .none
        }

        return MedicationDayStatus(
            expectedDoses: expectedDoses,
            loggedDoses: loggedDoses,
            adherence: adherence
        )
    }

    /// Consecutive complete days ending today. Days that expected nothing are skipped
    /// rather than counted or treated as breaks, and today still in progress does not
    /// end a streak earned yesterday.
    func currentStreak(
        medications: [Medication],
        loggedDosesByDay: [Date: Int],
        maximumLookbackDays: Int = 400
    ) -> Int {
        var streak = 0
        var day = calendar.startOfDay(for: now())

        for offset in 0..<maximumLookbackDays {
            let expected = expectedDoseCount(for: medications, on: day)
            let logged = loggedDosesByDay[day] ?? 0

            if expected == 0 {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
                continue
            }

            if logged >= expected {
                streak += 1
            } else if offset == 0 {
                // Today has not finished; fall through to yesterday.
            } else {
                break
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
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
        let reminderOverview = makeReminderOverview(for: medication)
        let todayStatus = makeTodayStatus(
            for: medication,
            doseRecords: sortedDoseRecords,
            reminderOverview: reminderOverview
        )

        return MedicationDetailSnapshot(
            medication: medication,
            hero: MedicationHeroContent(
                id: medication.id,
                name: medication.name,
                classificationText: medication.classification.title,
                bottleColorHex: medication.bottleColorHex
            ),
            todayStatus: todayStatus,
            stockStatus: stockStatus,
            metrics: makeMetrics(for: medication, doseRecords: sortedDoseRecords, stockStatus: stockStatus),
            reminderOverview: reminderOverview,
            actions: makeActions(for: medication, todayStatus: todayStatus),
            recentDoseRecords: Array(sortedDoseRecords.prefix(5))
        )
    }

    /// Doses expected per day from active, scheduled reminders. 0 when as-needed/none.
    func dosesPerDay(for medication: Medication) -> Double {
        medication.reminders.reduce(into: 0.0) { total, reminder in
            guard reminder.isActive else { return }

            switch reminder.frequency {
            case .daily:
                total += 1
            case .specificDays:
                total += Double(reminder.weekdays.count) / 7.0
            case .asNeeded:
                break
            }
        }
    }

    /// Also used by Manage Medications, which shows the supply headline per row.
    func makeStockStatus(for medication: Medication) -> MedicationStockStatus {
        let remaining = max(0, medication.tabletsRemaining)
        let dose = max(1, medication.tabletsPerDose)
        let fullDoses = remaining / dose
        let tabletsPerDay = Double(dose) * dosesPerDay(for: medication)

        let daysRemaining: Int? = tabletsPerDay > 0
            ? Int((Double(remaining) / tabletsPerDay).rounded(.down))
            : nil
        let runsOut = daysRemaining.flatMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now()))
        }

        let supplyHeadline: String
        if let daysRemaining {
            supplyHeadline = "\(daysRemaining) \(dayText(daysRemaining)) left"
        } else {
            supplyHeadline = "\(remaining) \(tabletText(remaining)) left"
        }

        let supplyDetail = runsOut.map { "Runs out \(monthDayText($0))" } ?? "No schedule set"

        // Ordering on the day it empties is already too late; back off the same lead time
        // that decides when the bottle counts as low. Once that day has passed the card
        // is showing urgency instead, so there is nothing to plan.
        let reorderBy = runsOut
            .flatMap { calendar.date(byAdding: .day, value: -MedicationStockStatus.refillLeadDays, to: $0) }
            .flatMap { $0 > now() ? $0 : nil }

        func status(level: MedicationStockLevel, title: String, message: String) -> MedicationStockStatus {
            MedicationStockStatus(
                level: level,
                title: title,
                message: message,
                remainingCount: remaining,
                remainingDoses: fullDoses,
                daysRemaining: daysRemaining,
                runsOutDate: runsOut,
                supplyHeadline: supplyHeadline,
                supplyDetail: supplyDetail,
                reorderByDate: reorderBy
            )
        }

        if remaining == 0 {
            return status(
                level: .empty,
                title: "Empty",
                message: "Refill this bottle before the next dose."
            )
        }

        if let daysRemaining {
            if daysRemaining <= MedicationStockStatus.refillLeadDays {
                return status(
                    level: .low,
                    title: "Refill soon",
                    message: "Only \(daysRemaining) \(dayText(daysRemaining)) left — order a refill now."
                )
            }

            return status(
                level: .ready,
                title: "On hand",
                message: runsOut.map { "Enough until \(monthDayText($0))." } ?? "No schedule set."
            )
        }

        if fullDoses <= 3 {
            return status(
                level: .low,
                title: "Refill soon",
                message: fullDoses == 0
                    ? "Less than one full dose remains — order a refill now."
                    : "Only \(fullDoses) full \(fullDoses == 1 ? "dose" : "doses") left — order a refill now."
            )
        }

        return status(
            level: .ready,
            title: "On hand",
            message: "No schedule set."
        )
    }

    private func makeTodayStatus(
        for medication: Medication,
        doseRecords: [DoseRecord],
        reminderOverview: MedicationReminderOverview
    ) -> MedicationTodayStatus {
        var status = makeTodayVerdict(
            for: medication,
            doseRecords: doseRecords,
            reminderOverview: reminderOverview
        )

        status.scheduleDetail = makeScheduleDetail(
            for: medication,
            overview: reminderOverview,
            verdict: status.verdict
        )

        return status
    }

    /// "Next tomorrow 8:30 AM · 1 tablet" — or the cadence alone when the title already
    /// names the time, and whatever the reminder overview says when nothing is scheduled.
    private func makeScheduleDetail(
        for medication: Medication,
        overview: MedicationReminderOverview,
        verdict: MedicationDoseVerdict
    ) -> String {
        guard
            let nextReminderDate = overview.nextReminderDate,
            verdict != .upcoming,
            let lead = leadReminder(for: medication, nextReminder: nextReminderDate)
        else {
            return overview.subtitle
        }

        let doseAmount = max(1, lead.dosageAmount)
        return "Next \(relativeDateTimeText(nextReminderDate)) · \(doseAmount) tablet\(doseAmount == 1 ? "" : "s")"
    }

    private func makeTodayVerdict(
        for medication: Medication,
        doseRecords: [DoseRecord],
        reminderOverview: MedicationReminderOverview
    ) -> MedicationTodayStatus {
        let today = doseRecords
            .filter { isToday($0.takenAt) }
            .sorted { $0.takenAt < $1.takenAt }

        let scheduledReminders = medication.reminders.filter { $0.isActive && $0.frequency != .asNeeded }

        if !today.isEmpty {
            return MedicationTodayStatus(
                verdict: .takenToday,
                title: "Taken today",
                detail: takenTodayDetail(today),
                systemImage: "checkmark.circle.fill"
            )
        }

        guard !scheduledReminders.isEmpty else {
            return MedicationTodayStatus(
                verdict: .noSchedule,
                title: "As needed",
                detail: lastTakenDetail(for: medication.lastTakenAt),
                systemImage: "pills"
            )
        }

        let occurrencesToday = scheduledReminders
            .compactMap { $0.detailOccurrenceToday(now: now(), calendar: calendar) }
            .sorted()

        if let latestPassed = occurrencesToday.last(where: { $0 <= now() }) {
            return MedicationTodayStatus(
                verdict: .dueNow,
                title: "Due now",
                detail: "\(timeText(latestPassed)) dose not logged",
                systemImage: "exclamationmark.circle.fill"
            )
        }

        if let nextToday = occurrencesToday.first(where: { $0 > now() }) {
            return MedicationTodayStatus(
                verdict: .upcoming,
                title: "Due at \(timeText(nextToday))",
                detail: "Nothing logged yet today",
                systemImage: "clock"
            )
        }

        // Scheduled, but not on this weekday.
        if let nextReminderDate = reminderOverview.nextReminderDate {
            return MedicationTodayStatus(
                verdict: .upcoming,
                title: "Due \(relativeDateTimeText(nextReminderDate))",
                detail: "Nothing logged yet today",
                systemImage: "clock"
            )
        }

        return MedicationTodayStatus(
            verdict: .noSchedule,
            title: "As needed",
            detail: lastTakenDetail(for: medication.lastTakenAt),
            systemImage: "pills"
        )
    }

    /// Beyond a handful of doses the individual times stop being information and start
    /// being a wall of text that pushes the rest of the screen down, so the card keeps
    /// the count and the most recent time instead of every timestamp.
    private static let takenTodayTimeLimit = 3

    private func takenTodayDetail(_ today: [DoseRecord]) -> String {
        let times = today.map { timeText($0.takenAt) }

        if today.count > Self.takenTodayTimeLimit {
            let latest = times.last ?? ""
            return "\(today.count) doses · latest \(latest)"
        }

        if today.count > 1 {
            return "\(today.count) doses · \(times.joined(separator: ", "))"
        }

        // The next dose lives on the status line now, so this stays purely a record of
        // what happened today.
        return times.first ?? "Logged today"
    }

    private func lastTakenDetail(for date: Date?) -> String {
        guard let date else { return "No doses logged yet" }

        if isToday(date) {
            return "Last taken today, \(timeText(date))"
        }

        if isYesterday(date) {
            return "Last taken yesterday, \(timeText(date))"
        }

        return "Last taken \(date.formatted(date: .abbreviated, time: .shortened))"
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
            subtitle: reminderSubtitle(for: medication, nextReminder: nextReminder),
            activeCount: activeSummaries.count,
            nextReminderText: nextReminder.map { "Next: \(shortDateTime($0))" },
            nextReminderDate: nextReminder,
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

    private func makeActions(
        for medication: Medication,
        todayStatus: MedicationTodayStatus
    ) -> MedicationDetailActions {
        let canLogDose = medication.tabletsRemaining > 0
        let isDoseLoggedToday = todayStatus.verdict == .takenToday
        let defaultRefillCount = max(30, medication.tabletsRemaining + max(1, medication.tabletsPerDose) * 30)

        let primaryTitle: String
        let primarySystemImage: String
        switch (canLogDose, isDoseLoggedToday) {
        case (false, _):
            primaryTitle = "Refill bottle"
            primarySystemImage = "arrow.triangle.2.circlepath"
        case (true, true):
            primaryTitle = "Log another dose"
            primarySystemImage = "plus"
        case (true, false):
            primaryTitle = "Log dose"
            primarySystemImage = "checkmark"
        }

        return MedicationDetailActions(
            canLogDose: canLogDose,
            canRefill: true,
            primaryTitle: primaryTitle,
            primarySystemImage: primarySystemImage,
            refillTitle: "Refill",
            refillSystemImage: "plus.circle",
            defaultRefillCount: defaultRefillCount,
            isDoseLoggedToday: isDoseLoggedToday
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

        if isToday(date) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }

        if isYesterday(date) {
            return "Yesterday, \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func shortDateTime(_ date: Date) -> String {
        if isToday(date) {
            return "Today at \(date.formatted(date: .omitted, time: .shortened))"
        }

        if isTomorrow(date) {
            return "Tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        }

        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    // `Calendar.isDateInToday` and friends read the system clock, which ignores the
    // injected `now`. These relative checks stay honest under a fixed clock.
    private func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: now())
    }

    private func isYesterday(_ date: Date) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now()) else { return false }
        return calendar.isDate(date, inSameDayAs: yesterday)
    }

    private func isTomorrow(_ date: Date) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now()) else { return false }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func monthDayText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }

    /// "today 8:30 PM" | "tomorrow 8:30 AM" | "Thu 8:30 AM" — reads inline after "next" or "Due".
    private func relativeDateTimeText(_ date: Date) -> String {
        if isToday(date) {
            return "today \(timeText(date))"
        }

        if isTomorrow(date) {
            return "tomorrow \(timeText(date))"
        }

        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func dayText(_ count: Int) -> String {
        count == 1 ? "day" : "days"
    }

    private func reminderTitle(activeCount: Int, totalCount: Int) -> String {
        if totalCount == 0 { return "No reminders" }
        if activeCount == 0 { return "Reminders paused" }
        return activeCount == 1 ? "1 active reminder" : "\(activeCount) active reminders"
    }

    /// `Everyday · 1 tablet` / `Mon, Wed, Fri · 2 tablets` / `As needed` / `All reminders paused` / `No schedule set`
    private func reminderSubtitle(for medication: Medication, nextReminder: Date?) -> String {
        guard !medication.reminders.isEmpty else { return "No schedule set" }

        let activeReminders = medication.reminders.filter(\.isActive)
        guard !activeReminders.isEmpty else { return "All reminders paused" }

        guard let leadReminder = leadReminder(for: medication, nextReminder: nextReminder) else {
            return "As needed"
        }

        let doseAmount = max(1, leadReminder.dosageAmount)
        let doseText = "\(doseAmount) tablet\(doseAmount == 1 ? "" : "s")"

        switch leadReminder.frequency {
        case .daily:
            return "Everyday · \(doseText)"
        case .specificDays:
            let days = leadReminder.weekdays
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.shortTitle)
                .joined(separator: ", ")
            return "\(days.isEmpty ? "Custom days" : days) · \(doseText)"
        case .asNeeded:
            return "As needed"
        }
    }

    /// The scheduled reminder the next dose comes from — the one that fires next, or the
    /// earliest of the day when nothing is pending. `nil` when nothing is scheduled.
    private func leadReminder(for medication: Medication, nextReminder: Date?) -> Medication.Reminder? {
        let scheduled = medication.reminders.filter { $0.isActive && $0.frequency != .asNeeded }
        guard !scheduled.isEmpty else { return nil }

        return scheduled.first {
            $0.detailNextOccurrence(from: now(), calendar: calendar) == nextReminder
        } ?? scheduled.sorted { $0.time < $1.time }[0]
    }

    private func tabletText(_ count: Int) -> String {
        count == 1 ? "tablet" : "tablets"
    }
}

private extension Medication.Reminder {
    /// This reminder's time mapped onto today, past or future. `nil` when it does not fire today.
    func detailOccurrenceToday(now: Date, calendar: Calendar) -> Date? {
        guard isActive, frequency != .asNeeded else { return nil }

        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let validWeekdays: Set<Medication.Weekday> = frequency == .daily
            ? Set(Medication.Weekday.allCases)
            : (weekdays.isEmpty ? Set(Medication.Weekday.allCases) : weekdays)

        guard let today = Medication.Weekday(rawValue: calendar.component(.weekday, from: now)),
              validWeekdays.contains(today) else {
            return nil
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

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
