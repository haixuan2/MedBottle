# Fast Bottle Rotation Containment

## Task 1: Add the failing containment regression

**Description:** Add deterministic SceneKit tests that expose the missing lid/moving-envelope design and disabled CCD before production changes.

**Acceptance criteria:**

- [x] The test checks the published envelope bounds and collision masks.
- [x] The test checks CCD equals `0.044` for every pill.
- [x] The stress matrix covers all four shapes at inventories 1 and 18.

**Verification:**

- [x] Targeted `xcodebuild test` fails before the production fix.

**Dependencies:** None

**Files likely touched:**

- `MedBottle/MedBottleTests/BottleScenePhysicsTests.swift`
- `MedBottle/MedBottle.xcodeproj/project.pbxproj`

**Estimated scope:** Small

## Task 2: Close and stabilize the physics envelope

**Description:** Separate visual rotation from a stationary closed cylinder and enable pill CCD without changing the visible interaction.

**Acceptance criteria:**

- [x] Floor, continuous walls, and lid form the approved envelope.
- [x] Pills cannot leave the envelope during the fixed fast-rotation matrix.
- [x] Rotation no longer resets moving kinematic collider transforms.

**Verification:**

- [x] Targeted physics tests pass.
- [x] Debug build succeeds.
- [x] Manual check: normal and fast drags preserve rotation responsiveness and containment.

The exact ten-sweep interaction was executed deterministically frame by frame for every supported pill shape at counts 1 and 18 on two simulator/runtime combinations. The signed build was then installed and launched on an iPhone 16 Pro Max with iOS 26.5.2, where the user confirmed the version works well.

**Dependencies:** Task 1

**Files likely touched:**

- `MedBottle/MedBottle/BottleSceneView.swift`

**Estimated scope:** Small

## Task 3: Verify and hand off to independent QA

**Description:** Run the relevant suite, self-review the change, and give Agent 3 exact reproduction steps for clean independent validation.

**Acceptance criteria:**

- [x] Full automated suite and clean Debug build pass.
- [x] No new compiler warnings or unresolved known issues remain.
- [x] Agent 3 executes targeted and regression validation and returns PASS.

**Verification:**

- [x] `xcodebuild test` passes on the primary iOS 26.5 simulator (31/31).
- [x] Small-device iOS 26.4 bottle-physics regression passes (5/5).

**Dependencies:** Task 2

**Files likely touched:** None

**Estimated scope:** Small
