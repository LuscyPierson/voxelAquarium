import SceneKit
import simd

/// Off-screen renders: fish portraits for the picker and the widget, and the empty-tank backdrop.
@MainActor
enum Snapshots {
    private static let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    /// One creature side-on (facing right), seen a little from above and in front, on a transparent background.
    /// With a fixed half height every species is drawn at the same scale; otherwise it's zoomed to fill the image.
    static func fish(_ s: Species, size: CGSize, fixedHalfHeight: Float? = nil) -> NSImage {
        sprite(s, size: size, fixedHalfHeight: fixedHalfHeight).image
    }

    /// Like `fish`, also returning the half height (in world units) the image covers.
    static func sprite(_ s: Species, size: CGSize, fixedHalfHeight: Float? = nil) -> (image: NSImage, halfHeight: Float) {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        addLights(to: scene)

        let root = SCNNode()
        let side = s.motion == .swim || s.motion == .walk
        root.simdOrientation = simd_quatf(angle: (side ? 75 : 20) * .pi / 180, axis: SIMD3(0, 1, 0))
        let rig = CreatureRig(s)
        rig.pose(time: 0.6, wag: 0.5)
        rig.model.simdEulerAngles.z = s.bank
        root.addChildNode(rig.model)
        scene.rootNode.addChildNode(root)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true
        cam.camera!.zNear = 0.1
        cam.camera!.zFar = 100
        cam.simdEulerAngles = SIMD3(-16 * .pi / 180, 0, 0)
        scene.rootNode.addChildNode(cam)

        // Extents of the creature as the camera sees it.
        let right = cam.simdWorldRight, up = cam.simdWorldUp, forward = cam.simdWorldFront
        var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
        rig.model.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (a, b) = node.boundingBox
            for corner in 0..<8 {
                let local = SCNVector3(corner & 1 == 0 ? a.x : b.x, corner & 2 == 0 ? a.y : b.y, corner & 4 == 0 ? a.z : b.z)
                let w = SIMD3<Float>(node.convertPosition(local, to: nil))
                let p = SIMD2(simd_dot(w, right), simd_dot(w, up))
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
            }
        }
        if !lo.x.isFinite { lo = .zero; hi = .zero }
        let aspect = Float(size.width / size.height)
        let mid = (lo + hi) / 2
        let half = (hi - lo) / 2
        let fit = max(half.y, half.x / aspect, 0.05) * 1.12
        let scale = fixedHalfHeight.map { max($0, fit) } ?? fit
        cam.camera!.orthographicScale = Double(scale)
        cam.simdPosition = right * mid.x + up * mid.y - forward * 20

        renderer.scene = scene
        renderer.pointOfView = cam
        return (renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X), scale)
    }

    /// The tank without fish, framed like the main view at the given shape.
    static func backdrop(_ tank: TankController, size: CGSize) -> NSImage {
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.fieldOfView = 36
        cam.camera!.zNear = 0.1
        cam.camera!.zFar = 120
        cam.camera!.categoryBitMask = TankController.Mask.scenery
        cam.camera!.wantsDepthOfField = true
        cam.camera!.fStop = 0.8
        cam.camera!.focalBlurSampleCount = 16
        tank.scene.rootNode.addChildNode(cam)
        TankController.fit(cam, aspect: Float(size.width / size.height), parallax: .zero)
        renderer.scene = tank.scene
        renderer.pointOfView = cam
        let image = renderer.snapshot(atTime: Double(tank.time), with: size, antialiasingMode: .multisampling4X)
        cam.removeFromParentNode()
        return image
    }

    static func addLights(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 700
        ambient.light!.color = NSColor(white: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .directional
        sun.light!.intensity = 850
        sun.simdPosition = SIMD3(4, 10, 8)
        sun.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sun)
    }
}
