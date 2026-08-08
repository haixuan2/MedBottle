import XCTest
@testable import MedBottle

@MainActor
final class MedicationBottleGaugeTests: XCTestCase {
    func testFillHeightClampsAtEmptyNearEmptyAndFull() {
        let bodyHeight: CGFloat = 120

        // Empty draws nothing at all.
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: bodyHeight, fillRatio: 0), 0)

        // A bottle holding tablets never renders as empty.
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: bodyHeight, fillRatio: 0.01), 6)
        XCTAssertGreaterThanOrEqual(
            MedicationBottleGauge.fillHeight(bodyHeight: bodyHeight, fillRatio: 0.001),
            6
        )

        // Full stops short of the shoulder so the meniscus stays visible.
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: bodyHeight, fillRatio: 1), bodyHeight - 4)
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: bodyHeight, fillRatio: 0.99), bodyHeight - 4)

        // Mid-range stays proportional, so 30/30 and 24/30 are distinguishable.
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: bodyHeight, fillRatio: 0.5), 60)
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: bodyHeight, fillRatio: 0.8), 96)
    }

    func testFillHeightSurvivesDegenerateBodyHeights() {
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: 0, fillRatio: 1), 0)
        // The 6pt floor must never exceed the 4pt-inset ceiling on a tiny thumbnail.
        XCTAssertEqual(MedicationBottleGauge.fillHeight(bodyHeight: 5, fillRatio: 0.01), 1)
        XCTAssertLessThanOrEqual(MedicationBottleGauge.fillHeight(bodyHeight: 5, fillRatio: 1), 1)
    }

    /// The bottle fills its stage. The hint that once justified 37% headroom is gone,
    /// and that slack read as a hole between the medication name and the bottle.
    func testBottleFillsItsStage() {
        let stage: CGFloat = 157
        let bottle = MedicationBottleGauge.bottleHeight(inStageOf: stage)

        XCTAssertEqual(bottle, stage * 0.951, accuracy: 0.001)
        XCTAssertLessThanOrEqual(bottle, stage, "The bottle must never overflow its stage")
        XCTAssertLessThan(stage - bottle, 10, "Slack is the ground shadow's room, not layout headroom")
    }

    func testFillRatioStaysWithinOneAfterARefillBeyondCapacity() throws {
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

            // Refilling past the known capacity must raise capacity, not overflow the gauge.
            store.refill(medication, to: 120)

            XCTAssertEqual(store.medications[0].bottleCapacity, 120)
            XCTAssertEqual(store.medications[0].fillRatio, 1, accuracy: 0.0001)
            XCTAssertEqual(
                MedicationBottleGauge.fillHeight(bodyHeight: 100, fillRatio: store.medications[0].fillRatio),
                96
            )
        }
    }

    // MARK: - Helpers

    private func withMedicationStoreStorage(
        medications: [Medication],
        doseRecords: [DoseRecord],
        perform operation: () throws -> Void
    ) throws {
        let defaults = UserDefaults.standard
        let previousMedications = defaults.data(forKey: MedicationStore.medicationsStorageKey)
        let previousDoseRecords = defaults.data(forKey: MedicationStore.doseRecordsStorageKey)

        defer {
            if let previousMedications {
                defaults.set(previousMedications, forKey: MedicationStore.medicationsStorageKey)
            } else {
                defaults.removeObject(forKey: MedicationStore.medicationsStorageKey)
            }

            if let previousDoseRecords {
                defaults.set(previousDoseRecords, forKey: MedicationStore.doseRecordsStorageKey)
            } else {
                defaults.removeObject(forKey: MedicationStore.doseRecordsStorageKey)
            }
        }

        defaults.set(try JSONEncoder().encode(medications), forKey: MedicationStore.medicationsStorageKey)
        defaults.set(try JSONEncoder().encode(doseRecords), forKey: MedicationStore.doseRecordsStorageKey)

        try operation()
    }
}
