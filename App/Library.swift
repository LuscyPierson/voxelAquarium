import AppKit
import Foundation

/// Reads and writes files in the App Group container the widget also reads.
enum Store {
    static let dir: URL = {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "VoxelAquarium")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var now: Double { Date().timeIntervalSince1970 }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appending(path: name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: dir.appending(path: name), options: .atomic)
    }

    static func writePNG(_ image: NSImage, _ name: String) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        let url = dir.appending(path: name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url, options: .atomic)
    }
}

/// Every species the tank knows: the built-ins plus designs from the editor.
@MainActor
final class Library: ObservableObject {
    let builtins = Roster.everyEntry.compactMap { Roster.species($0.key) }
    @Published private(set) var designs: [FishDesign]
    /// Bumped whenever a design changes, so thumbnails know to re-render.
    @Published private(set) var version = 0
    private var customs: [UUID: Species] = [:]

    init() {
        designs = Store.read([FishDesign].self, "designs.json") ?? []
        for d in designs { customs[d.id] = Species(design: d) }
    }

    var customSpecies: [Species] { designs.compactMap { customs[$0.id] } }
    var all: [Species] { builtins + customSpecies }

    func species(_ key: String) -> Species? { all.first { $0.key == key } }

    func save(_ design: FishDesign) {
        if let i = designs.firstIndex(where: { $0.id == design.id }) { designs[i] = design } else { designs.append(design) }
        customs[design.id] = Species(design: design)
        Store.write(designs, "designs.json")
        version += 1
    }

    func delete(_ id: UUID) {
        designs.removeAll { $0.id == id }
        customs[id] = nil
        Store.write(designs, "designs.json")
        version += 1
    }
}
