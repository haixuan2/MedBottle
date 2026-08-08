import Combine
import SwiftData
import SwiftUI
import XCTest
@testable import MedBottle

@MainActor
final class MedicationDetailViewModelTests: XCTestCase {
    func testStockCardRestoresStatusTitleMessageAndAccessibilitySummary() {
        let scenarios: [(MedicationStockStatus, String)] = [
            (
                MedicationStockStatus(
                    level: .ready,
                    title: "On hand",
                    message: "5 full doses available.",
                    remainingCount: 10,
                    remainingDoses: 5
                ),
                "tablets"
            ),
            (
                MedicationStockStatus(
                    level: .low,
                    title: "Low stock",
                    message: "1 full dose left.",
                    remainingCount: 1,
                    remainingDoses: 1
                ),
                "tablet"
            ),
            (
                MedicationStockStatus(
                    level: .empty,
                    title: "Empty",
                    message: "Refill this bottle before the next dose.",
                    remainingCount: 0,
                    remainingDoses: 0
                ),
                "tablets"
            )
        ]

        for (status, expectedTabletLabel) in scenarios {
            let card = MedicationStockCard(
                status: status,
                tint: .blue,
                isHighlighted: false,
                refillAction: {}
            )

            XCTAssertEqual(card.titleText, status.title)
            XCTAssertEqual(card.messageText, status.message)
            XCTAssertEqual(card.tabletLabel, expectedTabletLabel)
            XCTAssertEqual(
                card.accessibilitySummary,
                "Remaining, \(status.remainingCount) \(expectedTabletLabel). \(status.title). \(status.message)"
            )
        }
    }

    /// The row used to end in a hardcoded "refill reminder at 7 days" for every bottle.
    /// It now says the two things that actually vary: what is left, and when to act.
    func testStockCardRowStatesDosesOnlyWhenADoseIsMoreThanOneTablet() {
        let single = MedicationStockCard(
            status: MedicationStockStatus(
                level: .ready,
                title: "On hand",
                message: "Enough until Aug 24.",
                remainingCount: 16,
                remainingDoses: 16,
                daysRemaining: 16
            ),
            tint: .blue,
            tabletsPerDose: 1,
            isHighlighted: false,
            refillAction: {}
        )
        XCTAssertEqual(single.rowSummaryText, "16 tablets left")

        let multiple = MedicationStockCard(
            status: MedicationStockStatus(
                level: .ready,
                title: "On hand",
                message: "Enough until Aug 24.",
                remainingCount: 16,
                remainingDoses: 8,
                daysRemaining: 8
            ),
            tint: .blue,
            tabletsPerDose: 2,
            isHighlighted: false,
            refillAction: {}
        )
        XCTAssertEqual(multiple.rowSummaryText, "16 tablets left · 8 doses at 2 per dose")
    }

    func testStockCardSecondLineReordersWhenHealthyAndWarnsWhenNot() {
        let reorderBy = Date(timeIntervalSince1970: 1_775_000_000)
        let healthy = MedicationStockCard(
            status: MedicationStockStatus(
                level: .ready,
                title: "On hand",
                message: "Enough until Apr 8.",
                remainingCount: 30,
                remainingDoses: 30,
                daysRemaining: 30,
                reorderByDate: reorderBy
            ),
            tint: .blue,
            isHighlighted: false,
            refillAction: {}
        )
        XCTAssertEqual(
            healthy.secondaryText,
            "Order by \(reorderBy.formatted(.dateTime.month().day())) to avoid running out"
        )

        // Past the reorder day the builder stops supplying one; the row goes quiet rather
        // than telling someone to order by a date that has gone.
        let unscheduled = MedicationStockCard(
            status: MedicationStockStatus(
                level: .ready,
                title: "On hand",
                message: "No schedule set.",
                remainingCount: 30,
                remainingDoses: 30
            ),
            tint: .blue,
            isHighlighted: false,
            refillAction: {}
        )
        XCTAssertNil(unscheduled.secondaryText)

        let low = MedicationStockCard(
            status: MedicationStockStatus(
                level: .low,
                title: "Refill soon",
                message: "Only 3 days left — order a refill now.",
                remainingCount: 3,
                remainingDoses: 3,
                daysRemaining: 3
            ),
            tint: .blue,
            isHighlighted: false,
            refillAction: {}
        )
        XCTAssertEqual(low.secondaryText, "Only 3 days left — order a refill now.")
    }

    func testBottleMotionPolicyDisablesAutomaticMotionForReducedMotion() {
        XCTAssertFalse(BottleSceneMotionPolicy.shouldAutoPlay(reduceMotion: true))
        XCTAssertFalse(BottleSceneMotionPolicy.shouldAnimateInventoryChange(reduceMotion: true))
        XCTAssertEqual(BottleSceneMotionPolicy.preferredFramesPerSecond(reduceMotion: true), 30)
    }

    func testBottleMotionPolicyUsesSmoothInteractiveFrameRate() {
        XCTAssertTrue(BottleSceneMotionPolicy.shouldAutoPlay(reduceMotion: false))
        XCTAssertTrue(BottleSceneMotionPolicy.shouldAnimateInventoryChange(reduceMotion: false))
        XCTAssertEqual(BottleSceneMotionPolicy.preferredFramesPerSecond(reduceMotion: false), 60)
    }

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

    func testViewModelManualDoseUsesSelectedPastDateAndRefreshesSnapshot() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let takenAt = Date(timeIntervalSince1970: 400)
        let medication = makeMedication(tabletsRemaining: 10, tabletsPerDose: 2)
        let repository = MockMedicationDetailRepository(medication: medication)
        let viewModel = MedicationDetailViewModel(
            medicationID: medication.id,
            repository: repository,
            snapshotBuilder: MedicationDetailSnapshotBuilder(
                calendar: Calendar(identifier: .gregorian),
                now: { now }
            ),
            now: { now }
        )

        await viewModel.logManualDose(takenAt: takenAt)

        XCTAssertEqual(repository.loggedDoseAmounts, [2])
        XCTAssertEqual(repository.loggedDoseDates, [takenAt])
        XCTAssertEqual(viewModel.snapshot?.stockStatus.remainingCount, 8)
        XCTAssertEqual(viewModel.snapshot?.recentDoseRecords.first?.takenAt, takenAt)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testViewModelManualDoseRejectsFutureDateWithoutCallingRepository() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let medication = makeMedication(tabletsRemaining: 10, tabletsPerDose: 2)
        let repository = MockMedicationDetailRepository(medication: medication)
        let viewModel = MedicationDetailViewModel(
            medicationID: medication.id,
            repository: repository,
            now: { now }
        )

        await viewModel.logManualDose(takenAt: Date(timeIntervalSince1970: 1_001))

        XCTAssertTrue(repository.loggedDoseAmounts.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, MedicationDetailError.futureDoseDate.localizedDescription)
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

    func testQuantityInputViewModelAcceptsTypedQuantityAndStepsWithinBounds() {
        let viewModel = MedicationQuantityInputViewModel(initialValue: 30)

        viewModel.setText("42")
        XCTAssertEqual(viewModel.text, "42")
        XCTAssertEqual(viewModel.value, 42)
        XCTAssertNil(viewModel.errorMessage)

        viewModel.increment()
        XCTAssertEqual(viewModel.value, 43)
        XCTAssertEqual(viewModel.text, "43")

        viewModel.decrement()
        XCTAssertEqual(viewModel.value, 42)

        viewModel.setText("501")
        XCTAssertNil(viewModel.value)
        XCTAssertEqual(viewModel.state.validationError, .aboveMaximum(500))

        viewModel.increment()
        XCTAssertEqual(viewModel.value, 500)
        XCTAssertEqual(viewModel.text, "500")
    }

    func testQuantityInputViewModelKeepsInvalidTypedTextOutOfCommittedValue() {
        let viewModel = MedicationQuantityInputViewModel(
            configuration: .doseCount,
            initialValue: 1
        )

        viewModel.setText("")
        XCTAssertNil(viewModel.value)
        XCTAssertEqual(viewModel.validatedValue(), .failure(.empty))

        viewModel.setText("-1")
        XCTAssertNil(viewModel.value)
        XCTAssertEqual(viewModel.validatedValue(), .failure(.invalidNumber))

        viewModel.setText("0")
        XCTAssertNil(viewModel.value)
        XCTAssertEqual(viewModel.validatedValue(), .failure(.belowMinimum(1)))

        viewModel.setText("13")
        XCTAssertNil(viewModel.value)
        XCTAssertEqual(viewModel.validatedValue(), .failure(.aboveMaximum(12)))
    }

    func testViewModelRefillUsingTypedQuantityRefreshesSnapshotAndResetsInput() async {
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

        await viewModel.refresh()
        XCTAssertEqual(viewModel.refillQuantity.value, 10)

        viewModel.setRefillQuantityText("75")
        await viewModel.refillUsingQuantityInput()

        XCTAssertEqual(repository.refillCounts, [75])
        XCTAssertEqual(viewModel.snapshot?.stockStatus.remainingCount, 75)
        XCTAssertEqual(viewModel.refillQuantity.value, 75)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testViewModelRefillUsingInvalidTypedQuantitySurfacesValidationError() async {
        let medication = makeMedication(tabletsRemaining: 10)
        let repository = MockMedicationDetailRepository(medication: medication)
        let viewModel = MedicationDetailViewModel(
            medicationID: medication.id,
            repository: repository
        )

        viewModel.setRefillQuantityText("")
        await viewModel.refillUsingQuantityInput()

        XCTAssertTrue(repository.refillCounts.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, MedicationQuantityInputError.empty.localizedDescription)
    }

    func testMedicationStoreClampsTabletAndDoseQuantitiesToSupportedRanges() throws {
        try withMedicationStoreStorage(medications: [], doseRecords: []) {
            let store = MedicationStore()

            store.addMedication(
                name: "Amlodipine",
                tablets: 700,
                dose: 99,
                colorHex: "3A8E84",
                classification: .prescription
            )

            XCTAssertEqual(store.medications.first?.tabletsRemaining, 500)
            XCTAssertEqual(store.medications.first?.tabletsPerDose, 12)

            let medication = try XCTUnwrap(store.medications.first)
            store.refill(medication, to: -50)
            XCTAssertEqual(store.medications.first?.tabletsRemaining, 0)
        }
    }

    func testMedicationStoreManualPastDoseDoesNotRegressLastTakenAt() throws {
        let medicationID = UUID()
        let newerDoseDate = Date(timeIntervalSince1970: 300)
        let olderDoseDate = Date(timeIntervalSince1970: 100)
        let medication = makeMedication(
            id: medicationID,
            tabletsRemaining: 10,
            tabletsPerDose: 1,
            lastTakenAt: newerDoseDate
        )
        let newerDose = DoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: medication.name,
            takenAt: newerDoseDate,
            tabletCount: 1
        )

        try withMedicationStoreStorage(medications: [medication], doseRecords: [newerDose]) {
            let store = MedicationStore()

            store.logDose(forMedicationID: medicationID, dosageAmount: 1, takenAt: olderDoseDate)

            XCTAssertEqual(store.medications.first?.tabletsRemaining, 9)
            XCTAssertEqual(store.medications.first?.lastTakenAt, newerDoseDate)
            XCTAssertEqual(store.doseRecords.map(\.takenAt), [newerDoseDate, olderDoseDate])
        }
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

    func testSwiftDataLogDoseAddsPastRecordWithoutRegressingLastTakenAt() throws {
        let schema = Schema([
            PersistentMedication.self,
            PersistentMedicationReminder.self,
            PersistentDoseRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let medicationID = UUID()
        let newerDoseDate = Date(timeIntervalSince1970: 300)
        let olderDoseDate = Date(timeIntervalSince1970: 100)
        let medication = PersistentMedication(
            id: medicationID,
            name: "Amlodipine",
            tabletsRemaining: 10,
            tabletsPerDose: 1,
            bottleColorHex: "3A8E84",
            classification: .prescription,
            lastTakenAt: newerDoseDate
        )
        let newerDose = PersistentDoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: "Amlodipine",
            takenAt: newerDoseDate,
            tabletCount: 1
        )
        context.insert(medication)
        context.insert(newerDose)
        try context.save()

        let persistence = SwiftDataActiveMedicationStore(modelContext: context)
        let updatedMedication = try persistence.logDose(
            medicationID: medicationID,
            dosageAmount: 1,
            takenAt: olderDoseDate
        )

        XCTAssertEqual(updatedMedication.tabletsRemaining, 9)
        XCTAssertEqual(updatedMedication.lastTakenAt, newerDoseDate)
        XCTAssertEqual(
            try persistence.doseRecords(forMedicationID: medicationID).map(\.takenAt),
            [newerDoseDate, olderDoseDate]
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

    // MARK: - Phase 1: days of supply

    func testDosesPerDayAcrossDailySpecificDaysAsNeededAndMixedReminders() {
        let builder = makeBuilder()

        XCTAssertEqual(builder.dosesPerDay(for: makeMedication(reminders: [])), 0, accuracy: 0.0001)

        XCTAssertEqual(
            builder.dosesPerDay(for: makeMedication(reminders: [makeReminder(hour: 8), makeReminder(hour: 20)])),
            2,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            builder.dosesPerDay(
                for: makeMedication(
                    reminders: [makeReminder(hour: 8, frequency: .specificDays, weekdays: [.monday, .wednesday, .friday])]
                )
            ),
            3.0 / 7.0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            builder.dosesPerDay(for: makeMedication(reminders: [makeReminder(hour: 8, frequency: .asNeeded)])),
            0,
            accuracy: 0.0001
        )

        // Inactive reminders contribute nothing.
        XCTAssertEqual(
            builder.dosesPerDay(for: makeMedication(reminders: [makeReminder(hour: 8, isActive: false)])),
            0,
            accuracy: 0.0001
        )

        // Mixed: one daily + Mon/Wed/Fri + as-needed + paused.
        XCTAssertEqual(
            builder.dosesPerDay(
                for: makeMedication(
                    reminders: [
                        makeReminder(hour: 8),
                        makeReminder(hour: 13, frequency: .specificDays, weekdays: [.monday, .wednesday, .friday]),
                        makeReminder(hour: 18, frequency: .asNeeded),
                        makeReminder(hour: 22, isActive: false)
                    ]
                )
            ),
            1 + 3.0 / 7.0,
            accuracy: 0.0001
        )
    }

    func testDaysRemainingAndRunsOutDateUseTabletsConsumedPerDay() {
        let builder = makeBuilder()
        // 30 tablets, 1 per dose, one daily reminder, 12 doses already logged -> 18 days.
        let medication = makeMedication(
            tabletsRemaining: 18,
            tabletsPerDose: 1,
            reminders: [makeReminder(hour: 8)]
        )

        let status = builder.makeStockStatus(for: medication)

        XCTAssertEqual(status.daysRemaining, 18)
        XCTAssertEqual(status.supplyHeadline, "18 days left")
        XCTAssertEqual(status.level, .ready)
        XCTAssertEqual(
            status.runsOutDate,
            testCalendar.date(byAdding: .day, value: 18, to: testCalendar.startOfDay(for: referenceNow))
        )
        XCTAssertTrue(status.supplyDetail.hasPrefix("Runs out "))
    }

    func testDaysRemainingIsNilAndNoDateIsClaimedWithoutASchedule() {
        let builder = makeBuilder()
        let status = builder.makeStockStatus(for: makeMedication(tabletsRemaining: 30, tabletsPerDose: 1))

        XCTAssertNil(status.daysRemaining)
        XCTAssertNil(status.runsOutDate)
        XCTAssertEqual(status.supplyHeadline, "30 tablets left")
        XCTAssertEqual(status.supplyDetail, "No schedule set")
        XCTAssertEqual(status.level, .ready)
    }

    func testStockLevelThresholdsAtSevenDayBoundaryAndEmptyBottle() {
        let builder = makeBuilder()
        let twiceDaily = [makeReminder(hour: 8), makeReminder(hour: 20)]

        // 16 tablets, 1 per dose, 2 doses/day -> 8 days: still ready.
        let ready = builder.makeStockStatus(
            for: makeMedication(tabletsRemaining: 16, tabletsPerDose: 1, reminders: twiceDaily)
        )
        XCTAssertEqual(ready.daysRemaining, 8)
        XCTAssertEqual(ready.level, .ready)
        XCTAssertEqual(ready.title, "On hand")

        // 14 tablets -> exactly 7 days: low.
        let atBoundary = builder.makeStockStatus(
            for: makeMedication(tabletsRemaining: 14, tabletsPerDose: 1, reminders: twiceDaily)
        )
        XCTAssertEqual(atBoundary.daysRemaining, 7)
        XCTAssertEqual(atBoundary.level, .low)
        XCTAssertEqual(atBoundary.title, "Refill soon")
        XCTAssertEqual(atBoundary.message, "Only 7 days left — order a refill now.")

        // 6 tablets, 2 per dose, twice daily -> 1 day: low, singular copy.
        let oneDay = builder.makeStockStatus(
            for: makeMedication(tabletsRemaining: 6, tabletsPerDose: 2, reminders: twiceDaily)
        )
        XCTAssertEqual(oneDay.daysRemaining, 1)
        XCTAssertEqual(oneDay.level, .low)
        XCTAssertEqual(oneDay.supplyHeadline, "1 day left")

        let empty = builder.makeStockStatus(
            for: makeMedication(tabletsRemaining: 0, tabletsPerDose: 1, reminders: twiceDaily)
        )
        XCTAssertEqual(empty.level, .empty)
        XCTAssertEqual(empty.title, "Empty")
        XCTAssertEqual(empty.message, "Refill this bottle before the next dose.")
    }

    func testUnscheduledMedicationStillFlagsLowStockOnRemainingDoses() {
        let builder = makeBuilder()
        let status = builder.makeStockStatus(for: makeMedication(tabletsRemaining: 3, tabletsPerDose: 1))

        XCTAssertNil(status.daysRemaining)
        XCTAssertEqual(status.level, .low)
        XCTAssertEqual(status.title, "Refill soon")
    }

    // MARK: - Phase 1: today verdict

    func testVerdictIsDueNowWhenScheduledTimeHasPassedWithNothingLogged() {
        let builder = makeBuilder()
        let medication = makeMedication(reminders: [makeReminder(hour: 8, minute: 30)])

        let snapshot = builder.makeSnapshot(medication: medication, doseRecords: [])

        XCTAssertEqual(snapshot.todayStatus.verdict, .dueNow)
        XCTAssertEqual(snapshot.todayStatus.title, "Due now")
        XCTAssertEqual(snapshot.todayStatus.systemImage, "exclamationmark.circle.fill")
        XCTAssertTrue(snapshot.todayStatus.detail.hasSuffix("dose not logged"))
        XCTAssertFalse(snapshot.actions.isDoseLoggedToday)
        XCTAssertEqual(snapshot.actions.primaryTitle, "Log dose")
    }

    func testVerdictIsUpcomingWhenTodaysDoseIsStillAhead() {
        let builder = makeBuilder()
        let medication = makeMedication(reminders: [makeReminder(hour: 21)])

        let snapshot = builder.makeSnapshot(medication: medication, doseRecords: [])

        XCTAssertEqual(snapshot.todayStatus.verdict, .upcoming)
        XCTAssertTrue(snapshot.todayStatus.title.hasPrefix("Due at "))
        XCTAssertEqual(snapshot.todayStatus.detail, "Nothing logged yet today")
        XCTAssertEqual(snapshot.todayStatus.systemImage, "clock")
    }

    func testVerdictIsTakenTodayForOneAndForMultipleLoggedDoses() {
        let builder = makeBuilder()
        let medication = makeMedication(reminders: [makeReminder(hour: 8, minute: 30)])
        let morning = makeDoseRecord(medicationID: medication.id, hour: 8, minute: 30)

        let single = builder.makeSnapshot(medication: medication, doseRecords: [morning])
        XCTAssertEqual(single.todayStatus.verdict, .takenToday)
        XCTAssertEqual(single.todayStatus.title, "Taken today")
        XCTAssertEqual(single.todayStatus.systemImage, "checkmark.circle.fill")
        // The detail is only what happened; what is coming lives on the schedule line.
        XCTAssertEqual(
            single.todayStatus.detail,
            morning.takenAt.formatted(date: .omitted, time: .shortened)
        )
        XCTAssertFalse(single.todayStatus.detail.contains("· next "))
        XCTAssertTrue(single.actions.isDoseLoggedToday)
        XCTAssertEqual(single.actions.primaryTitle, "Log another dose")
        XCTAssertEqual(single.actions.primarySystemImage, "plus")

        let evening = makeDoseRecord(medicationID: medication.id, hour: 12, minute: 15)
        let double = builder.makeSnapshot(medication: medication, doseRecords: [morning, evening])
        XCTAssertEqual(double.todayStatus.verdict, .takenToday)
        XCTAssertTrue(double.todayStatus.detail.hasPrefix("2 doses · "))
    }

    /// The today card absorbed the schedule when the separate Next Dose card was removed,
    /// so it has to answer "what is coming" for every verdict, not just the tidy ones.
    func testScheduleDetailCarriesTheNextDoseTheReminderCardUsedToShow() {
        let builder = makeBuilder()
        let medication = makeMedication(reminders: [makeReminder(hour: 8, minute: 30)])

        // Logged many times today: the detail is a tally, so the next dose must survive here.
        let many = (1...14).map { makeDoseRecord(medicationID: medication.id, hour: 8, minute: $0) }
        let logged = builder.makeSnapshot(medication: medication, doseRecords: many)
        XCTAssertEqual(logged.todayStatus.verdict, .takenToday)
        XCTAssertTrue(
            logged.todayStatus.scheduleDetail.hasPrefix("Next "),
            "Expected a next-dose line, got: \(logged.todayStatus.scheduleDetail)"
        )
        XCTAssertTrue(logged.todayStatus.scheduleDetail.hasSuffix("· 1 tablet"))

        // Still ahead of the dose: the title already names the time, so the line adds cadence.
        let upcoming = builder.makeSnapshot(
            medication: makeMedication(reminders: [makeReminder(hour: 21)]),
            doseRecords: []
        )
        XCTAssertEqual(upcoming.todayStatus.verdict, .upcoming)
        XCTAssertEqual(upcoming.todayStatus.scheduleDetail, "Everyday · 1 tablet")

        // Nothing scheduled: say so rather than leaving the card silent about the schedule.
        let asNeeded = builder.makeSnapshot(
            medication: makeMedication(reminders: [makeReminder(hour: 8, frequency: .asNeeded)]),
            doseRecords: []
        )
        XCTAssertEqual(asNeeded.todayStatus.scheduleDetail, "As needed")
    }

    /// Spelling out every timestamp made the card grow without bound — fourteen doses
    /// pushed the bottle and the supply readout off the first screen.
    func testTakenTodayDetailStopsListingEveryTimeOnceThereAreManyDoses() {
        let builder = makeBuilder()
        let medication = makeMedication(reminders: [makeReminder(hour: 8, minute: 30)])

        let three = (1...3).map { makeDoseRecord(medicationID: medication.id, hour: 8, minute: $0) }
        let listed = builder.makeSnapshot(medication: medication, doseRecords: three)
        let listedTimes = three.map { $0.takenAt.formatted(date: .omitted, time: .shortened) }
        XCTAssertEqual(
            listed.todayStatus.detail,
            "3 doses · \(listedTimes.joined(separator: ", "))",
            "A short day still spells out its times"
        )

        let many = (1...14).map { makeDoseRecord(medicationID: medication.id, hour: 8, minute: $0) }
        let collapsed = builder.makeSnapshot(medication: medication, doseRecords: many)
        let latest = many[13].takenAt.formatted(date: .omitted, time: .shortened)

        XCTAssertEqual(collapsed.todayStatus.detail, "14 doses · latest \(latest)")
        XCTAssertFalse(
            collapsed.todayStatus.detail.contains(", "),
            "The detail must not enumerate times once it collapses"
        )
    }

    func testVerdictIsNoScheduleForAsNeededMedications() {
        let builder = makeBuilder()
        let asNeeded = makeMedication(reminders: [makeReminder(hour: 8, frequency: .asNeeded)])

        let withoutDoses = builder.makeSnapshot(medication: asNeeded, doseRecords: [])
        XCTAssertEqual(withoutDoses.todayStatus.verdict, .noSchedule)
        XCTAssertEqual(withoutDoses.todayStatus.title, "As needed")
        XCTAssertEqual(withoutDoses.todayStatus.detail, "No doses logged yet")
        XCTAssertEqual(withoutDoses.todayStatus.systemImage, "pills")

        let yesterday = testCalendar.date(byAdding: .day, value: -1, to: referenceNow)!
        let withHistory = builder.makeSnapshot(
            medication: makeMedication(
                reminders: [makeReminder(hour: 8, frequency: .asNeeded)],
                lastTakenAt: yesterday
            ),
            doseRecords: []
        )
        XCTAssertEqual(withHistory.todayStatus.verdict, .noSchedule)
        XCTAssertTrue(withHistory.todayStatus.detail.hasPrefix("Last taken yesterday, "))
    }

    func testEmptyBottleKeepsRefillAsThePrimaryActionEvenAfterADoseToday() {
        let builder = makeBuilder()
        let medication = makeMedication(tabletsRemaining: 0, reminders: [makeReminder(hour: 8, minute: 30)])
        let record = makeDoseRecord(medicationID: medication.id, hour: 8, minute: 30)

        let snapshot = builder.makeSnapshot(medication: medication, doseRecords: [record])

        XCTAssertTrue(snapshot.actions.isDoseLoggedToday)
        XCTAssertFalse(snapshot.actions.canLogDose)
        XCTAssertEqual(snapshot.actions.primaryTitle, "Refill bottle")
    }

    // MARK: - Phase 1: reminder card copy

    func testReminderSubtitleFollowsCopyPriority() {
        let builder = makeBuilder()

        XCTAssertEqual(
            builder.makeSnapshot(medication: makeMedication(), doseRecords: []).reminderOverview.subtitle,
            "No schedule set"
        )
        XCTAssertEqual(
            builder.makeSnapshot(
                medication: makeMedication(reminders: [makeReminder(hour: 8, isActive: false)]),
                doseRecords: []
            ).reminderOverview.subtitle,
            "All reminders paused"
        )
        XCTAssertEqual(
            builder.makeSnapshot(
                medication: makeMedication(reminders: [makeReminder(hour: 8, frequency: .asNeeded)]),
                doseRecords: []
            ).reminderOverview.subtitle,
            "As needed"
        )
        XCTAssertEqual(
            builder.makeSnapshot(
                medication: makeMedication(reminders: [makeReminder(hour: 21, dosageAmount: 1)]),
                doseRecords: []
            ).reminderOverview.subtitle,
            "Everyday · 1 tablet"
        )
        XCTAssertEqual(
            builder.makeSnapshot(
                medication: makeMedication(
                    reminders: [
                        makeReminder(
                            hour: 21,
                            frequency: .specificDays,
                            weekdays: [.monday, .wednesday, .friday],
                            dosageAmount: 2
                        )
                    ]
                ),
                doseRecords: []
            ).reminderOverview.subtitle,
            "Mon, Wed, Fri · 2 tablets"
        )
    }

    func testReminderOverviewPublishesNextReminderDateForTheView() {
        let builder = makeBuilder()
        let snapshot = builder.makeSnapshot(
            medication: makeMedication(reminders: [makeReminder(hour: 21)]),
            doseRecords: []
        )

        XCTAssertEqual(
            snapshot.reminderOverview.nextReminderDate,
            testCalendar.date(bySettingHour: 21, minute: 0, second: 0, of: referenceNow)
        )
    }

    // MARK: - Phase 1: undo

    func testUndoRestoresTabletsRemovesExactlyOneRecordAndRecomputesLastTaken() async {
        let earlierDose = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 10_000)
        let medication = makeMedication(tabletsRemaining: 10, tabletsPerDose: 3)
        let repository = MockMedicationDetailRepository(medication: medication)
        let viewModel = MedicationDetailViewModel(
            medicationID: medication.id,
            repository: repository,
            snapshotBuilder: makeBuilder(),
            now: { now }
        )

        await viewModel.logManualDose(takenAt: earlierDose)
        await viewModel.logDose()

        let undoTarget = viewModel.undoableDose
        XCTAssertNotNil(undoTarget)
        XCTAssertEqual(viewModel.snapshot?.stockStatus.remainingCount, 4)
        XCTAssertEqual(viewModel.snapshot?.recentDoseRecords.count, 2)

        await viewModel.undoLastDose()

        XCTAssertEqual(repository.undoneRecordIDs.count, 1)
        XCTAssertEqual(repository.undoneRecordIDs.first, undoTarget?.id)
        XCTAssertEqual(viewModel.snapshot?.stockStatus.remainingCount, 7)
        XCTAssertEqual(viewModel.snapshot?.recentDoseRecords.count, 1)
        XCTAssertEqual(viewModel.snapshot?.medication.lastTakenAt, earlierDose)
        XCTAssertNil(viewModel.undoableDose)
    }

    func testUndoIsUnavailableAfterCancellationAndDoesNotTouchTheRepository() async {
        let medication = makeMedication(tabletsRemaining: 10, tabletsPerDose: 2)
        let repository = MockMedicationDetailRepository(medication: medication)
        let viewModel = MedicationDetailViewModel(
            medicationID: medication.id,
            repository: repository,
            snapshotBuilder: makeBuilder()
        )

        await viewModel.logDose()
        XCTAssertNotNil(viewModel.undoableDose)

        viewModel.cancelUndo()
        await viewModel.undoLastDose()

        XCTAssertTrue(repository.undoneRecordIDs.isEmpty)
        XCTAssertEqual(viewModel.snapshot?.stockStatus.remainingCount, 8)
    }

    func testMedicationStoreUndoDoseRestoresExactCountAndRecomputesLastTaken() throws {
        try withMedicationStoreStorage(medications: [], doseRecords: []) {
            let store = MedicationStore()
            store.medications = [makeMedication(tabletsRemaining: 1, tabletsPerDose: 2)]
            let medicationID = store.medications[0].id
            let earlier = Date(timeIntervalSince1970: 500)

            store.logDose(forMedicationID: medicationID, dosageAmount: 2, takenAt: earlier)
            let previousCount = store.medications[0].tabletsRemaining
            let record = try XCTUnwrap(
                store.logDose(forMedicationID: medicationID, dosageAmount: 2, takenAt: Date(timeIntervalSince1970: 900))
            )
            XCTAssertEqual(store.doseRecords.count, 2)

            store.undoDose(
                medicationID: medicationID,
                recordID: record.id,
                restoringTabletsTo: previousCount
            )

            // The first dose clamped the bottle to 0; undo must not invent tablets.
            XCTAssertEqual(store.medications[0].tabletsRemaining, previousCount)
            XCTAssertEqual(store.doseRecords.count, 1)
            XCTAssertEqual(store.medications[0].lastTakenAt, earlier)
        }
    }

    // MARK: - Phase 2: bottle as supply gauge

    func testVisiblePillCountTracksFillRatioRatherThanRawCount() {
        // Full bottles saturate, regardless of how large the bottle is.
        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 30, bottleCapacity: 30), 18)
        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 90, bottleCapacity: 90), 18)

        // The same 30 tablets read very differently against different capacities.
        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 30, bottleCapacity: 90), 6)
        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 45, bottleCapacity: 90), 9)

        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 0, bottleCapacity: 30), 0)
        // A nearly-empty bottle still shows something rather than reading as empty.
        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 1, bottleCapacity: 500), 1)
        // Over-full and degenerate capacities stay in range.
        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 40, bottleCapacity: 30), 18)
        XCTAssertEqual(BottleFillPolicy.visiblePillCount(tabletsRemaining: 5, bottleCapacity: 0), 18)
    }

    func testBottleCapacityIsSetOnAddAndRaisedOnlyByLargerRefills() throws {
        try withMedicationStoreStorage(medications: [], doseRecords: []) {
            let store = MedicationStore()
            store.medications = []

            let added = store.addMedication(
                name: "Finasteride",
                tablets: 30,
                dose: 1,
                colorHex: "D99A00",
                classification: .prescription
            )
            let medication = try XCTUnwrap(added)
            XCTAssertEqual(store.medications[0].bottleCapacity, 30)

            // Logging doses lowers the count but not the bottle's size.
            store.logDose(forMedicationID: medication.id, dosageAmount: 10)
            XCTAssertEqual(store.medications[0].tabletsRemaining, 20)
            XCTAssertEqual(store.medications[0].bottleCapacity, 30)
            XCTAssertEqual(store.medications[0].fillRatio, 20.0 / 30.0, accuracy: 0.0001)

            // A smaller refill does not shrink capacity.
            store.refill(store.medications[0], to: 12)
            XCTAssertEqual(store.medications[0].bottleCapacity, 30)

            // A larger one becomes the new full mark.
            store.refill(store.medications[0], to: 90)
            XCTAssertEqual(store.medications[0].bottleCapacity, 90)
            XCTAssertEqual(store.medications[0].fillRatio, 1, accuracy: 0.0001)
        }
    }

    func testMedicationDecodedBeforeCapacityExistedAdoptsItsCurrentCount() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Atorvastatin","tabletsRemaining":24,
         "tabletsPerDose":1,"bottleColorHex":"D99A00"}
        """.data(using: .utf8)!

        let medication = try JSONDecoder().decode(Medication.self, from: legacy)

        XCTAssertEqual(medication.bottleCapacity, 24)
        XCTAssertEqual(medication.fillRatio, 1, accuracy: 0.0001)
        XCTAssertNil(medication.rxcui)
    }

    func testRxcuiSurvivesAnAddAndEditRoundTrip() throws {
        try withMedicationStoreStorage(medications: [], doseRecords: []) {
            let store = MedicationStore()
            store.medications = []

            store.addMedication(
                name: "Finasteride",
                tablets: 30,
                dose: 1,
                colorHex: "D99A00",
                classification: .prescription,
                rxcui: "310429"
            )
            XCTAssertEqual(store.medications[0].rxcui, "310429")

            var edited = store.medications[0]
            edited.name = "Finasteride 1mg"
            store.updateMedication(edited)

            XCTAssertEqual(store.medications[0].rxcui, "310429")
            XCTAssertEqual(store.medications[0].bottleCapacity, 30)
        }
    }

    // MARK: - Phase 2: calendar adherence

    func testDayStatesCoverCompletePartialMissedAndNone() {
        let calculator = makeAdherenceCalculator()
        let yesterday = testCalendar.date(byAdding: .day, value: -1, to: referenceNow)!

        XCTAssertEqual(
            calculator.dayStatus(expectedDoses: 2, loggedDoses: 2, on: yesterday).adherence,
            .complete
        )
        XCTAssertEqual(
            calculator.dayStatus(expectedDoses: 2, loggedDoses: 3, on: yesterday).adherence,
            .complete
        )
        XCTAssertEqual(
            calculator.dayStatus(expectedDoses: 2, loggedDoses: 1, on: yesterday).adherence,
            .partial
        )
        XCTAssertEqual(
            calculator.dayStatus(expectedDoses: 2, loggedDoses: 0, on: yesterday).adherence,
            .missed
        )
        XCTAssertEqual(
            calculator.dayStatus(expectedDoses: 0, loggedDoses: 0, on: yesterday).adherence,
            .none
        )
        // Today is still in progress, so nothing logged yet is not a miss.
        XCTAssertEqual(
            calculator.dayStatus(expectedDoses: 2, loggedDoses: 0, on: referenceNow).adherence,
            .none
        )
        XCTAssertEqual(
            calculator.dayStatus(expectedDoses: 2, loggedDoses: 1, on: yesterday).accessibilitySuffix,
            ", 1 of 2 doses"
        )
    }

    func testExpectedDoseCountRespectsWeekdaysAndPausedReminders() {
        let calculator = makeAdherenceCalculator()
        // referenceNow is a Wednesday.
        let wednesday = referenceNow
        let thursday = testCalendar.date(byAdding: .day, value: 1, to: referenceNow)!

        let medication = makeMedication(
            reminders: [
                makeReminder(hour: 8),
                makeReminder(hour: 13, frequency: .specificDays, weekdays: [.wednesday]),
                makeReminder(hour: 18, frequency: .asNeeded),
                makeReminder(hour: 22, isActive: false)
            ]
        )

        XCTAssertEqual(calculator.expectedDoseCount(for: [medication], on: wednesday), 2)
        XCTAssertEqual(calculator.expectedDoseCount(for: [medication], on: thursday), 1)
        XCTAssertEqual(calculator.expectedDoseCount(for: [], on: wednesday), 0)
    }

    func testStreakCountsConsecutiveCompleteDaysAndStopsAtAGap() {
        let calculator = makeAdherenceCalculator()
        let medications = [makeMedication(reminders: [makeReminder(hour: 8)])]

        func day(_ offset: Int) -> Date {
            testCalendar.startOfDay(for: testCalendar.date(byAdding: .day, value: offset, to: referenceNow)!)
        }

        // Today logged, then three complete days, then a gap, then more complete days.
        let logged: [Date: Int] = [
            day(0): 1,
            day(-1): 1,
            day(-2): 1,
            day(-3): 1,
            day(-4): 0,
            day(-5): 1,
            day(-6): 1
        ]

        XCTAssertEqual(
            calculator.currentStreak(medications: medications, loggedDosesByDay: logged),
            4
        )

        // Today not yet logged must not erase a streak earned through yesterday.
        var withoutToday = logged
        withoutToday[day(0)] = 0
        XCTAssertEqual(
            calculator.currentStreak(medications: medications, loggedDosesByDay: withoutToday),
            3
        )

        // A medication with no schedule has no streak to earn.
        XCTAssertEqual(
            calculator.currentStreak(medications: [makeMedication()], loggedDosesByDay: logged),
            0
        )
    }

    func testStreakSkipsDaysThatExpectedNothing() {
        let calculator = makeAdherenceCalculator()
        // Wednesday-only reminder: the six days between Wednesdays expect nothing and
        // must neither count toward nor break the streak.
        let medications = [
            makeMedication(reminders: [makeReminder(hour: 8, frequency: .specificDays, weekdays: [.wednesday])])
        ]

        func day(_ offset: Int) -> Date {
            testCalendar.startOfDay(for: testCalendar.date(byAdding: .day, value: offset, to: referenceNow)!)
        }

        let logged: [Date: Int] = [day(0): 1, day(-7): 1, day(-14): 1]

        XCTAssertEqual(
            calculator.currentStreak(medications: medications, loggedDosesByDay: logged),
            3
        )
    }

    // MARK: - Phase 2: dose record deletion

    func testDeletingADoseRecordReturnsTabletsOnlyWhenAsked() throws {
        try withMedicationStoreStorage(medications: [], doseRecords: []) {
            let store = MedicationStore()
            store.medications = [makeMedication(tabletsRemaining: 30, tabletsPerDose: 2)]
            let medicationID = store.medications[0].id

            let discarded = try XCTUnwrap(
                store.logDose(forMedicationID: medicationID, dosageAmount: 2, takenAt: Date(timeIntervalSince1970: 100))
            )
            XCTAssertEqual(store.medications[0].tabletsRemaining, 28)

            store.deleteDoseRecords(withIDs: [discarded.id], returningTablets: false)
            XCTAssertEqual(store.medications[0].tabletsRemaining, 28)
            XCTAssertTrue(store.doseRecords.isEmpty)

            let returned = try XCTUnwrap(
                store.logDose(forMedicationID: medicationID, dosageAmount: 2, takenAt: Date(timeIntervalSince1970: 200))
            )
            XCTAssertEqual(store.medications[0].tabletsRemaining, 26)

            store.deleteDoseRecords(withIDs: [returned.id], returningTablets: true)
            XCTAssertEqual(store.medications[0].tabletsRemaining, 28)
            XCTAssertTrue(store.doseRecords.isEmpty)
            XCTAssertNil(store.medications[0].lastTakenAt)
        }
    }

    // MARK: - Helpers

    private func makeAdherenceCalculator() -> MedicationAdherenceCalculator {
        let now = referenceNow
        return MedicationAdherenceCalculator(calendar: testCalendar, now: { now })
    }

    /// 12:00 on Wednesday 17 April 2024, so "morning" reminders are in the past
    /// and "evening" ones are still ahead.
    private var referenceNow: Date {
        testCalendar.date(from: DateComponents(year: 2024, month: 4, day: 17, hour: 12, minute: 0))!
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeBuilder() -> MedicationDetailSnapshotBuilder {
        let now = referenceNow
        return MedicationDetailSnapshotBuilder(calendar: testCalendar, now: { now })
    }

    private func makeReminder(
        hour: Int,
        minute: Int = 0,
        frequency: Medication.ReminderFrequency = .daily,
        weekdays: Set<Medication.Weekday> = Set(Medication.Weekday.allCases),
        isActive: Bool = true,
        dosageAmount: Int = 1
    ) -> Medication.Reminder {
        Medication.Reminder(
            time: testCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: referenceNow)!,
            frequency: frequency,
            weekdays: weekdays,
            isActive: isActive,
            dosageAmount: dosageAmount
        )
    }

    private func makeDoseRecord(
        medicationID: Medication.ID,
        hour: Int,
        minute: Int = 0,
        tabletCount: Int = 1
    ) -> DoseRecord {
        DoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: "Atorvastatin",
            takenAt: testCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: referenceNow)!,
            tabletCount: tabletCount
        )
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
    private(set) var loggedDoseDates: [Date] = []
    private(set) var refillCounts: [Int] = []
    private(set) var undoneRecordIDs: [DoseRecord.ID] = []

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

    func logDose(medicationID: Medication.ID, dosageAmount: Int, takenAt: Date) async throws -> MedicationDoseLogResult {
        guard medicationValue.id == medicationID else { throw MedicationDetailError.medicationNotFound }
        guard medicationValue.tabletsRemaining > 0 else { throw MedicationDetailError.outOfStock }

        let dose = max(1, dosageAmount)
        let previousTabletsRemaining = medicationValue.tabletsRemaining
        loggedDoseAmounts.append(dose)
        loggedDoseDates.append(takenAt)
        medicationValue.tabletsRemaining = max(0, medicationValue.tabletsRemaining - dose)
        medicationValue.lastTakenAt = ([medicationValue.lastTakenAt, takenAt].compactMap { $0 } + records.map(\.takenAt)).max()
        let record = DoseRecord(
            id: UUID(),
            medicationID: medicationID,
            medicationName: medicationValue.name,
            takenAt: takenAt,
            tabletCount: dose
        )
        records.insert(record, at: 0)

        return MedicationDoseLogResult(
            medication: medicationValue,
            record: record,
            previousTabletsRemaining: previousTabletsRemaining
        )
    }

    func undoDose(
        medicationID: Medication.ID,
        recordID: DoseRecord.ID,
        restoringTabletsTo count: Int
    ) async throws -> Medication {
        guard medicationValue.id == medicationID else { throw MedicationDetailError.medicationNotFound }
        guard records.contains(where: { $0.id == recordID }) else { return medicationValue }

        undoneRecordIDs.append(recordID)
        records.removeAll { $0.id == recordID }
        medicationValue.tabletsRemaining = count
        medicationValue.lastTakenAt = records
            .filter { $0.medicationID == medicationID }
            .map(\.takenAt)
            .max()
        return medicationValue
    }

    func refill(medicationID: Medication.ID, to count: Int) async throws -> Medication {
        guard medicationValue.id == medicationID else { throw MedicationDetailError.medicationNotFound }
        guard MedicationQuantityLimits.tabletCount.contains(count) else {
            throw MedicationDetailError.invalidRefillCount
        }

        refillCounts.append(count)
        medicationValue.tabletsRemaining = count
        return medicationValue
    }
}
