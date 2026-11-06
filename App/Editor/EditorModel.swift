import AppKit
import SceneKit
import SwiftUI

/// The Fish Editor: one design at a time, sculpted voxel by voxel on a turntable.
/// Body voxels sit at their own grid coordinates; the tail hangs one step behind the body's back end,
/// so world coordinates in the editor scene are body-grid coordinates for both parts.
@MainActor
final class EditorModel: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case add = "Add", erase = "Erase", paint = "Paint", pick = "Pick"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .add: "plus.square"
            case .erase: "eraser"
            case .paint: "paintbrush.pointed"
            case .pick: "eyedropper"
            }
        }
        var key: KeyEquivalent {
            switch self {
            case .add: "1"
            case .erase: "2"
            case .paint: "3"
            case .pick: "4"
            }
        }
    }

    enum Part: String, CaseIterable, Identifiable {
        case body = "Body", tail = "Tail"
        var id: String { rawValue }
    }

    static let palette: [UInt32] = [
        0xFF7A1A, 0xF8F8F2, 0x15151B, 0xFFD23A, 0x2457E8, 0x5C93FF, 0x2FE6FF, 0x5FD35A,
        0x2E8B57, 0xE5303A, 0xC4123F, 0x7B2AB8, 0xFF8FB8, 0xC9A15E, 0x8A4B2C, 0xA9B1BD,
    ]
    private static let partMask = 2

    let library: Library
    unowned let aquarium: AquariumModel

    @Published private(set) var design: FishDesign
    @Published var tool: Tool = .add
    @Published var part: Part = .body
    @Published var rgb: UInt32 = 0xFF7A1A
    @Published var glow = false
    @Published var mirror = true
    @Published var wagPreview = false
    @Published private(set) var dirty = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// A still of the 3D view, swapped in while capturing screenshots.
    @Published var frozen: NSImage?

    weak var view: SCNView?
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let bodyNode = SCNNode()
    private let tailNode = SCNNode()
    private let gridNode = SCNNode()
    private let ghost = SCNNode()
    private var body = VoxelModel()
    private var tail = VoxelModel()
    private var undoStack: [FishDesign] = []
    private var redoStack: [FishDesign] = []
    private var time: Double = 0

    init(library: Library, aquarium: AquariumModel) {
        self.library = library
        self.aquarium = aquarium
        design = library.designs.first ?? Self.starter()
        buildScene()
        load(design)
        frameCamera()
    }

    var isSaved: Bool { library.designs.contains { $0.id == design.id } }
    var voxelCount: Int { body.count + tail.count }
    var species: Species? { library.species("custom-\(design.id.uuidString.lowercased())") }

    // MARK: - Opening designs

    func open(_ d: FishDesign) {
        guard d.id != design.id || !isSaved else { return }
        autosave()
        undoStack = []
        redoStack = []
        load(d)
        dirty = !library.designs.contains { $0.id == d.id }
        frameCamera()
    }

    func newBlank() { open(Self.starter()) }

    func newFrom(_ s: Species) { open(s.design(named: "\(s.name) Remix").withNewID()) }

    private func autosave() {
        if dirty, voxelCount > 0, isSaved || !undoStack.isEmpty { save() }
    }

    private func load(_ d: FishDesign) {
        design = d
        body = VoxelModel(entries: d.body)
        tail = VoxelModel(entries: d.tail)
        canUndo = false
        canRedo = false
        rebuild()
    }

    // MARK: - Settings (bindings mark the design changed)

    func binding<T>(_ key: WritableKeyPath<FishDesign, T>) -> Binding<T> {
        Binding(get: { self.design[keyPath: key] }, set: { self.design[keyPath: key] = $0; self.dirty = true })
    }

    var color: Binding<Color> {
        Binding(get: { Color(nsColor: NSColor(rgb: self.rgb)) }, set: { self.rgb = NSColor($0).rgb })
    }

    // MARK: - Saving

    func save() {
        guard voxelCount > 0 else { return }
        syncDesign()
        library.save(design)
        dirty = false
        if let s = species { aquarium.designSaved(s) }
    }

    func addToTank() {
        save()
        if let s = species { aquarium.spawn(s) }
    }

    func delete() {
        let key = "custom-\(design.id.uuidString.lowercased())"
        let wasSaved = isSaved
        library.delete(design.id)
        if wasSaved { aquarium.designDeleted(key: key) }
        dirty = false
        load(library.designs.first ?? Self.starter())
        frameCamera()
    }

    private func syncDesign() {
        design.body = body.entries
        design.tail = tail.entries
    }

    // MARK: - Undo

    private func checkpoint() {
        syncDesign()
        undoStack.append(design)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack = []
        canUndo = true
        canRedo = false
    }

    func undo() {
        guard let d = undoStack.popLast() else { return }
        syncDesign()
        redoStack.append(design)
        restore(d)
    }

    func redo() {
        guard let d = redoStack.popLast() else { return }
        syncDesign()
        undoStack.append(design)
        restore(d)
    }

    private func restore(_ d: FishDesign) {
        design = d
        body = VoxelModel(entries: d.body)
        tail = VoxelModel(entries: d.tail)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        dirty = true
        rebuild()
    }

    // MARK: - Scene

    private func buildScene() {
        scene.background.contents = NSColor(rgb: 0x0B1A26)
        Snapshots.addLights(to: scene)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light!.type = .directional
        rim.light!.intensity = 350
        rim.light!.color = NSColor(rgb: 0x9FD8FF)
        rim.simdPosition = SIMD3(-6, 4, -10)
        rim.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(rim)

        cameraNode.camera = SCNCamera()
        cameraNode.camera!.fieldOfView = 40
        cameraNode.camera!.zNear = 0.1
        cameraNode.camera!.zFar = 400
        scene.rootNode.addChildNode(cameraNode)

        bodyNode.categoryBitMask = Self.partMask
        tailNode.categoryBitMask = Self.partMask
        bodyNode.addChildNode(tailNode)
        scene.rootNode.addChildNode(bodyNode)

        gridNode.geometry = Self.grid(half: 14)
        scene.rootNode.addChildNode(gridNode)

        let box = SCNBox(width: 1.04, height: 1.04, length: 1.04, chamferRadius: 0.16)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.transparency = 0.45
        m.writesToDepthBuffer = false
        box.materials = [m]
        ghost.geometry = box
        ghost.isHidden = true
        ghost.categoryBitMask = 0
        ghost.renderingOrder = 10
        scene.rootNode.addChildNode(ghost)
    }

    /// Body z where the tail is attached: one step behind the back of the body.
    private var tailOffset: Int { (body.bounds?.min.z ?? 0) - 1 }

    private func rebuild() {
        bodyNode.geometry = body.isEmpty ? nil : body.geometry(size: 1, pivot: .zero)
        tailNode.geometry = tail.isEmpty ? nil : tail.geometry(size: 1, pivot: SIMD3(0, 0, 0.5))
        tailNode.simdPosition = SIMD3(0, 0, Float(tailOffset) + 0.5)
        let floorY = Float(min(body.bounds?.min.y ?? 0, tail.bounds?.min.y ?? 0)) - 0.52
        gridNode.simdPosition = SIMD3(0, floorY - 0.5, 0)
        objectWillChange.send()
    }

    func frameCamera() {
        var lo = SIMD3<Float>(-2, -2, -4), hi = SIMD3<Float>(2, 2, 4)
        if let b = body.bounds {
            lo = b.min.float - 0.5
            hi = b.max.float + 0.5
        }
        if let t = tail.bounds {
            let o = SIMD3<Float>(0, 0, Float(tailOffset))
            lo = simd_min(lo, t.min.float + o - 0.5)
            hi = simd_max(hi, t.max.float + o + 0.5)
        }
        let center = (lo + hi) / 2
        let radius = max(3, simd_length(hi - lo) / 2)
        let dir = simd_normalize(SIMD3<Float>(1.0, 0.45, 0.55))
        cameraNode.simdPosition = center + dir * radius * 2.9
        cameraNode.simdLook(at: center, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        view?.defaultCameraController.target = SCNVector3(center)
    }

    func frame(dt: Double) {
        time += dt
        let angle = wagPreview ? sin(Float(time) * design.wag) * design.wagAngle * .pi / 180 : 0
        tailNode.simdEulerAngles = SIMD3(0, angle, 0)
        if wagPreview {
            bodyNode.simdEulerAngles = SIMD3(0, -angle * 0.25, 0)
        } else if bodyNode.simdEulerAngles != .zero {
            bodyNode.simdEulerAngles = .zero
        }
    }

    // MARK: - Editing

    /// Where a click lands: the cell that was hit, the empty cell in front of it, and which part it belongs to.
    private struct Target {
        var cell: V3
        var front: V3
        var part: Part
    }

    private func target(at point: CGPoint) -> Target? {
        guard let view else { return nil }
        let hits = view.hitTest(point, options: [
            .categoryBitMask: Self.partMask,
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
        ])
        guard let hit = hits.first else { return nil }
        let isTail = hit.node === tailNode
        // Work in the node's own grid so a wagging tail still edits cleanly.
        let pivot = SIMD3<Float>(0, 0, isTail ? 0.5 : 0)
        let local = SIMD3<Float>(hit.localCoordinates) + pivot
        let normal = SIMD3<Float>(hit.localNormal)
        let inside = (local - normal * 0.05).rounded(.toNearestOrAwayFromZero)
        let cell = V3(Int(inside.x), Int(inside.y), Int(inside.z))
        let d = local - inside
        let axis = abs(d.x) >= abs(d.y) && abs(d.x) >= abs(d.z) ? 0 : abs(d.y) >= abs(d.z) ? 1 : 2
        var front = cell
        front[axis] += d[axis] >= 0 ? 1 : -1
        let shift = isTail ? tailOffset : 0
        return Target(cell: V3(cell.x, cell.y, cell.z + shift), front: V3(front.x, front.y, front.z + shift),
                      part: isTail ? .tail : .body)
    }

    private func model(_ part: Part) -> VoxelModel { part == .body ? body : tail }

    /// Body-grid cell → the part's own grid.
    private func local(_ cell: V3, _ part: Part) -> V3 { part == .body ? cell : V3(cell.x, cell.y, cell.z - tailOffset) }

    private func mirrored(_ cell: V3) -> [V3] { mirror && cell.x != 0 ? [cell, V3(-cell.x, cell.y, cell.z)] : [cell] }

    private var current: VoxelColor { VoxelColor(rgb: rgb, glow: glow ? 160 : 0) }

    func click(at point: CGPoint) {
        guard let t = target(at: point) else {
            if voxelCount == 0, tool == .add {
                checkpoint()
                model(part).set(0, 0, 0, current)
                changed()
            }
            return
        }
        switch tool {
        case .add:
            // Work out the tail's grid before the body changes shape under it.
            let cells = mirrored(t.front).map { local($0, part) }
            checkpoint()
            for c in cells where model(part)[c] == nil { model(part)[c] = current }
        case .erase:
            let cells = mirrored(t.cell).map { local($0, t.part) }
            checkpoint()
            for c in cells { model(t.part)[c] = nil }
        case .paint:
            let cells = mirrored(t.cell).map { local($0, t.part) }
            guard cells.contains(where: { model(t.part)[$0] != nil && model(t.part)[$0] != current }) else { return }
            checkpoint()
            for c in cells where model(t.part)[c] != nil { model(t.part)[c] = current }
        case .pick:
            if let c = model(t.part)[local(t.cell, t.part)] {
                rgb = c.rgb
                glow = c.glow >= 100
                tool = .paint
            }
            return
        }
        changed()
        hover(at: point)
    }

    private func changed() {
        dirty = true
        syncDesign()
        rebuild()
    }

    func hover(at point: CGPoint?) {
        guard let point, let t = target(at: point) else { ghost.isHidden = true; return }
        let cell = tool == .add ? t.front : t.cell
        ghost.isHidden = false
        ghost.simdPosition = cell.float
        let tint: NSColor = switch tool {
        case .add: NSColor(rgb: rgb)
        case .erase: NSColor(rgb: 0xFF4A4A)
        case .paint: NSColor(rgb: rgb)
        case .pick: NSColor.white
        }
        ghost.geometry?.firstMaterial?.diffuse.contents = tint
        ghost.scale = tool == .add ? SCNVector3(0.92, 0.92, 0.92) : SCNVector3(1.06, 1.06, 1.06)
    }

    // MARK: - Starting shapes

    /// A small, plain fish to start sculpting from.
    static func starter() -> FishDesign {
        let m = VoxelModel(), t = VoxelModel()
        let orange = C(0xFF9A1C), belly = C(0xFFD27A), fin = C(0xFFB04A)
        for z in -5...5 {
            let u = Float(z) / 5.6
            let h = 3.2 * (1 - u * u).squareRoot(), w = 1.9 * (1 - u * u).squareRoot()
            for y in -3...3 where Float(abs(y)) <= h - 0.3 {
                for x in -2...2 where Float(abs(x)) <= w - 0.3 {
                    m.set(x, y, z, y < -1 ? belly : orange)
                }
            }
        }
        for s in [-1, 1] {
            m.set(s * 2, 1, 3, C(0x0A0A0E))
            m.set(s * 2, 2, 3, C(0xFFFFFF, 255))
        }
        for z in -2...1 { m.set(0, 3 + (z > -2 && z < 1 ? 1 : 0), z, fin) }
        for i in 0..<4 {
            for y in -(i + 1)...(i + 1) { t.set(0, y, -i, fin) }
        }
        var d = FishDesign()
        d.body = m.entries
        d.tail = t.entries
        return d
    }

    /// Faint floor grid lines, in the xz plane.
    private static func grid(half: Int) -> SCNGeometry {
        var points: [SCNVector3] = []
        for i in -half...half {
            let f = CGFloat(i), h = CGFloat(half)
            points += [SCNVector3(f - 0.5, 0, -h - 0.5), SCNVector3(f - 0.5, 0, h - 0.5)]
            points += [SCNVector3(-h - 0.5, 0, f - 0.5), SCNVector3(h - 0.5, 0, f - 0.5)]
        }
        let source = SCNGeometrySource(vertices: points)
        let indices = (0..<Int32(points.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let g = SCNGeometry(sources: [source], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(rgb: 0x2E5870, alpha: 0.6)
        g.materials = [m]
        return g
    }
}

extension FishDesign {
    func withNewID() -> FishDesign {
        var d = self
        d.id = UUID()
        return d
    }
}
