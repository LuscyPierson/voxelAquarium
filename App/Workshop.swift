import Foundation
import SceneKit

/// One thing made in the Unity Voxel Workshop (DevTools/VoxelWorkshop): a creature that visits, or a decoration
/// that sits on the floor. Saved as JSON into the Workshop folder of the shared container.
struct WorkshopItem: Codable {
    var name: String
    /// "creature" or "decor".
    var kind: String
    /// Which worlds it shows up in: "ocean", "swamp", "rainforest".
    var worlds: [String]
    var voxelSize: Float
    var body: [VoxelEntry]
    var tail: [VoxelEntry]?

    // Creatures
    /// "water" swims, "air" flies (in the swamp and rainforest), "ground" walks the floor.
    var habitat: String?
    var speed: Float?
    var depthMin: Float?
    var depthMax: Float?
    var schooling: Bool?
    var groupMin: Int?
    var groupMax: Int?
    var weight: Double?

    // Decorations
    var x: Float?
    var z: Float?
    var turn: Float?

    func shows(in biome: Biome) -> Bool { worlds.isEmpty || worlds.contains(biome.rawValue) }
}

/// Loads Workshop items and feeds them to the roster and the scenery. A developer path: the folder is empty
/// unless the Unity Workshop has saved into it.
enum Workshop {
    static let dir = Store.dir.appending(path: "Workshop")

    nonisolated(unsafe) private(set) static var items: [(file: String, item: WorkshopItem)] = []
    nonisolated(unsafe) private(set) static var signature = ""

    /// A string that changes whenever any Workshop file is added, removed or saved.
    static func currentSignature() -> String {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
            return "\(url.lastPathComponent)@\(date)"
        }.sorted().joined(separator: "|")
    }

    static func load() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        signature = currentSignature()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        items = files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let data = try? Data(contentsOf: url), let item = try? JSONDecoder().decode(WorkshopItem.self, from: data),
                  !item.body.isEmpty else { return nil }
            return (url.deletingPathExtension().lastPathComponent, item)
        }
    }

    /// Workshop creatures for one world, ready to join its roster.
    static func entries(for biome: Biome) -> [RosterEntry] {
        items.filter { $0.item.kind == "creature" && $0.item.shows(in: biome) }.map { file, item in
            let lo = max(1, item.groupMin ?? 1)
            return RosterEntry(key: key(file), name: item.name, weight: item.weight ?? 2, group: lo...max(lo, item.groupMax ?? lo),
                               shark: false, build: { species(item, file: file) }, fun: nil)
        }
    }

    /// Every world's Workshop creatures, for looking one up by key.
    static var everyEntry: [RosterEntry] {
        items.filter { $0.item.kind == "creature" }.map { file, item in
            RosterEntry(key: key(file), name: item.name, weight: 0, group: 1...1, shark: false,
                        build: { species(item, file: file) }, fun: nil)
        }
    }

    static func key(_ file: String) -> String { "workshop-" + file.lowercased() }

    private static func species(_ item: WorkshopItem, file: String) -> Species {
        let s = Species(key: key(file), name: item.name, blurb: "Made in the Workshop.", accent: 0)
        s.voxelSize = item.voxelSize
        s.speed = item.speed ?? 1
        s.depth = (item.depthMin ?? 0.2, item.depthMax ?? 0.8)
        s.schooling = item.schooling ?? false
        for e in item.body { s.body.set(e.x, e.y, e.z, e.color) }
        for e in item.tail ?? [] { s.tail.set(e.x, e.y, e.z, e.color) }
        s.accent = s.body.dominantColor
        switch item.habitat ?? "water" {
        case "ground": s.motion = .walk
        case "air": s.flies = Biome.current == .swamp
        default: s.aquatic = Biome.current == .rainforest
        }
        return s
    }

    /// Sets this world's Workshop decorations on the floor.
    @MainActor
    static func decorate(_ root: SCNNode, biome: Biome) {
        for (_, item) in items where item.kind == "decor" && item.shows(in: biome) {
            let model = VoxelModel(entries: item.body)
            guard let b = model.bounds else { continue }
            // Centred over its spot, with its lowest blocks resting on the floor.
            let pivot = SIMD3(Float(b.min.x + b.max.x) / 2, Float(b.min.y) - 0.5, Float(b.min.z + b.max.z) / 2)
            let node = SCNNode(geometry: model.geometry(size: item.voxelSize, pivot: pivot))
            node.name = item.name
            node.categoryBitMask = TankController.Mask.decor
            let x = item.x ?? 0, z = item.z ?? 1
            node.simdPosition = SIMD3(x, TankDecor.floor(x, z), z)
            node.simdEulerAngles = SIMD3(0, (item.turn ?? 0) * .pi / 180, 0)
            root.addChildNode(node)
        }
    }
}
