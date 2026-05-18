@preconcurrency import SceneKit
import SwiftUI

@MainActor
struct BottleSceneView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let medication: Medication

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.layer.masksToBounds = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.isPlaying = false
        view.preferredFramesPerSecond = 30
        let scene = context.coordinator.scene ?? BottleSceneFactory.scene(for: medication, colorScheme: colorScheme)
        scene.isPaused = true
        context.coordinator.scene = scene
        view.scene = scene
        context.coordinator.sceneView = view
        context.coordinator.renderedState = SceneRenderState(medication: medication, colorScheme: colorScheme)
        context.coordinator.playTemporarily()

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene == nil {
            let scene = context.coordinator.scene ?? BottleSceneFactory.scene(for: medication, colorScheme: colorScheme)
            context.coordinator.scene = scene
            view.scene = scene
        }

        let nextState = SceneRenderState(medication: medication, colorScheme: colorScheme)
        if context.coordinator.renderedState != nextState {
            BottleSceneFactory.update(
                scene: context.coordinator.scene ?? view.scene,
                medication: medication,
                colorScheme: colorScheme
            )
            context.coordinator.renderedState = nextState
            context.coordinator.playTemporarily()
        }
        context.coordinator.sceneView = view
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var sceneView: SCNView?
        var scene: SCNScene?
        var renderedState: SceneRenderState?
        private var accumulatedRotation: Float = 0
        private var gestureStartRotation: Float = 0
        private var playbackStopTask: Task<Void, Never>?

        deinit {
            playbackStopTask?.cancel()
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let sceneView, let scene = sceneView.scene else { return }
            let translation = recognizer.translation(in: sceneView)

            switch recognizer.state {
            case .began:
                startPlayback()
                gestureStartRotation = accumulatedRotation
            case .changed:
                let rotation = gestureStartRotation + Float(translation.x) * 0.012
                BottleSceneFactory.applyInteractiveRotation(scene: scene, rotation: rotation, horizontalOffset: translation.x)
            case .ended, .cancelled, .failed:
                accumulatedRotation = gestureStartRotation + Float(translation.x) * 0.012
                BottleSceneFactory.applyInteractiveRotation(scene: scene, rotation: accumulatedRotation, horizontalOffset: 0)
                playTemporarily(duration: 0.8)
            default:
                break
            }
        }

        func playTemporarily(duration: TimeInterval = 1.2) {
            startPlayback()
            playbackStopTask = Task { [weak self] in
                let nanoseconds = UInt64(duration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.stopPlayback()
                }
            }
        }

        private func startPlayback() {
            playbackStopTask?.cancel()
            playbackStopTask = nil
            sceneView?.scene?.isPaused = false
            sceneView?.isPlaying = true
        }

        private func stopPlayback() {
            sceneView?.isPlaying = false
            sceneView?.scene?.isPaused = true
        }
    }

    struct SceneRenderState: Equatable {
        let id: Medication.ID
        let name: String
        let tabletsRemaining: Int
        let tabletsPerDose: Int
        let bottleColorHex: String
        let medicationShape: MedicationShape
        let colorScheme: ColorScheme

        init(medication: Medication, colorScheme: ColorScheme) {
            id = medication.id
            name = medication.name
            tabletsRemaining = medication.tabletsRemaining
            tabletsPerDose = medication.tabletsPerDose
            bottleColorHex = medication.bottleColorHex
            medicationShape = medication.medicationShape
            self.colorScheme = colorScheme
        }
    }
}

@MainActor
enum BottleSceneFactory {
    enum NodeName {
        static let assembly = "assembly"
        static let cap = "cap"
        static let bottle = "bottle"
        static let body = "body"
        static let neck = "neck"
        static let bottomRim = "bottomRim"
        static let highlight = "highlight"
        static let label = "label"
        static let tablets = "tablets"
        static let pill = "pill"
        static let pillRemoving = "pillRemoving"
        static let shadowPlane = "shadowPlane"
        static let collisionFloor = "collisionFloor"
        static let collisionWalls = "collisionWalls"
        static let keyLight = "keyLight"
        static let fillLight = "fillLight"
        static let ambientLight = "ambientLight"
    }

    enum PhysicsCategory {
        static let pill: Int = 1 << 0
        static let container: Int = 1 << 1
    }

    private enum PhysicsMetrics {
        static let wallInnerRadius: CGFloat = 0.62
        static let wallThickness: CGFloat = 0.18
        static let wallHeight: CGFloat = 2.42
        static let wallCenterY: Float = -0.27
        static let wallSegmentCount = 16

        static let floorRadius: CGFloat = 0.62
        static let floorThickness: CGFloat = 0.02
        static let floorCenterY: Float = -1.485

        static let spawnColumns = 6
        static let spawnRingRadius: Float = 0.30
        static let spawnStartY: Float = -0.48
        static let spawnLayerSpacing: Float = 0.20

        static let spinImpulseScale: Float = 0.07
        static let maxSpinImpulse: Float = 0.055

        static let collisionMargin: CGFloat = 0.001
    }

    private enum LabelMetrics {
        static let radius: CGFloat = 0.805
        static let width: CGFloat = 1.34
        static let height: CGFloat = 1.48
        static let columns = 56
        static let rows = 12
    }

    private enum RenderOrder {
        static let collisionOnly = -100
        static let pills = 0
        static let bottleShell = 40
        static let bottleHighlight = 50
        static let cap = 70
        static let label = 100
    }

    private enum SceneFraming {
        static let assemblyPosition = SCNVector3(0, -0.26, 0)
        static let cameraPosition = SCNVector3(0, 0.34, 7.8)
        static let cameraPitch: Float = -0.05
    }

    private struct LabelImageKey: Hashable {
        let id: Medication.ID
        let name: String
        let tabletsRemaining: Int
        let tabletsPerDose: Int
        let medicationShape: MedicationShape

        init(medication: Medication) {
            id = medication.id
            name = medication.name
            tabletsRemaining = medication.tabletsRemaining
            tabletsPerDose = medication.tabletsPerDose
            medicationShape = medication.medicationShape
        }
    }

    private static var previousInteractiveRotation: Float?
    private static var labelImageCache: [LabelImageKey: UIImage] = [:]

    private struct LightingProfile {
        let key: CGFloat
        let environment: CGFloat
        let exposure: CGFloat
        let contrast: CGFloat
        let saturation: CGFloat

        static func profile(for colorScheme: ColorScheme) -> LightingProfile {
            if colorScheme == .dark {
                return LightingProfile(key: 420, environment: 1.25, exposure: -0.70, contrast: 0.08, saturation: 0.90)
            }

            return LightingProfile(key: 520, environment: 1.45, exposure: -0.56, contrast: 0.08, saturation: 0.92)
        }
    }

    static func scene(for medication: Medication, colorScheme: ColorScheme) -> SCNScene {
        previousInteractiveRotation = nil

        let lighting = LightingProfile.profile(for: colorScheme)
        let scene = SCNScene()
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)
        applyLightingEnvironment(to: scene, colorScheme: colorScheme)
        scene.rootNode.addChildNode(cameraNode(lighting: lighting))
        scene.rootNode.addChildNode(keyLightNode(intensity: lighting.key))
        scene.rootNode.addChildNode(shadowPlaneNode(colorScheme: colorScheme))

        let assembly = SCNNode()
        assembly.name = NodeName.assembly
        assembly.position = SceneFraming.assemblyPosition
        scene.rootNode.addChildNode(assembly)

        let bottle = bottleNode(color: UIColor(hex: medication.bottleColorHex), colorScheme: colorScheme)
        assembly.addChildNode(bottle)

        let cap = capNode(colorScheme: colorScheme)
        cap.name = NodeName.cap
        cap.position = SCNVector3(0, 1.66, 0)
        bottle.addChildNode(cap)

        let label = labelNode(for: medication)
        label.position = SCNVector3(0, 0.18, 0)
        bottle.addChildNode(label)

        bottle.addChildNode(collisionFloorNode())
        bottle.addChildNode(collisionWallsNode())

        let tablets = tabletsNode(count: medication.tabletsRemaining, shape: medication.medicationShape)
        assembly.addChildNode(tablets)

        update(scene: scene, medication: medication, colorScheme: colorScheme)
        return scene
    }

    static func update(scene: SCNScene?, medication: Medication, colorScheme: ColorScheme) {
        guard let scene else { return }
        updateLighting(in: scene, colorScheme: colorScheme)
        guard let assembly = scene.rootNode.childNode(withName: NodeName.assembly, recursively: false) else { return }
        assembly.position = SceneFraming.assemblyPosition

        if let bottle = assembly.childNode(withName: NodeName.bottle, recursively: false) {
            removeLegacyFillNodes(from: bottle)
            applyBottleColor(to: bottle, color: UIColor(hex: medication.bottleColorHex), colorScheme: colorScheme)
            updateBottleHighlight(in: bottle, colorScheme: colorScheme)
        }

        if let cap = assembly.childNode(withName: NodeName.cap, recursively: true) {
            applyCapMaterials(to: cap, colorScheme: colorScheme)
        }

        if let label = assembly.childNode(withName: NodeName.label, recursively: true) {
            let image = cachedLabelImage(for: medication)
            label.geometry?.firstMaterial?.diffuse.contents = image
        }

        if let tablets = tabletGroup(in: assembly) {
            if tablets.name != tabletGroupName(shape: medication.medicationShape) {
                tablets.removeFromParentNode()
                let newTablets = tabletsNode(count: medication.tabletsRemaining, shape: medication.medicationShape)
                assembly.addChildNode(newTablets)
            } else {
                reconcileTabletCount(in: tablets, count: medication.tabletsRemaining, shape: medication.medicationShape)
            }
        }
    }

    static func applyInteractiveRotation(scene: SCNScene, rotation: Float, horizontalOffset: CGFloat) {
        guard let bottle = scene.rootNode.childNode(withName: NodeName.bottle, recursively: true) else { return }
        let delta = rotationDelta(rotation: rotation)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        bottle.eulerAngles = SCNVector3(0, rotation, 0)
        SCNTransaction.commit()

        synchronizeContainerPhysics(in: bottle)
        applyRotationalDrag(in: scene, delta: delta)
    }

    private static func rotationDelta(rotation: Float) -> Float {
        let previous = previousInteractiveRotation ?? rotation
        previousInteractiveRotation = rotation

        var delta = rotation - previous
        while delta > Float.pi { delta -= Float.pi * 2 }
        while delta < -Float.pi { delta += Float.pi * 2 }
        return delta
    }

    private static func synchronizeContainerPhysics(in node: SCNNode) {
        if node.physicsBody?.categoryBitMask == PhysicsCategory.container {
            node.physicsBody?.resetTransform()
        }

        for child in node.childNodes {
            synchronizeContainerPhysics(in: child)
        }
    }

    private static func removeLegacyFillNodes(from node: SCNNode) {
        for child in node.childNodes {
            let normalizedName = child.name?.lowercased() ?? ""
            if normalizedName == "liquid" || normalizedName.contains("filllevel") || normalizedName.contains("fill-level") {
                child.removeFromParentNode()
            } else {
                removeLegacyFillNodes(from: child)
            }
        }
    }

    private static func applyRotationalDrag(in scene: SCNScene, delta: Float) {
        guard abs(delta) > 0.0005 else { return }
        guard let assembly = scene.rootNode.childNode(withName: NodeName.assembly, recursively: false) else { return }
        guard let tablets = tabletGroup(in: assembly) else { return }

        let spinImpulse = max(
            -PhysicsMetrics.maxSpinImpulse,
            min(PhysicsMetrics.maxSpinImpulse, delta * PhysicsMetrics.spinImpulseScale)
        )

        for pill in tablets.childNodes where pill.name == NodeName.pill {
            guard let body = pill.physicsBody else { continue }
            let worldPosition = pill.presentation.worldPosition
            let tangentialImpulse = SCNVector3(
                -worldPosition.z * spinImpulse,
                0,
                worldPosition.x * spinImpulse
            )
            body.applyForce(tangentialImpulse, asImpulse: true)
            body.applyTorque(SCNVector4(0, 1, 0, spinImpulse * 0.02), asImpulse: true)
        }
    }

    private static func updateLighting(in scene: SCNScene, colorScheme: ColorScheme) {
        let lighting = LightingProfile.profile(for: colorScheme)
        applyLightingEnvironment(to: scene, colorScheme: colorScheme)
        if let keyLight = scene.rootNode.childNode(withName: NodeName.keyLight, recursively: false) {
            configureKeyLight(keyLight, intensity: lighting.key)
        } else {
            scene.rootNode.addChildNode(keyLightNode(intensity: lighting.key))
        }
        scene.rootNode.childNode(withName: NodeName.fillLight, recursively: false)?.removeFromParentNode()
        scene.rootNode.childNode(withName: NodeName.ambientLight, recursively: false)?.removeFromParentNode()
        if let shadowPlane = scene.rootNode.childNode(withName: NodeName.shadowPlane, recursively: false) {
            shadowPlane.geometry?.firstMaterial = shadowPlaneMaterial(colorScheme: colorScheme)
        } else {
            scene.rootNode.addChildNode(shadowPlaneNode(colorScheme: colorScheme))
        }

        if let camera = scene.rootNode.childNodes.compactMap(\.camera).first {
            camera.exposureOffset = lighting.exposure
            camera.contrast = lighting.contrast
            camera.saturation = lighting.saturation
        }
    }

    private static func applyLightingEnvironment(to scene: SCNScene, colorScheme: ColorScheme) {
        let lighting = LightingProfile.profile(for: colorScheme)
        if let environmentURL = Bundle.main.url(forResource: "studio_lighting", withExtension: "hdr") {
            scene.lightingEnvironment.contents = environmentURL
        }
        scene.lightingEnvironment.intensity = lighting.environment
    }

    private static func cameraNode(lighting: LightingProfile) -> SCNNode {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 31.5
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = lighting.exposure
        camera.contrast = lighting.contrast
        camera.saturation = lighting.saturation
        camera.zNear = 0.1
        camera.zFar = 100

        let node = SCNNode()
        node.camera = camera
        node.position = SceneFraming.cameraPosition
        node.eulerAngles.x = SceneFraming.cameraPitch
        return node
    }

    private static func keyLightNode(intensity: CGFloat) -> SCNNode {
        let light = SCNLight()

        let node = SCNNode()
        node.name = NodeName.keyLight
        node.light = light
        configureKeyLight(node, intensity: intensity)
        return node
    }

    private static func configureKeyLight(_ node: SCNNode, intensity: CGFloat) {
        let light = node.light ?? SCNLight()
        light.type = .directional
        light.intensity = intensity
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowSampleCount = 24
        light.shadowRadius = 4
        light.shadowBias = 0.002
        light.shadowColor = UIColor.black.withAlphaComponent(0.34)

        node.light = light
        node.position = SCNVector3(-2.6, 4.6, 4.0)
        node.look(at: SCNVector3(0, -0.3, 0))
    }

    private static func shadowPlaneNode(colorScheme: ColorScheme) -> SCNNode {
        let plane = SCNPlane(width: 3.0, height: 1.8)
        plane.materials = [shadowPlaneMaterial(colorScheme: colorScheme)]

        let node = SCNNode(geometry: plane)
        node.name = NodeName.shadowPlane
        node.position = SCNVector3(0, -1.96, 0.10)
        node.eulerAngles.x = -Float.pi / 2
        node.castsShadow = false
        return node
    }

    private static func shadowPlaneMaterial(colorScheme: ColorScheme) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.roughness.contents = 0.92
        material.metalness.contents = 0.0
        material.lightingModel = .physicallyBased
        material.colorBufferWriteMask = []
        material.blendMode = .replace
        material.transparency = 1.0
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        return material
    }

    private static func bottleNode(color: UIColor, colorScheme: ColorScheme) -> SCNNode {
        let node = SCNNode()
        node.name = NodeName.bottle
        node.position = SCNVector3(0, -0.08, 0)

        let body = SCNTube(innerRadius: 0.68, outerRadius: 0.78, height: 2.85)
        body.radialSegmentCount = 128
        body.heightSegmentCount = 18
        let bodyNode = SCNNode(geometry: body)
        bodyNode.name = NodeName.body
        bodyNode.position = SCNVector3(0, -0.04, 0)
        bodyNode.eulerAngles.y = Float.pi
        bodyNode.renderingOrder = RenderOrder.bottleShell
        bodyNode.castsShadow = true
        node.addChildNode(bodyNode)

        let topBand = SCNTube(innerRadius: 0.68, outerRadius: 0.79, height: 0.34)
        topBand.radialSegmentCount = 128
        let topBandNode = SCNNode(geometry: topBand)
        topBandNode.name = NodeName.neck
        topBandNode.position = SCNVector3(0, 1.20, 0)
        topBandNode.eulerAngles.y = Float.pi
        topBandNode.renderingOrder = RenderOrder.bottleShell
        topBandNode.castsShadow = true
        node.addChildNode(topBandNode)

        let bottomRim = SCNTorus(ringRadius: 0.70, pipeRadius: 0.045)
        bottomRim.ringSegmentCount = 128
        bottomRim.pipeSegmentCount = 18
        let bottomRimNode = SCNNode(geometry: bottomRim)
        bottomRimNode.name = NodeName.bottomRim
        bottomRimNode.position = SCNVector3(0, -1.46, 0)
        bottomRimNode.renderingOrder = RenderOrder.bottleShell
        bottomRimNode.castsShadow = true
        node.addChildNode(bottomRimNode)

        applyBottleColor(to: node, color: color, colorScheme: colorScheme)

        let highlight = SCNPlane(width: 0.08, height: 2.5)
        let highlightMaterial = SCNMaterial()
        highlightMaterial.diffuse.contents = highlightColor(for: colorScheme)
        highlightMaterial.lightingModel = .constant
        highlightMaterial.blendMode = .alpha
        highlightMaterial.writesToDepthBuffer = false
        highlightMaterial.readsFromDepthBuffer = true
        highlightMaterial.transparencyMode = .singleLayer
        highlight.materials = [highlightMaterial]
        let highlightNode = SCNNode(geometry: highlight)
        highlightNode.name = NodeName.highlight
        highlightNode.position = SCNVector3(-0.58, -0.06, 0.56)
        highlightNode.eulerAngles = SCNVector3(0, 0.34, 0.02)
        highlightNode.renderingOrder = RenderOrder.bottleHighlight
        highlightNode.castsShadow = false
        node.addChildNode(highlightNode)

        return node
    }

    private static func applyBottleColor(to bottle: SCNNode, color: UIColor, colorScheme: ColorScheme) {
        bottle.childNode(withName: NodeName.body, recursively: false)?.geometry?.materials = [bottleMaterial(color: color, alpha: 0.58, colorScheme: colorScheme)]
        bottle.childNode(withName: NodeName.neck, recursively: false)?.geometry?.materials = [bottleMaterial(color: color, alpha: 0.70, colorScheme: colorScheme)]
        bottle.childNode(withName: NodeName.bottomRim, recursively: false)?.geometry?.materials = [bottleMaterial(color: color, alpha: 0.64, colorScheme: colorScheme)]
    }

    private static func bottleMaterial(color: UIColor, alpha: CGFloat, colorScheme: ColorScheme) -> SCNMaterial {
        let material = SCNMaterial()
        let balancedColor = blend(color, with: .black, ratio: colorScheme == .dark ? 0.34 : 0.22)
        material.diffuse.contents = balancedColor.withAlphaComponent(alpha)
        material.specular.contents = UIColor.white.withAlphaComponent(colorScheme == .dark ? 0.20 : 0.24)
        material.emission.contents = UIColor.clear
        material.transparency = alpha
        material.roughness.contents = 0.2
        material.metalness.contents = 0.0
        material.blendMode = .alpha
        material.transparencyMode = .dualLayer
        material.cullMode = .back
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = true
        material.lightingModel = .physicallyBased
        material.fresnelExponent = 1.35
        return material
    }

    private static func updateBottleHighlight(in bottle: SCNNode, colorScheme: ColorScheme) {
        bottle.childNode(withName: NodeName.highlight, recursively: false)?
            .geometry?
            .firstMaterial?
            .diffuse.contents = highlightColor(for: colorScheme)
    }

    private static func highlightColor(for colorScheme: ColorScheme) -> UIColor {
        UIColor(
            red: 0.95,
            green: 0.92,
            blue: 0.78,
            alpha: colorScheme == .dark ? 0.028 : 0.045
        )
    }

    private static func capNode(colorScheme: ColorScheme) -> SCNNode {
        let cap = SCNCylinder(radius: 0.92, height: 0.48)
        cap.radialSegmentCount = 128
        cap.heightSegmentCount = 4

        let material = capMaterial(colorScheme: colorScheme)
        cap.materials = [material]

        let node = SCNNode(geometry: cap)
        node.position = SCNVector3(0, 1.58, 0)
        node.renderingOrder = RenderOrder.cap
        node.castsShadow = true

        let underside = SCNCylinder(radius: 0.72, height: 0.018)
        underside.radialSegmentCount = 128
        underside.materials = [capUndersideMaterial(colorScheme: colorScheme)]
        let undersideNode = SCNNode(geometry: underside)
        undersideNode.position = SCNVector3(0, -0.262, 0)
        undersideNode.renderingOrder = RenderOrder.cap
        undersideNode.castsShadow = true
        node.addChildNode(undersideNode)

        let skirt = SCNCylinder(radius: 0.94, height: 0.22)
        skirt.radialSegmentCount = 128
        skirt.heightSegmentCount = 3
        skirt.materials = [material]
        let skirtNode = SCNNode(geometry: skirt)
        skirtNode.position = SCNVector3(0, -0.31, 0)
        skirtNode.renderingOrder = RenderOrder.cap
        skirtNode.castsShadow = true
        node.addChildNode(skirtNode)

        for index in 0..<36 {
            let ridge = SCNBox(width: 0.026, height: 0.48, length: 0.075, chamferRadius: 0.01)
            ridge.materials = [material]
            let ridgeNode = SCNNode(geometry: ridge)
            let angle = (Float(index) / 36) * Float.pi * 2
            ridgeNode.position = SCNVector3(cos(angle) * 0.94, 0, sin(angle) * 0.94)
            ridgeNode.eulerAngles.y = -angle
            ridgeNode.renderingOrder = RenderOrder.cap
            ridgeNode.castsShadow = true
            node.addChildNode(ridgeNode)
        }

        return node
    }

    private static func applyCapMaterials(to cap: SCNNode, colorScheme: ColorScheme) {
        let material = capMaterial(colorScheme: colorScheme)
        cap.geometry?.materials = [material]
        for child in cap.childNodes {
            if child.name == nil {
                child.geometry?.materials = [material]
            }
        }
    }

    private static func capMaterial(colorScheme: ColorScheme) -> SCNMaterial {
        let material = SCNMaterial()
        let plastic = colorScheme == .dark
            ? UIColor(red: 0.50, green: 0.47, blue: 0.38, alpha: 1)
            : UIColor(red: 0.72, green: 0.68, blue: 0.56, alpha: 1)
        material.diffuse.contents = plastic
        material.specular.contents = UIColor.white.withAlphaComponent(0.16)
        material.emission.contents = UIColor.clear
        material.roughness.contents = 0.46
        material.metalness.contents = 0.0
        material.lightingModel = .physicallyBased
        return material
    }

    private static func capUndersideMaterial(colorScheme: ColorScheme) -> SCNMaterial {
        let material = SCNMaterial()
        let liner = colorScheme == .dark
            ? UIColor(red: 0.38, green: 0.36, blue: 0.30, alpha: 1)
            : UIColor(red: 0.62, green: 0.58, blue: 0.48, alpha: 1)
        material.diffuse.contents = liner
        material.specular.contents = UIColor.white.withAlphaComponent(0.07)
        material.emission.contents = UIColor.clear
        material.roughness.contents = 0.58
        material.metalness.contents = 0.0
        material.lightingModel = .physicallyBased
        material.writesToDepthBuffer = true
        return material
    }

    private static func labelNode(for medication: Medication) -> SCNNode {
        let geometry = curvedLabelGeometry()
        let material = SCNMaterial()
        let image = cachedLabelImage(for: medication)
        material.diffuse.contents = image
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.mipFilter = .linear
        material.specular.contents = UIColor.white.withAlphaComponent(0.02)
        material.emission.contents = UIColor.clear
        material.lightingModel = .constant
        material.roughness.contents = 0.96
        material.metalness.contents = 0
        material.transparency = 1
        material.blendMode = .replace
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = true
        material.transparencyMode = .singleLayer
        material.cullMode = .back
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = NodeName.label
        node.renderingOrder = RenderOrder.label
        return node
    }

    private static func curvedLabelGeometry() -> SCNGeometry {
        let columns = LabelMetrics.columns
        let rows = LabelMetrics.rows
        let radius = Float(LabelMetrics.radius)
        let angularWidth = Float(LabelMetrics.width / LabelMetrics.radius)
        let startAngle = -angularWidth / 2
        let height = Float(LabelMetrics.height)

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var textureCoordinates: [CGPoint] = []
        vertices.reserveCapacity((columns + 1) * (rows + 1))
        normals.reserveCapacity(vertices.capacity)
        textureCoordinates.reserveCapacity(vertices.capacity)

        for row in 0...rows {
            let v = Float(row) / Float(rows)
            let y = -height / 2 + v * height

            for column in 0...columns {
                let u = Float(column) / Float(columns)
                let angle = startAngle + u * angularWidth
                let x = sin(angle) * radius
                let z = cos(angle) * radius

                vertices.append(SCNVector3(x, y, z))
                normals.append(SCNVector3(sin(angle), 0, cos(angle)))
                textureCoordinates.append(CGPoint(x: CGFloat(u), y: CGFloat(1 - v)))
            }
        }

        var indices: [Int32] = []
        indices.reserveCapacity(columns * rows * 6)
        for row in 0..<rows {
            for column in 0..<columns {
                let lowerLeft = Int32(row * (columns + 1) + column)
                let lowerRight = lowerLeft + 1
                let upperLeft = Int32((row + 1) * (columns + 1) + column)
                let upperRight = upperLeft + 1

                indices.append(contentsOf: [
                    lowerLeft, lowerRight, upperLeft,
                    lowerRight, upperRight, upperLeft
                ])
            }
        }

        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: textureCoordinates)
            ],
            elements: [
                SCNGeometryElement(indices: indices, primitiveType: .triangles)
            ]
        )
    }

    private static func collisionFloorNode() -> SCNNode {
        let floor = SCNCylinder(radius: PhysicsMetrics.floorRadius, height: PhysicsMetrics.floorThickness)
        floor.radialSegmentCount = 96
        floor.materials = [invisibleCollisionMaterial()]

        let node = SCNNode(geometry: floor)
        node.name = NodeName.collisionFloor
        node.position = SCNVector3(0, PhysicsMetrics.floorCenterY, 0)
        prepareCollisionOnlyNode(node)

        let shape = SCNPhysicsShape(
            geometry: floor,
            options: [
                .type: SCNPhysicsShape.ShapeType.convexHull,
                .collisionMargin: PhysicsMetrics.collisionMargin
            ]
        )
        let body = SCNPhysicsBody(type: .kinematic, shape: shape)
        body.categoryBitMask = PhysicsCategory.container
        body.collisionBitMask = PhysicsCategory.pill
        body.contactTestBitMask = 0
        body.friction = 0.96
        body.restitution = 0.04
        node.physicsBody = body
        node.geometry = nil
        return node
    }

    private static func collisionWallsNode() -> SCNNode {
        let group = SCNNode()
        group.name = NodeName.collisionWalls
        prepareCollisionOnlyNode(group)

        let centerRadius = PhysicsMetrics.wallInnerRadius + PhysicsMetrics.wallThickness / 2
        let segmentArc = (2 * CGFloat.pi * centerRadius) / CGFloat(PhysicsMetrics.wallSegmentCount)
        let segmentWidth = segmentArc * 1.18

        for index in 0..<PhysicsMetrics.wallSegmentCount {
            let panel = SCNBox(
                width: segmentWidth,
                height: PhysicsMetrics.wallHeight,
                length: PhysicsMetrics.wallThickness,
                chamferRadius: 0
            )
            panel.materials = [invisibleCollisionMaterial()]

            let panelNode = SCNNode(geometry: panel)
            let angle = (Float(index) / Float(PhysicsMetrics.wallSegmentCount)) * Float.pi * 2
            panelNode.name = "\(NodeName.collisionWalls)-segment-\(index)"
            panelNode.position = SCNVector3(
                cos(angle) * Float(centerRadius),
                PhysicsMetrics.wallCenterY,
                sin(angle) * Float(centerRadius)
            )
            panelNode.eulerAngles.y = Float.pi / 2 - angle
            prepareCollisionOnlyNode(panelNode)
            panelNode.physicsBody = wallSegmentPhysicsBody(for: panel)
            panelNode.geometry = nil
            group.addChildNode(panelNode)
        }

        return group
    }

    private static func wallSegmentPhysicsBody(for geometry: SCNGeometry) -> SCNPhysicsBody {
        let shape = SCNPhysicsShape(
            geometry: geometry,
            options: [
                .type: SCNPhysicsShape.ShapeType.boundingBox,
                .collisionMargin: PhysicsMetrics.collisionMargin
            ]
        )
        let body = SCNPhysicsBody(type: .kinematic, shape: shape)
        body.categoryBitMask = PhysicsCategory.container
        body.collisionBitMask = PhysicsCategory.pill
        body.contactTestBitMask = 0
        body.friction = 0.92
        body.restitution = 0.04
        return body
    }

    private static func invisibleCollisionMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.clear
        material.ambient.contents = UIColor.clear
        material.specular.contents = UIColor.clear
        material.emission.contents = UIColor.clear
        material.transparency = 0
        material.blendMode = .replace
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.colorBufferWriteMask = []
        material.isDoubleSided = false
        return material
    }

    private static func prepareCollisionOnlyNode(_ node: SCNNode) {
        node.categoryBitMask = 0
        node.castsShadow = false
        node.opacity = 1
        node.renderingOrder = RenderOrder.collisionOnly
        node.geometry?.firstMaterial = invisibleCollisionMaterial()
    }

    private static func tabletsNode(count: Int, shape: MedicationShape) -> SCNNode {
        let group = SCNNode()
        group.name = tabletGroupName(shape: shape)

        let visibleCount = min(count, 18)
        guard visibleCount > 0 else { return group }

        for index in 0..<visibleCount {
            group.addChildNode(tabletNode(shape: shape, index: index, visibleCount: visibleCount))
        }

        return group
    }

    private static func reconcileTabletCount(in group: SCNNode, count: Int, shape: MedicationShape) {
        let targetCount = min(count, 18)
        let activePills = group.childNodes.filter { $0.name == NodeName.pill }

        if activePills.count > targetCount {
            let removalCount = activePills.count - targetCount
            for node in activePills.suffix(removalCount) {
                removePillGracefully(node)
            }
        } else if activePills.count < targetCount {
            for index in activePills.count..<targetCount {
                group.addChildNode(tabletNode(shape: shape, index: index, visibleCount: targetCount))
            }
        }
    }

    private static func removePillGracefully(_ node: SCNNode) {
        node.name = NodeName.pillRemoving
        node.physicsBody = nil

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        let shrink = SCNAction.scale(to: 0, duration: 0.3)
        shrink.timingMode = .easeInEaseOut
        node.runAction(.sequence([shrink, .removeFromParentNode()]))
        SCNTransaction.commit()
    }

    private static func tabletNode(shape: MedicationShape, index: Int, visibleCount: Int) -> SCNNode {
        let tablet = tabletGeometry(for: shape)
        let material = SCNMaterial()
        material.diffuse.contents = tabletColor(for: shape, index: index)
        material.specular.contents = UIColor.white.withAlphaComponent(0.22)
        material.roughness.contents = 0.62
        material.metalness.contents = 0.0
        material.lightingModel = .physicallyBased
        tablet.materials = [material]

        let node = SCNNode(geometry: tablet)
        node.name = NodeName.pill
        node.renderingOrder = RenderOrder.pills
        node.position = pillSpawnPosition(index: index)
        node.eulerAngles = pillSpawnRotation(shape: shape, index: index)
        node.physicsBody = pillPhysicsBody(for: tablet)
        node.physicsBody?.isAffectedByGravity = true
        node.castsShadow = true
        return node
    }

    private static func pillSpawnPosition(index: Int) -> SCNVector3 {
        let layer = index / PhysicsMetrics.spawnColumns
        let slot = index % PhysicsMetrics.spawnColumns
        let angleStep = (Float.pi * 2) / Float(PhysicsMetrics.spawnColumns)
        let stagger = layer.isMultiple(of: 2) ? Float(0) : angleStep / 2
        let angle = Float(slot) * angleStep + stagger
        let y = PhysicsMetrics.spawnStartY + Float(layer) * PhysicsMetrics.spawnLayerSpacing

        return SCNVector3(
            cos(angle) * PhysicsMetrics.spawnRingRadius,
            y,
            sin(angle) * PhysicsMetrics.spawnRingRadius
        )
    }

    private static func pillSpawnRotation(shape: MedicationShape, index: Int) -> SCNVector3 {
        let yaw = (Float(index) * 0.73).truncatingRemainder(dividingBy: Float.pi * 2)
        let smallTilt = Float(index % 5) * 0.035

        switch shape {
        case .capsule:
            return SCNVector3(0.12 + smallTilt, yaw, Float.pi / 2)
        case .tablet:
            return SCNVector3(0.10 + smallTilt, yaw, 0.08)
        case .pill, .softgel:
            return SCNVector3(smallTilt, yaw, smallTilt * 0.5)
        }
    }

    private static func pillPhysicsBody(for geometry: SCNGeometry) -> SCNPhysicsBody {
        let shape = SCNPhysicsShape(
            geometry: geometry,
            options: [
                .type: SCNPhysicsShape.ShapeType.boundingBox,
                .collisionMargin: PhysicsMetrics.collisionMargin
            ]
        )
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = 0.012
        body.isAffectedByGravity = false
        body.continuousCollisionDetectionThreshold = 0
        body.friction = 0.72
        body.rollingFriction = 0.18
        body.restitution = 0.04
        body.damping = 0.36
        body.angularDamping = 0.42
        body.allowsResting = true
        body.velocity = SCNVector3Zero
        body.angularVelocity = SCNVector4Zero
        body.categoryBitMask = PhysicsCategory.pill
        body.collisionBitMask = PhysicsCategory.pill | PhysicsCategory.container
        body.contactTestBitMask = 0
        return body
    }

    private static func blend(_ color: UIColor, with overlay: UIColor, ratio: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var overlayRed: CGFloat = 0
        var overlayGreen: CGFloat = 0
        var overlayBlue: CGFloat = 0
        var overlayAlpha: CGFloat = 0

        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        overlay.getRed(&overlayRed, green: &overlayGreen, blue: &overlayBlue, alpha: &overlayAlpha)

        return UIColor(
            red: red * (1 - ratio) + overlayRed * ratio,
            green: green * (1 - ratio) + overlayGreen * ratio,
            blue: blue * (1 - ratio) + overlayBlue * ratio,
            alpha: alpha * (1 - ratio) + overlayAlpha * ratio
        )
    }

    private static func tabletGroup(in assembly: SCNNode) -> SCNNode? {
        assembly.childNodes.first { node in
            node.name?.hasPrefix("\(NodeName.tablets)|") == true
        }
    }

    private static func tabletGroupName(shape: MedicationShape) -> String {
        "\(NodeName.tablets)|\(shape.rawValue)"
    }

    private static func tabletGeometry(for shape: MedicationShape) -> SCNGeometry {
        switch shape {
        case .tablet:
            let cylinder = SCNCylinder(radius: 0.118, height: 0.088)
            cylinder.radialSegmentCount = 64
            cylinder.heightSegmentCount = 3
            return cylinder
        case .pill:
            let sphere = SCNSphere(radius: 0.116)
            sphere.segmentCount = 48
            return sphere
        case .capsule:
            let capsule = SCNCapsule(capRadius: 0.09, height: 0.36)
            capsule.radialSegmentCount = 48
            capsule.heightSegmentCount = 12
            return capsule
        case .softgel:
            let sphere = SCNSphere(radius: 0.128)
            sphere.segmentCount = 48
            return sphere
        }
    }

    private static func tabletColor(for shape: MedicationShape, index: Int) -> UIColor {
        switch shape {
        case .tablet:
            return index.isMultiple(of: 5) ? UIColor(red: 1, green: 0.93, blue: 0.38, alpha: 1) : UIColor(red: 0.96, green: 0.74, blue: 0.05, alpha: 1)
        case .pill:
            return UIColor(red: 0.98, green: 0.78, blue: 0.10, alpha: 1)
        case .capsule:
            return index.isMultiple(of: 2) ? UIColor(red: 1, green: 0.82, blue: 0.16, alpha: 1) : UIColor(red: 1, green: 0.96, blue: 0.70, alpha: 1)
        case .softgel:
            return UIColor(red: 0.95, green: 0.61, blue: 0.02, alpha: 0.94)
        }
    }

    private static func applyTabletMotion(to group: SCNNode, horizontalOffset: CGFloat) {
        let xTilt = max(-1, min(1, Float(horizontalOffset / 150)))
        let yTilt: Float = 0
        let target = SCNVector3(xTilt * 0.34, -abs(yTilt) * 0.08, yTilt * 0.24)

        group.position = target
        group.eulerAngles = SCNVector3(yTilt * 0.16, xTilt * 0.10, -xTilt * 0.24)

        for (index, child) in group.childNodes.enumerated() {
            let spin = CGFloat(xTilt * 0.25 + yTilt * 0.18 + Float(index % 3) * 0.03)
            child.eulerAngles.x += Float(spin * 0.4)
            child.eulerAngles.y += Float(spin)
            child.eulerAngles.z -= Float(spin * 0.55)
        }
    }

    private static func cachedLabelImage(for medication: Medication) -> UIImage {
        let key = LabelImageKey(medication: medication)
        if let image = labelImageCache[key] {
            return image
        }

        let image = labelImage(for: medication)
        if labelImageCache.count > 24 {
            labelImageCache.removeAll(keepingCapacity: true)
        }
        labelImageCache[key] = image
        return image
    }

    private static func labelImage(for medication: Medication) -> UIImage {
        let size = CGSize(width: 520, height: 620)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            let paperRect = CGRect(origin: .zero, size: size)
            let ink = UIColor(red: 0.01, green: 0.012, blue: 0.014, alpha: 1)
            let softInk = UIColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1)
            let rule = UIColor(red: 0.34, green: 0.33, blue: 0.29, alpha: 0.42)

            cgContext.setShouldAntialias(true)
            cgContext.setAllowsAntialiasing(true)
            cgContext.interpolationQuality = .high

            let paper = UIColor(red: 0.998, green: 0.992, blue: 0.972, alpha: 1)
            paper.setFill()
            UIRectFill(paperRect)
            UIBezierPath(roundedRect: paperRect, cornerRadius: 18).fill()

            for index in 0..<560 {
                let x = CGFloat((index * 37) % Int(size.width))
                let y = CGFloat((index * 83) % Int(size.height))
                let alpha = CGFloat(0.004 + Double(index % 5) * 0.002)
                UIColor(red: 0.30, green: 0.27, blue: 0.20, alpha: alpha).setFill()
                UIRectFill(CGRect(x: x, y: y, width: 1, height: index.isMultiple(of: 7) ? 2 : 1))
            }

            UIColor(red: 0.86, green: 0.84, blue: 0.78, alpha: 0.12).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 16, height: size.height))
            UIRectFill(CGRect(x: size.width - 16, y: 0, width: 16, height: size.height))

            let leftParagraph = NSMutableParagraphStyle()
            leftParagraph.alignment = .left
            leftParagraph.lineBreakMode = .byTruncatingTail

            let rightParagraph = NSMutableParagraphStyle()
            rightParagraph.alignment = .right

            let centerParagraph = NSMutableParagraphStyle()
            centerParagraph.alignment = .center
            centerParagraph.lineBreakMode = .byTruncatingTail

            ("Rx" as NSString).draw(
                in: CGRect(x: 38, y: 34, width: 116, height: 80),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 58, weight: .bold),
                    .foregroundColor: ink,
                    .paragraphStyle: leftParagraph
                ]
            )

            ("PRESCRIPTION" as NSString).draw(
                in: CGRect(x: 172, y: 42, width: 304, height: 32),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 25, weight: .semibold),
                    .foregroundColor: ink,
                    .paragraphStyle: rightParagraph
                ]
            )

            ("TAKE AS DIRECTED" as NSString).draw(
                in: CGRect(x: 172, y: 78, width: 304, height: 28),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 21, weight: .medium),
                    .foregroundColor: softInk,
                    .paragraphStyle: rightParagraph
                ]
            )

            cgContext.setStrokeColor(rule.cgColor)
            cgContext.setLineWidth(3)
            cgContext.move(to: CGPoint(x: 36, y: 128))
            cgContext.addLine(to: CGPoint(x: size.width - 36, y: 128))
            cgContext.strokePath()

            ("MEDICATION" as NSString).draw(
                in: CGRect(x: 40, y: 166, width: size.width - 80, height: 24),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
                    .foregroundColor: softInk,
                    .paragraphStyle: centerParagraph
                ]
            )

            (medication.name as NSString).draw(
                in: CGRect(x: 36, y: 198, width: size.width - 72, height: 78),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
                    .foregroundColor: ink,
                    .paragraphStyle: centerParagraph
                ]
            )

            let quantity = "QTY \(medication.tabletsRemaining)"
            let dose = "DOSE \(medication.tabletsPerDose)"
            let shape = medication.medicationShape.title.uppercased()

            cgContext.setStrokeColor(rule.cgColor)
            cgContext.setLineWidth(2)
            cgContext.stroke(CGRect(x: 38, y: 306, width: size.width - 76, height: 72))
            cgContext.move(to: CGPoint(x: size.width / 2, y: 306))
            cgContext.addLine(to: CGPoint(x: size.width / 2, y: 378))
            cgContext.strokePath()

            (quantity as NSString).draw(
                in: CGRect(x: 58, y: 322, width: 190, height: 34),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 26, weight: .semibold),
                    .foregroundColor: ink,
                    .paragraphStyle: leftParagraph
                ]
            )

            (dose as NSString).draw(
                in: CGRect(x: 284, y: 322, width: 180, height: 34),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 26, weight: .semibold),
                    .foregroundColor: ink,
                    .paragraphStyle: leftParagraph
                ]
            )

            (shape as NSString).draw(
                in: CGRect(x: 40, y: 398, width: size.width - 80, height: 30),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                    .foregroundColor: softInk,
                    .paragraphStyle: centerParagraph
                ]
            )

            cgContext.setStrokeColor(rule.cgColor)
            cgContext.setLineWidth(2)
            cgContext.move(to: CGPoint(x: 42, y: 452))
            cgContext.addLine(to: CGPoint(x: size.width - 42, y: 452))
            cgContext.strokePath()

            var barcodeX: CGFloat = 60
            let barcodeTop: CGFloat = 480
            let barcodePattern = [2, 1, 4, 1, 1, 3, 2, 2, 5, 1, 1, 2, 3, 1, 4, 2, 1, 1, 5, 1, 2, 3, 1, 4, 1, 2, 2, 1, 3]
            ink.setFill()
            for (index, width) in barcodePattern.enumerated() {
                let barWidth = CGFloat(width)
                let barHeight: CGFloat = index.isMultiple(of: 3) ? 64 : 52
                UIRectFill(CGRect(x: barcodeX, y: barcodeTop + 64 - barHeight, width: barWidth, height: barHeight))
                barcodeX += barWidth + CGFloat(index.isMultiple(of: 2) ? 5 : 3)
            }

            ("NDC 0000-0000-00  |  RX \(abs(medication.id.hashValue % 90000) + 10000)" as NSString).draw(
                in: CGRect(x: 44, y: 552, width: size.width - 88, height: 30),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular),
                    .foregroundColor: softInk,
                    .paragraphStyle: centerParagraph
                ]
            )

            cgContext.setStrokeColor(UIColor(red: 0.68, green: 0.66, blue: 0.58, alpha: 0.22).cgColor)
            cgContext.setLineWidth(3)
            cgContext.stroke(CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24).insetBy(dx: 2, dy: 2))
        }
    }

}
