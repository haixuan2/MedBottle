# Implementation Plan: Fast Bottle Rotation Containment

## Overview

Close and stabilize the SceneKit collision envelope so pills remain inside the visible medication bottle during rapid horizontal rotation. Keep the current SwiftUI interaction, visual bottle, medication data, and iOS 26.0 deployment target unchanged.

## Architecture Decisions

- Keep the rotating bottle shell, cap, and label as presentation-only nodes.
- Place a stationary axisymmetric physics envelope under the scene assembly at `(0, -0.08, 0)` because Y-axis rotation does not change a cylindrical boundary.
- Close the envelope with continuous walls, a floor, and an invisible lid; remove per-frame kinematic collider transform resets.
- Enable SceneKit continuous collision detection at `0.044` scene units, half the smallest pill extent.
- Preserve the existing bounded rotational impulse and move rotation-history ownership from factory-global state to each view coordinator.
- Add no dependency and make no persistence, networking, navigation, or medication-model changes.

## Task List

### Phase 1: Regression Gate

- [x] Add a SceneKit test file to the unit-test target.
- [x] Prove the current scene lacks a closed stationary envelope and positive CCD.
- [x] Encode the signed fast-rotation frame sequence and per-frame containment invariants.

### Checkpoint: Red

- [x] The targeted regression test fails against the current implementation for the reported containment gap.

### Phase 2: Minimum Fix

- [x] Add the stationary floor/walls/lid collision envelope.
- [x] Remove moving-collider synchronization from interactive rotation.
- [x] Enable the explicit CCD threshold on every dynamic pill.
- [x] Keep interaction rotation state local to the coordinator.

### Checkpoint: Green

- [x] Targeted physics tests pass.
- [x] Full unit suite passes.
- [x] Debug build succeeds without new warnings.

### Phase 3: Independent QA

- [x] Agent 2 completes self-review and handoff.
- [x] Agent 3 runs clean builds, automated tests, simulator stress checks, and regression checks.
- [x] Route and correct any defect until Agent 3 returns PASS.

### Final QA Decision

- **PASS** — 31/31 tests passed on iPhone 17 Pro with iOS 26.5.
- The five bottle-physics tests passed on iPhone 17e with iOS 26.4.
- A clean generic iOS Simulator Release build passed and the Debug app launched successfully.
- A signed Debug build installed and launched on iPhone 16 Pro Max with iOS 26.5.2; the user confirmed the version works well on-device.
- No reproducible defect or unresolved P0/P1 issue was found in the executed matrix.
- Agent 3 did not execute appearance/accessibility UI modes or lifecycle/relaunch checks; these remain documented coverage limitations rather than observed defects.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| SceneKit simulation variance | Medium | Assert boundary structure and sample every fixed-time stress frame across all pill shapes/counts. |
| Lid/wall mismatch | High | Derive continuous wall height/center from the published floor and lid planes. |
| CCD performance cost | Medium | Use the smallest effective threshold and test the maximum visible count of 18. |
| Motion becomes visually inert | Low | Preserve the existing bounded pill impulse and verify the interaction on a physical device. |

## Open Questions

- None. Agent 1 approved the numeric containment contract and Agent 3 approved its testability.
