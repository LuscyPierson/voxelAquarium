import Foundation

// Data shared by the app and the widget through the App Group container.

let appGroup = "4BD53JYD4T.com.piersonluscy.voxelaquarium"

/// Settings both sides read: the app writes "no sharks", the widget counts taps ("nudges").
enum Shared {
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
    static let noSharks = "noSharks"
    static let nudges = "nudges"
    /// Which world the app shows (ocean, swamp, rainforest); the widget follows along.
    static let biome = "biome"
}

/// What the widget needs to know about each creature it might show.
struct SpeciesInfo: Codable {
    let key: String
    let name: String
    let accent: String
    let depthMin: Double
    let depthMax: Double
    let speed: Double
    /// How often it turns up, relative to the others (0 = never in the widget).
    var weight: Double?
    var shark: Bool?
    var groupMin: Int?
    var groupMax: Int?
    /// Half the height of its sprite, in ocean units.
    var halfHeight: Double?
    /// Drifts (jellies) rather than swimming side-on.
    var drift: Bool?
}

struct Catalog: Codable {
    var species: [SpeciesInfo]
}
