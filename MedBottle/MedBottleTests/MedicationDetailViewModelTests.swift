import Combine
import SwiftData
import XCTest
@testable import MedBottle

@MainActor
final class MedicationDetailViewModelTests: XCTestCase {
    func testSnapshotBuilderClampsEmptyStockAndSortsDoseHistory() {
        let medicationID = UUID()
        let olderDose = DoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: "Atorvastatin",
            takenAt: Date(timeIntervalSince1970: 100),
            tabletCount: 1
        )
        let newerDose = DoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: "Atorvastatin",
            takenAt: Date(timeIntervalSince1970: 200),
            tabletCount: 2
        )
        let medication = makeMedication(
            id: medicationID,
            tabletsRemaining: 0,
            tabletsPerDose: 2
        )
        let builder = MedicationDetailSnapshotBuilder(
            calendar: Calendar(identifier: .gregorian),
            now: { Date(timeIntervalSince1970: 150) }
        )

        let snapshot = builder.makeSnapshot(
            medication: medication,
            doseRecords: [olderDose, newerDose]
        )

        XCTAssertEqual(snapshot.stockStatus.level, .empty)
        XCTAssertEqual(snapshot.stockStatus.remainingCount, 0)
        XCTAssertFalse(snapshot.actions.canLogDose)
        XCTAssertEqual(snapshot.actions.primaryTitle, "Refill bottle")
        XCTAssertEqual(snapshot.recentDoseRecords.map(\.id), [newerDose.id, olderDose.id])
    }

    func testSnapshotBuilderReportsActiveRemindersAndNextScheduledReminder() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_713_360_000)
        let activeReminder = Medication.Reminder(
            time: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!,
            frequency: .daily,
            isActive: true,
            dosageAmount: 1
        )
        let asNeededReminder = Medication.Reminder(
            time: now,
            frequency: .asNeeded,
            isActive: true,
            dosageAmount: 1
        )
        let pausedReminder = Medication.Reminder(
            time: now,
            frequency: .daily,
            isActive: false,
            dosageAmount: 1
        )
        let medication = makeMedication(
            reminders: [activeReminder, asNeededReminder, pausedReminder]
        )
        let builder = MedicationDetailSnapshotBuilder(
            calendar: calendar,
            now: { now }
        )

        let snapshot = builder.makeSnapshot(medication: medication, doseRecords: [])

        XCTAssertEqual(snapshot.reminderOverview.activeCount, 2)
        XCTAssertNotNil(snapshot.reminderOverview.nextReminderText)
        XCTAssertEqual(snapshot.reminderOverview.reminders.count, 3)
    }

    func testSnapshotBuilderClampsReminderDoseTextBeforePluralizing() {
        let reminder = Medication.Reminder(
            frequency: .daily,
            dosageAmount: 0
        )
        let medication = makeMedication(reminders: [reminder])
        let builder = MedicationDetailSnapshotBuilder(
            calendar: Calendar(identifier: .gregorian),
            now: { Date(timeIntervalSince1970: 0) }
        )

        let snapshot = builder.makeSnapshot(medication: medication, doseRecords: [])

        XCTAssertEqual(snapshot.reminderOverview.reminders.first?.doseText, "1 tablet")
    }

    func testViewModelLogDoseUsesCurrentDoseAmountAndRefreshesSnapshot() async {
        let medication = makeMedication(tabletsRemaining: 10, tabletsPerDose: 2)
        let repository = MockMedicationDetailRepository(medication: medication)
        let viewModel = MedicationDetailViewModel(
            medicationID: medication.id,
            repository: repository,
            snapshotBuilder: MedicationDetailSnapshotBuilder(
                calendar: Calendar(identifier: .gregorian),
                now: { Date(timeIntervalSince1970: 0) }
            )
        )

        await viewModel.logDose()

        XCTAssertEqual(repository.loggedDoseAmounts, [2])
        XCTAssertEqual(viewModel.snapshot?.stockStatus.remainingCount, 8)
        XCTAssertEqual(viewModel.snapshot?.recentDoseRecords.count, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testViewModelSurfacesRepositoryErrors() async {
        let medication = makeMedication(tabletsRemaining: 0)
        let repository = MockMedicationDetailRepository(medication: medication)
        let viewModel = MedicationDetailViewModel(
            medicationID: medication.id,
            repository: repository
        )

        await viewModel.logDose()

        XCTAssertEqual(viewModel.errorMessage, MedicationDetailError.outOfStock.localizedDescription)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testMedicationStoreDeletePreservesDoseRecordsForDeletedMedication() throws {
        let deletedMedication = makeMedication(name: "Amlodipine")
        let remainingMedication = makeMedication(name: "Metformin")
        let deletedMedicationRecord = DoseRecord(
            id: UUID(),
            medicationID: deletedMedication.id,
            medicationName: deletedMedication.name,
            takenAt: Date(timeIntervalSince1970: 100),
            tabletCount: 1
        )
        let remainingMedicationRecord = DoseRecord(
            id: UUID(),
            medicationID: remainingMedication.id,
            medicationName: remainingMedication.name,
            takenAt: Date(timeIntervalSince1970: 200),
            tabletCount: 2
        )

        try withMedicationStoreStorage(
            medications: [deletedMedication, remainingMedication],
            doseRecords: [deletedMedicationRecord, remainingMedicationRecord]
        ) {
            let store = MedicationStore()

            let replacementID = store.deleteMedications(
                at: IndexSet(integer: 0),
                selectedID: deletedMedication.id
            )

            XCTAssertEqual(replacementID, remainingMedication.id)
            XCTAssertEqual(store.medications.map(\.id), [remainingMedication.id])
            XCTAssertEqual(store.doseRecords, [deletedMedicationRecord, remainingMedicationRecord])

            let persistedRecords = try XCTUnwrap(
                UserDefaults.standard.data(forKey: MedicationStore.doseRecordsStorageKey)
            )
            XCTAssertEqual(
                try JSONDecoder().decode([DoseRecord].self, from: persistedRecords),
                [deletedMedicationRecord, remainingMedicationRecord]
            )
        }
    }

    func testMedicationStoreDeleteLastMedicationKeepsPreservedDoseHistoryAndClearsSelection() throws {
        let medication = makeMedication(name: "Amlodipine")
        let doseRecord = DoseRecord(
            id: UUID(),
            medicationID: medication.id,
            medicationName: medication.name,
            takenAt: Date(timeIntervalSince1970: 100),
            tabletCount: 1
        )

        try withMedicationStoreStorage(
            medications: [medication],
            doseRecords: [doseRecord]
        ) {
            let store = MedicationStore()

            let replacementID = store.deleteMedications(
                at: IndexSet(integer: 0),
                selectedID: medication.id
            )

            XCTAssertNil(replacementID)
            XCTAssertTrue(store.medications.isEmpty)
            XCTAssertEqual(store.doseRecords, [doseRecord])
        }
    }

    func testSwiftDataDeletePreservesPersistentDoseRecordsForDeletedMedication() throws {
        let schema = Schema([
            PersistentMedication.self,
            PersistentMedicationReminder.self,
            PersistentDoseRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let medicationID = UUID()
        let medication = PersistentMedication(
            id: medicationID,
            name: "Amlodipine",
            tabletsRemaining: 30,
            tabletsPerDose: 1,
            bottleColorHex: "3A8E84",
            medicationShape: .tablet,
            classification: .prescription,
            reminders: [
                PersistentMedicationReminder(
                    time: Date(timeIntervalSince1970: 0),
                    dosageAmount: 1
                )
            ]
        )
        let doseRecord = PersistentDoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: "Amlodipine",
            takenAt: Date(timeIntervalSince1970: 100),
            tabletCount: 1
        )
        context.insert(medication)
        context.insert(doseRecord)
        try context.save()

        let persistence = SwiftDataActiveMedicationStore(modelContext: context)
        try persistence.deleteMedicationPreservingDoseHistory(id: medicationID)

        XCTAssertTrue(try context.fetch(FetchDescriptor<PersistentMedication>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersistentMedicationReminder>()).isEmpty)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PersistentDoseRecord>()).map { $0.toDoseRecord() },
            [doseRecord.toDoseRecord()]
        )
        XCTAssertEqual(
            try persistence.doseRecords(forMedicationID: medicationID),
            [doseRecord.toDoseRecord()]
        )
    }

    func testSwiftDataDeleteMissingMedicationLeavesDoseRecordsUntouched() throws {
        let schema = Schema([
            PersistentMedication.self,
            PersistentMedicationReminder.self,
            PersistentDoseRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let medicationID = UUID()
        let doseRecord = PersistentDoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: "Deleted Amlodipine",
            takenAt: Date(timeIntervalSince1970: 100),
            tabletCount: 1
        )
        context.insert(doseRecord)
        try context.save()

        let persistence = SwiftDataActiveMedicationStore(modelContext: context)

        XCTAssertThrowsError(try persistence.deleteMedicationPreservingDoseHistory(id: medicationID)) { error in
            XCTAssertEqual(error as? MedicationPersistenceError, .medicationNotFound)
        }
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PersistentDoseRecord>()).map { $0.toDoseRecord() },
            [doseRecord.toDoseRecord()]
        )
    }

    func testSelectionViewModelStartsWithFirstMedicationWhenNoInitialSelection() {
        let medications = [
            makeMedication(name: "Amlodipine"),
            makeMedication(name: "Metformin")
        ]
        let repository = MockMedicationSelectionRepository(medications: medications)

        let viewModel = MedicationSelectionViewModel(repository: repository)

        XCTAssertEqual(viewModel.selectedMedicationID, medications[0].id)
        XCTAssertEqual(viewModel.selectedMedication, medications[0])
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.pageCount, 2)
        XCTAssertFalse(viewModel.canMovePrevious)
        XCTAssertTrue(viewModel.canMoveNext)
    }

    func testSelectionViewModelMovesAndSelectsByID() {
        let medications = [
            makeMedication(name: "Amlodipine"),
            makeMedication(name: "Metformin"),
            makeMedication(name: "Lisinopril")
        ]
        let repository = MockMedicationSelectionRepository(medications: medications)
        let viewModel = MedicationSelectionViewModel(repository: repository)

        XCTAssertEqual(viewModel.moveNext(), .success(medications[1]))
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertTrue(viewModel.canMovePrevious)
        XCTAssertTrue(viewModel.canMoveNext)

        XCTAssertEqual(viewModel.selectMedication(id: medications[2].id), .success(medications[2]))
        XCTAssertEqual(viewModel.selectedIndex, 2)
        XCTAssertFalse(viewModel.canMoveNext)

        XCTAssertEqual(viewModel.movePrevious(), .success(medications[1]))
        XCTAssertEqual(viewModel.selectedMedicationID, medications[1].id)
    }

    func testSelectionViewModelKeepsSelectedMedicationAfterReorder() async {
        let selectedMedication = makeMedication(name: "Metformin")
        let medications = [
            makeMedication(name: "Amlodipine"),
            selectedMedication,
            makeMedication(name: "Lisinopril")
        ]
        let repository = MockMedicationSelectionRepository(medications: medications)
        let viewModel = MedicationSelectionViewModel(
            repository: repository,
            initiallySelectedID: selectedMedication.id
        )

        repository.medications = [medications[2], medications[0], selectedMedication]
        await Task.yield()

        XCTAssertEqual(viewModel.selectedMedicationID, selectedMedication.id)
        XCTAssertEqual(viewModel.selectedMedication, selectedMedication)
        XCTAssertEqual(viewModel.selectedIndex, 2)
    }

    func testSelectionViewModelSelectsNearestMedicationWhenSelectedMedicationIsDeleted() async {
        let medications = [
            makeMedication(name: "Amlodipine"),
            makeMedication(name: "Metformin"),
            makeMedication(name: "Lisinopril")
        ]
        let repository = MockMedicationSelectionRepository(medications: medications)
        let viewModel = MedicationSelectionViewModel(
            repository: repository,
            initiallySelectedID: medications[1].id
        )

        repository.medications = [medications[0], medications[2]]
        await Task.yield()

        XCTAssertEqual(viewModel.selectedMedicationID, medications[2].id)
        XCTAssertEqual(viewModel.selectedIndex, 1)
        XCTAssertEqual(viewModel.pageCount, 2)
    }

    func testSelectionViewModelClearsSelectionWhenMedicationListBecomesEmpty() async {
        let medications = [makeMedication(name: "Amlodipine")]
        let repository = MockMedicationSelectionRepository(medications: medications)
        let viewModel = MedicationSelectionViewModel(repository: repository)

        repository.medications = []
        await Task.yield()

        XCTAssertNil(viewModel.selectedMedicationID)
        XCTAssertNil(viewModel.selectedMedication)
        XCTAssertNil(viewModel.selectedIndex)
        XCTAssertEqual(viewModel.pageCount, 0)
        XCTAssertFalse(viewModel.canMovePrevious)
        XCTAssertFalse(viewModel.canMoveNext)
    }

    func testSelectionViewModelSurfacesSelectionErrorsWithoutChangingSelection() {
        let medication = makeMedication(name: "Amlodipine")
        let repository = MockMedicationSelectionRepository(medications: [medication])
        let viewModel = MedicationSelectionViewModel(repository: repository)

        XCTAssertEqual(viewModel.movePrevious(), .failure(.alreadyAtFirstMedication))
        XCTAssertEqual(viewModel.selectedMedicationID, medication.id)
        XCTAssertEqual(viewModel.errorMessage, MedicationSelectionError.alreadyAtFirstMedication.localizedDescription)

        viewModel.clearError()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectMedication(id: UUID()), .failure(.medicationNotFound))
        XCTAssertEqual(viewModel.selectedMedicationID, medication.id)
        XCTAssertEqual(viewModel.errorMessage, MedicationSelectionError.medicationNotFound.localizedDescription)
    }

    private func makeMedication(
        id: UUID = UUID(),
        name: String = "Atorvastatin",
        tabletsRemaining: Int = 30,
        tabletsPerDose: Int = 1,
        reminders: [Medication.Reminder] = [],
        lastTakenAt: Date? = nil
    ) -> Medication {
        Medication(
            id: id,
            name: name,
            tabletsRemaining: tabletsRemaining,
            tabletsPerDose: tabletsPerDose,
            bottleColorHex: "3A8E84",
            medicationShape: .tablet,
            classification: .prescription,
            reminders: reminders,
            lastTakenAt: lastTakenAt
        )
    }

    private func withMedicationStoreStorage(
        medications: [Medication],
        doseRecords: [DoseRecord],
        perform operation: () throws -> Void
    ) throws {
        let defaults = UserDefaults.standard
        let previousMedications = defaults.data(forKey: MedicationStore.medicationsStorageKey)
        let previousDoseRecords = defaults.data(forKey: MedicationStore.doseRecordsStorageKey)

        defer {
            restore(previousMedications, forKey: MedicationStore.medicationsStorageKey)
            restore(previousDoseRecords, forKey: MedicationStore.doseRecordsStorageKey)
        }

        defaults.set(try JSONEncoder().encode(medications), forKey: MedicationStore.medicationsStorageKey)
        defaults.set(try JSONEncoder().encode(doseRecords), forKey: MedicationStore.doseRecordsStorageKey)

        try operation()
    }

    private func restore(_ data: Data?, forKey key: String) {
        let defaults = UserDefaults.standard

        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

@MainActor
private final class MockMedicationSelectionRepository: MedicationSelectionRepository {
    @Published var medications: [Medication]

    var medicationsPublisher: AnyPublisher<[Medication], Never> {
        $medications.eraseToAnyPublisher()
    }

    init(medications: [Medication]) {
        self.medications = medications
    }
}

@MainActor
private final class MockMedicationDetailRepository: MedicationDetailRepository {
    private var medicationValue: Medication
    private var records: [DoseRecord] = []
    private(set) var loggedDoseAmounts: [Int] = []

    init(medication: Medication) {
        self.medicationValue = medication
    }

    func medication(id: Medication.ID) async throws -> Medication {
        guard medicationValue.id == id else { throw MedicationDetailError.medicationNotFound }
        return medicationValue
    }

    func doseRecords(forMedicationID medicationID: Medication.ID) async throws -> [DoseRecord] {
        records.filter { $0.medicationID == medicationID }
    }

    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date) async throws -> Medication {
        guard medicationValue.id == medicationID else { throw MedicationDetailError.medicationNotFound }
        guard medicationValue.tabletsRemaining > 0 else { throw MedicationDetailError.outOfStock }

        let dose = max(1, dosageAmount)
        loggedDoseAmounts.append(dose)
        medicationValue.tabletsRemaining = max(0, medicationValue.tabletsRemaining - dose)
        medicationValue.lastTakenAt = takenAt
        records.insert(
            DoseRecord(
                id: UUID(),
                medicationID: medicationID,
                medicationName: medicationValue.name,
                takenAt: takenAt,
                tabletCount: dose
            ),
            at: 0
        )
        return medicationValue
    }

    func refill(medicationID: Medication.ID, to count: Int) async throws -> Medication {
        guard medicationValue.id == medicationID else { throw MedicationDetailError.medicationNotFound }
        guard count >= 0 else { throw MedicationDetailError.invalidRefillCount }

        medicationValue.tabletsRemaining = count
        return medicationValue
    }
}
