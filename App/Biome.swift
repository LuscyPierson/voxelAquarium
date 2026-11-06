import AppKit
import simd

/// The worlds the window can show: the open ocean, a Louisiana swamp, or a rainforest.
/// Each has its own scenery, creatures, light and colours; the way things move and peek is shared.
enum Biome: String, CaseIterable, Identifiable {
    case ocean, swamp, rainforest

    /// The world being built and shown right now.
    nonisolated(unsafe) static var current: Biome = .ocean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: "Ocean"
        case .swamp: "Louisiana Swamp"
        case .rainforest: "Rainforest"
        }
    }

    /// Icon for the world buttons.
    var symbol: String {
        switch self {
        case .ocean: "water.waves"
        case .swamp: "leaf.fill"
        case .rainforest: "tree.fill"
        }
    }

    /// What the "no sharks" setting keeps away here.
    var predators: String {
        switch self {
        case .ocean: "sharks"
        case .swamp: "alligators"
        case .rainforest: "jaguars"
        }
    }

    var underwater: Bool { self != .rainforest }

    /// Scene background and haze.
    var background: UInt32 {
        switch self {
        case .ocean: 0x62C2DE
        case .swamp: 0xA2BA88
        case .rainforest: 0xA0CFA2
        }
    }

    var fog: (color: UInt32, start: CGFloat, end: CGFloat) {
        switch self {
        case .ocean: (0x80D2E6, 15, 54)
        case .swamp: (0x9CB282, 15, 56)
        case .rainforest: (0xAAD6AC, 16, 54)
        }
    }

    var ambient: (color: NSColor, intensity: CGFloat) {
        switch self {
        case .ocean: (NSColor(srgbRed: 0.62, green: 0.76, blue: 0.88, alpha: 1), 660)
        case .swamp: (NSColor(srgbRed: 0.7, green: 0.76, blue: 0.56, alpha: 1), 690)
        case .rainforest: (NSColor(srgbRed: 0.78, green: 0.86, blue: 0.7, alpha: 1), 710)
        }
    }

    /// The giant blocks of the far wallpaper: colour at the bottom, middle and top.
    var farColors: [SIMD3<Float>] {
        switch self {
        case .ocean: [SIMD3(0.14, 0.44, 0.58), SIMD3(0.3, 0.66, 0.8), SIMD3(0.58, 0.88, 0.94)]
        case .swamp: [SIMD3(0.2, 0.26, 0.15), SIMD3(0.42, 0.5, 0.32), SIMD3(0.76, 0.8, 0.66)]
        case .rainforest: [SIMD3(0.14, 0.28, 0.14), SIMD3(0.3, 0.5, 0.26), SIMD3(0.74, 0.86, 0.72)]
        }
    }

    /// Floor blocks: the main colours, and the odd pebble, leaf or shell.
    var floorColors: (main: [UInt32], bits: [UInt32]) {
        switch self {
        case .ocean: ([0xD6BA7E, 0xD0B274, 0xDCC28A], [0x8A7F70, 0xB06F4C])
        case .swamp: ([0x5A4A32, 0x544530, 0x5F4E36], [0x6E8A3A])
        case .rainforest: ([0x5E4228, 0x64472A, 0x5A4026], [0xC2702A, 0x8AA040])
        }
    }

    /// The little things that rise when you tap: bubbles under water, golden motes in the forest.
    var bubble: VoxelColor {
        switch self {
        case .ocean: C(0xCFF6FF, 170)
        case .swamp: C(0xD8E2B0, 150)
        case .rainforest: C(0xFFE98A, 220)
        }
    }
}
