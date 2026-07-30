import SceneKit
import SwiftUI
import XCTest
@testable import MedBottle

@MainActor
final class BottleScenePhysicsTests: XCTestCase {
    private enum Contract {
        static let envelopeName = "collisionEnvelope"
        static let floorName = "collisionFloor"
        static let wallsName = "collisionWalls"
        static let lidName = "collisionLid"
        static let pillName = "pill"
        static let tabletGroupPrefix = "tablets|"

        static let envelopeY: Float = -0.08
        static let innerRadius: Float = 0.620
        static let floorTop: Float = -1.475
        static let floorCollisionDepth: Float = 0.20
        static let lidBottom: Float = 1.389
        static let tolerance: Float = 0.020
        static let ccdThreshold: CGFloat = 0.010
        static let maxPillSpeed: Float = 2.4
        static let roundProxyRadius: Float = 0.128
        static let capsuleProxyRadius: Float = 0.09
        static let capsuleProxyHalfSegment: Float = 0.09

        static let pillCategory = 1 << 0
        static let containerCategory = 1 << 1
    }

    func testBottleSceneCreatesClosedStationaryCollisionEnvelope() throws {
        let scene = makeScene(shape: .tablet, inventory: 1)
        let assembly = try XCTUnwrap(scene.rootNode.childNode(withName: "assembly", recursively: false))
        let bottle = try XCTUnwrap(assembly.childNode(withName: "bottle", recursively: false))
        let envelope = try XCTUnwrap(assembly.childNode(withName: Contract.envelopeName, recursively: false))

        XCTAssertTrue(envelope.parent === assembly)
        XCTAssertFalse(envelope.parent === bottle)
        XCTAssertEqual(envelope.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(envelope.position.y, Contract.envelopeY, accuracy: 0.0001)
        XCTAssertEqual(envelope.position.z, 0, accuracy: 0.0001)

        let floor = try XCTUnwrap(envelope.childNode(withName: Contract.floorName, recursively: false))
        let walls = try XCTUnwrap(envelope.childNode(withName: Contract.wallsName, recursively: false))
        let lid = try XCTUnwrap(envelope.childNode(withName: Contract.lidName, recursively: false))

        XCTAssertEqual(floor.position.y, Contract.floorTop - Contract.floorCollisionDepth / 2, accuracy: 0.0001)
        XCTAssertEqual(lid.position.y, Contract.lidBottom + 0.01, accuracy: 0.0001)
        XCTAssertEqual(walls.childNodes.count, 16)

        for boundary in [floor, lid] + walls.childNodes {
            let body = try XCTUnwrap(boundary.physicsBody)
            XCTAssertEqual(body.type, .kinematic)
            XCTAssertEqual(body.categoryBitMask, Contract.containerCategory)
            XCTAssertEqual(body.collisionBitMask, Contract.pillCategory)
        }
    }

    func testEveryPillUsesContinuousCollisionDetection() throws {
        for shape in MedicationShape.allCases {
            let scene = makeScene(shape: shape, inventory: 90)
            let pills = try activePills(in: scene)

            XCTAssertEqual(pills.count, 90, "Unexpected pill count for \(shape.rawValue)")
            for pill in pills {
                let body = try XCTUnwrap(pill.physicsBody)
                XCTAssertEqual(body.type, .dynamic)
                XCTAssertTrue(body.isAffectedByGravity)
                XCTAssertEqual(body.continuousCollisionDetectionThreshold, Contract.ccdThreshold, accuracy: 0.0001)
                XCTAssertEqual(body.categoryBitMask, Contract.pillCategory)
                XCTAssertEqual(body.collisionBitMask, Contract.pillCategory | Contract.containerCategory)
            }
        }
    }

    func testDisplayedPillCountClampsAtNinetyForEveryShape() throws {
        for shape in MedicationShape.allCases {
            for (inventory, expectedCount) in [(0, 0), (18, 18), (30, 30), (90, 90), (91, 90)] {
                let scene = makeScene(shape: shape, inventory: inventory)
                XCTAssertEqual(
                    try activePills(in: scene).count,
                    expectedCount,
                    "Unexpected displayed count for \(shape.rawValue), inventory=\(inventory)"
                )
            }
        }
    }

    func testNinetyPillsStartFullyInsideEnvelopeWithoutProxyOverlap() throws {
        for shape in MedicationShape.allCases {
            let scene = makeScene(shape: shape, inventory: 90)
            let assembly = try XCTUnwrap(scene.rootNode.childNode(withName: "assembly", recursively: false))
            let envelope = try XCTUnwrap(assembly.childNode(withName: Contract.envelopeName, recursively: false))
            let pills = try activePills(in: scene)

            for pill in pills {
                let bounds = pill.boundingBox
                for x in [bounds.min.x, bounds.max.x] {
                    for y in [bounds.min.y, bounds.max.y] {
                        for z in [bounds.min.z, bounds.max.z] {
                            let corner = envelope.convertPosition(SCNVector3(x, y, z), from: pill)
                            XCTAssertLessThanOrEqual(
                                hypot(corner.x, corner.z),
                                Contract.innerRadius - Contract.tolerance + 0.0001,
                                "Spawn corner exceeds radial inset for \(shape.rawValue)"
                            )
                            XCTAssertGreaterThanOrEqual(
                                corner.y,
                                Contract.floorTop + Contract.tolerance - 0.0001,
                                "Spawn corner exceeds floor inset for \(shape.rawValue)"
                            )
                            XCTAssertLessThanOrEqual(
                                corner.y,
                                Contract.lidBottom - Contract.tolerance + 0.0001,
                                "Spawn corner exceeds lid inset for \(shape.rawValue)"
                            )
                        }
                    }
                }
            }

            if shape == .capsule {
                assertCapsuleProxiesDoNotOverlap(pills, envelope: envelope)
            } else {
                assertRoundProxiesDoNotOverlap(pills, envelope: envelope, shape: shape)
            }
        }
    }

    func testInventoryReconciliationAddsAndRemovesExactActivePillCounts() throws {
        for shape in MedicationShape.allCases {
            let decrementScene = makeScene(shape: shape, inventory: 90)
            BottleSceneFactory.update(
                scene: decrementScene,
                medication: makeMedication(shape: shape, inventory: 89),
                colorScheme: .light,
                reduceMotion: true
            )
            XCTAssertEqual(try activePills(in: decrementScene).count, 89)
            XCTAssertTrue(decrementScene.rootNode.childNodes(passingTest: { node, _ in
                node.name == "pillRemoving"
            }).isEmpty)

            let refillScene = makeScene(shape: shape, inventory: 30)
            BottleSceneFactory.update(
                scene: refillScene,
                medication: makeMedication(shape: shape, inventory: 90),
                colorScheme: .light,
                reduceMotion: true
            )
            XCTAssertEqual(try activePills(in: refillScene).count, 90)

            BottleSceneFactory.update(
                scene: refillScene,
                medication: makeMedication(shape: shape, inventory: 0),
                colorScheme: .light,
                reduceMotion: true
            )
            XCTAssertTrue(try activePills(in: refillScene).isEmpty)
        }
    }

    func testFastAlternatingRotationKeepsEveryPillInsideEnvelope() throws {
        for shape in MedicationShape.allCases {
            for inventory in [90] {
                let scene = makeScene(shape: shape, inventory: inventory)
                let renderer = SCNRenderer(device: nil, options: nil)
                renderer.scene = scene
                scene.physicsWorld.timeStep = 1.0 / 60.0

                var time: TimeInterval = 0
                var rotation: Float = 0
                renderer.update(atTime: time)

                for frame in 0..<120 {
                    time += 1.0 / 60.0
                    renderer.update(atTime: time)

                    guard assertContainment(
                        in: scene,
                        inventory: inventory,
                        context: "shape=\(shape.rawValue), settleFrame=\(frame)"
                    ) else { return }
                }

                for sweepIndex in 0..<10 {
                    let sweepDelta: Float = sweepIndex.isMultiple(of: 2) ? 4.32 : -4.32
                    let frameDelta = sweepDelta / 15

                    for frame in 0..<15 {
                        rotation += frameDelta
                        BottleSceneFactory.applyInteractiveRotation(
                            scene: scene,
                            rotation: rotation,
                            rotationDelta: frameDelta
                        )
                        time += 1.0 / 60.0
                        renderer.update(atTime: time)

                        guard assertContainment(
                            in: scene,
                            inventory: inventory,
                            context: "shape=\(shape.rawValue), sweep=\(sweepIndex), frame=\(frame)"
                        ) else { return }
                    }
                }

            }
        }
    }

    func testEmptyInventoryCreatesNoPillNodes() throws {
        let scene = makeScene(shape: .tablet, inventory: 0)
        XCTAssertTrue(try activePills(in: scene).isEmpty)
    }

    func testRotationDeltaIsStatelessAndWrapsAcrossPi() {
        XCTAssertEqual(
            BottleSceneMotionPolicy.normalizedRotationDelta(from: 0.5, to: 0.8),
            0.3,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            BottleSceneMotionPolicy.normalizedRotationDelta(
                from: Float.pi - 0.1,
                to: -Float.pi + 0.1
            ),
            0.2,
            accuracy: 0.0001
        )
    }

    private func assertContainment(in scene: SCNScene, inventory: Int, context: String) -> Bool {
        guard
            let assembly = scene.rootNode.childNode(withName: "assembly", recursively: false),
            let envelope = assembly.childNode(withName: Contract.envelopeName, recursively: false),
            let tabletGroup = assembly.childNodes.first(where: { $0.name?.hasPrefix(Contract.tabletGroupPrefix) == true })
        else {
            XCTFail("Missing containment hierarchy: \(context)")
            return false
        }

        let pills = tabletGroup.childNodes.filter { $0.name == Contract.pillName }
        guard pills.count == min(max(inventory, 0), 90) else {
            XCTFail("Active pill count changed to \(pills.count): \(context)")
            return false
        }
        guard tabletGroup.parent === assembly else {
            XCTFail("Tablet group detached from assembly: \(context)")
            return false
        }

        for pill in pills {
            guard pill.parent === tabletGroup else {
                XCTFail("Pill detached from tablet group: \(context)")
                return false
            }
            guard let body = pill.physicsBody else {
                XCTFail("Pill lost its physics body: \(context)")
                return false
            }

            let worldPosition = pill.presentation.worldPosition
            let localPosition = envelope.presentation.convertPosition(worldPosition, from: nil)
            let radialDistance = hypot(localPosition.x, localPosition.z)
            let velocity = body.velocity
            let angularVelocity = body.angularVelocity
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)

            let finiteValues = [
                localPosition.x, localPosition.y, localPosition.z,
                velocity.x, velocity.y, velocity.z,
                angularVelocity.x, angularVelocity.y, angularVelocity.z, angularVelocity.w
            ]
            guard finiteValues.allSatisfy(\.isFinite) else {
                XCTFail("Pill contains a non-finite transform or velocity: \(context)")
                return false
            }
            guard speed <= Contract.maxPillSpeed + 0.001 else {
                XCTFail("Pill speed exceeded the bounded response at \(speed): \(context)")
                return false
            }
            guard radialDistance <= Contract.innerRadius + Contract.tolerance else {
                XCTFail("Pill radial center escaped at \(radialDistance): \(context)")
                return false
            }
            guard localPosition.y >= Contract.floorTop - Contract.tolerance,
                  localPosition.y <= Contract.lidBottom + Contract.tolerance else {
                XCTFail(
                    "Pill vertical center escaped at \(localPosition.y), radial=\(radialDistance), " +
                    "position=(\(localPosition.x), \(localPosition.y), \(localPosition.z)), " +
                    "velocity=(\(velocity.x), \(velocity.y), \(velocity.z)): \(context)"
                )
                return false
            }
        }

        return true
    }

    private func activePills(in scene: SCNScene) throws -> [SCNNode] {
        let assembly = try XCTUnwrap(scene.rootNode.childNode(withName: "assembly", recursively: false))
        let tabletGroup = try XCTUnwrap(
            assembly.childNodes.first(where: { $0.name?.hasPrefix(Contract.tabletGroupPrefix) == true })
        )
        return tabletGroup.childNodes.filter { $0.name == Contract.pillName }
    }

    private func assertRoundProxiesDoNotOverlap(
        _ pills: [SCNNode],
        envelope: SCNNode,
        shape: MedicationShape
    ) {
        let centers = pills.map { envelope.convertPosition(SCNVector3Zero, from: $0) }
        for first in centers.indices {
            for second in centers.indices where second > first {
                let deltaX = centers[first].x - centers[second].x
                let deltaY = centers[first].y - centers[second].y
                let deltaZ = centers[first].z - centers[second].z
                let distanceSquared = deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ
                let distance = sqrt(distanceSquared)
                XCTAssertGreaterThanOrEqual(
                    distance + 0.0001,
                    Contract.roundProxyRadius * 2,
                    "Initial \(shape.rawValue) proxies overlap at \(first), \(second)"
                )
            }
        }
    }

    private func assertCapsuleProxiesDoNotOverlap(_ pills: [SCNNode], envelope: SCNNode) {
        let segments = pills.map { pill -> (minX: Float, maxX: Float, y: Float, z: Float) in
            let first = envelope.convertPosition(
                SCNVector3(0, -Contract.capsuleProxyHalfSegment, 0),
                from: pill
            )
            let second = envelope.convertPosition(
                SCNVector3(0, Contract.capsuleProxyHalfSegment, 0),
                from: pill
            )
            XCTAssertEqual(first.y, second.y, accuracy: 0.0001)
            XCTAssertEqual(first.z, second.z, accuracy: 0.0001)
            return (min(first.x, second.x), max(first.x, second.x), (first.y + second.y) / 2, (first.z + second.z) / 2)
        }

        for first in segments.indices {
            for second in segments.indices where second > first {
                let xGap = max(0, max(segments[first].minX, segments[second].minX) - min(segments[first].maxX, segments[second].maxX))
                let yGap = segments[first].y - segments[second].y
                let zGap = segments[first].z - segments[second].z
                let distance = sqrt(xGap * xGap + yGap * yGap + zGap * zGap)
                XCTAssertGreaterThanOrEqual(
                    distance + 0.0001,
                    Contract.capsuleProxyRadius * 2,
                    "Initial capsule proxies overlap at \(first), \(second)"
                )
            }
        }
    }

    private func makeScene(shape: MedicationShape, inventory: Int) -> SCNScene {
        BottleSceneFactory.scene(
            for: makeMedication(shape: shape, inventory: inventory),
            colorScheme: .light,
            reduceMotion: false
        )
    }

    private func makeMedication(shape: MedicationShape, inventory: Int) -> Medication {
        Medication(
            id: UUID(),
            name: "Physics Test",
            tabletsRemaining: inventory,
            tabletsPerDose: 1,
            bottleColorHex: "D68A28",
            medicationShape: shape,
            lastTakenAt: nil
        )
    }
}
