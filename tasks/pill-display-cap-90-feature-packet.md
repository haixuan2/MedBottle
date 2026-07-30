# Feature Implementation Packet: Display Up to 90 Medications

## 1. Objective

Make bottle quantity visually meaningful by rendering up to 90 individual real SceneKit medication objects. A quantity of 90 must look substantially fuller than 30, while preserving the original tablet, pill, capsule, and softgel geometry and their gravity/collision behavior.

## 2. Scope and User Flow

- Entry remains the existing medication detail bottle.
- On load, refill, or dose consumption, the bottle renders `min(max(quantity, 0), 90)` individual medication nodes.
- Quantity changes use the existing add/remove animation and physics behavior.
- Empty (`0`) shows no medication objects. Quantities above 90 retain the exact label value but display 90 objects.
- There is no loading, networking, retry, cancellation, navigation, persistence, or offline behavior change.
- Out of scope: synthetic fill, level guides, static/kinematic medication beds, bottle resizing, persistence limits, and per-prescription volume calibration.

## 3. Acceptance Criteria

1. Active medication-node counts are exactly: `0 -> 0`, `18 -> 18`, `30 -> 30`, `90 -> 90`, and `91 -> 90` for every `MedicationShape`.
2. Every displayed object keeps the existing shape-specific geometry/material and an individual dynamic `SCNPhysicsBody` with gravity, pill-to-pill collision, container collision, and CCD enabled. No synthetic fill or aggregate substitute is introduced.
3. After settling, 90 contains visibly more individual medication objects than 30; 30 contains more than 18; and 0 is empty. This experiment does not pre-approve whether 90 looks sufficiently full—the user will judge the captured image.
4. Dose/refill reconciliation changes the active node count without rebuilding or changing medication persistence. A one-pill decrement removes exactly one active node.
5. All 90 initial medication geometries—not only their center points—start within the envelope-local floor (`-1.475`), lid (`1.389`), and inner radius (`0.620`) with a named `0.020` tolerance/inset.
6. Initial same-shape objects do not overlap according to transformed shape proxies, then all shapes remain contained with finite transforms/velocities after exactly 120 settle frames at `1/60` second and during the existing ten-sweep stress sequence at inventory 90.
7. The interaction remains responsive with 90 dynamic bodies: average measured FPS is at least 50 and no frame hitch exceeds 100 ms during a 10-second Release rotation run on the nominated simulator/device. No crash, hang, or runaway velocity occurs.
8. A simulator screenshot of the fixed 90-count fixture is captured after the 120-frame settle from the normal medication-detail UI on iPhone 17 Pro / iOS 26.5. It must show individual real medication objects with the default camera and lighting, not a debug scene or synthetic mockup. The image is evidence for user review, not an assertion that the physical fullness is accepted.

## 4. Architecture

- Keep SwiftUI + SceneKit and iOS 26.0 unchanged.
- Introduce one named visual-cap constant (`90`) used by both initial creation and reconciliation; clamp only rendered nodes, never the domain quantity.
- Replace the current six-column rising ring, which would place index 89 at y≈`2.32` above the lid, with deterministic per-shape envelope-local layouts:
  - Tablet, pill, and softgel: 3×3×10; x/z each use `[-0.28, 0, 0.28]`; layer y is `-1.327 + layer * 0.28` for layers `0...9`. The conservative `0.128` vertical/radial proxy leaves the lowest bound exactly `0.020` above the floor and the highest bound below the lid.
  - Capsule: horizontal long axis parallel to x, 2×4×12; x uses `[-0.21, 0.21]`, z uses `[-0.30, -0.10, 0.10, 0.30]`, and layer y is `-1.365 + layer * 0.24` for layers `0...11`; consume positions in stable index order and stop at 90. With half-length `0.18` and cap radius `0.09`, the transformed proxy remains inside the radial and vertical inset.
- Coordinates above are envelope-local. Because the tablet group is identity-transformed under the assembly while the envelope is at `(0, -0.08, 0)`, set the group-local spawn with `assembly.convertPosition(envelopeLocalPoint, from: envelope)` (equivalently x/z unchanged and assembly-local y = envelope-local y `- 0.08`). Tests must use the actual node conversions rather than duplicating only the arithmetic.
- Prove initial pairwise non-overlap before simulation: use a conservative sphere proxy of radius `0.128` for tablet/pill/softgel; use the transformed capsule center-line segment (half segment `0.09`) swept by radius `0.09`. Round-shape center spacing is at least `0.28`; parallel capsules have x center spacing `0.42`, z spacing `0.20`, and vertical spacing `0.24`.
- Keep state ownership, dependency injection, navigation, persistence, label quantity, and collision-envelope boundaries unchanged. Add no dependency.

## 5. File and Component Plan

- Modify `MedBottle/MedBottle/BottleSceneView.swift`: named cap, bounded spawn policy, and any capsule spawn-orientation adjustment required for stable packing.
- Modify `MedBottle/MedBottleTests/BottleScenePhysicsTests.swift`: cap mapping, spawn bounds, 90-body settling/rotation containment, and physics-body contract tests.
- No model, persistence, project, or dependency file changes are expected.

## 6. Test Plan

- Unit/SceneKit: assert counts `0/18/30/90/91` for all four shapes.
- Geometry: before simulation, transform every node bounding-box corner into collision-envelope space and assert it is inside floor/lid/radius with named tolerance `0.020`; separately assert pairwise non-overlap using the approved transformed sphere/capsule proxies.
- Physics: verify every one of 90 nodes is dynamic, gravity-affected, CCD-enabled, and has unchanged category/collision masks.
- Integration: reconcile `90 -> 89`, `30 -> 90`, and `90 -> 0`; after actions complete, active-node counts match targets and no stale `pillRemoving` node is treated as active.
- Stress: advance exactly 120 frames at `1/60` second to settle, then run the existing ten alternating sweeps at 90 for tablet, pill, capsule, and softgel; assert containment, finite state, and bounded speed.
- Build: clean Debug build, full unit suite, then Release build with no newly introduced warnings.
- Manual: compare settled 0, 18, 30, and 90 on a small and large iPhone simulator running iOS 26; test light/dark mode and rapid drag.
- Screenshot fixture: medication name `Visual Test`, quantity `90`, shape `.tablet`, bottle color `D99A00`, default camera/light, iPhone 17 Pro with iOS 26.5. Enter through the normal medication-detail UI, advance/wait for the deterministic 120-frame settle, then capture the app screenshot.
- Performance: measure a 10-second Release rotation at 90 and document device/runtime, average FPS, worst hitch, hangs, and CPU symptoms. Gate: average FPS `>= 50`, no hitch `> 100 ms`, and no trace-backed blocking regression.

## 7. Definition of Done / QA Gate

Agent 2 may hand off only after the clean build, automated matrix, simulator comparisons, performance observation, self-review, and screenshot succeed. Agent 3 must independently rebuild, execute the count/physics/containment matrix, inspect the actual UI at 30 and 90, and verify the supplied 90 screenshot. Only Agent 3 may return PASS. Physical-device results must be identified separately from simulator results.

## Architecture Decision Record

Use an exact dynamic-object representation through 90 because the requested visual meaning depends on real medication volume and interaction. Clamp only above 90 to bound SceneKit cost. This intentionally accepts higher physics cost than the former 18-node cap and requires explicit 90-body stability/performance evidence.
