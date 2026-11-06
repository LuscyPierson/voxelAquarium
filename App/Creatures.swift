import SceneKit
import simd

/// Everything that can turn up in the ocean, how often, and in what sized groups.
/// Most kinds have a rare "fun" look (a clownfish dressed as a clown, a hammerhead with an actual hammer…).
struct RosterEntry {
    let key: String
    let name: String
    /// How likely this kind is to be the next visitor, relative to the others.
    let weight: Double
    let group: ClosedRange<Int>
    let shark: Bool
    let build: () -> Species
    let fun: (() -> Species)?
    /// Pops up over the wall at the back now and then (the ocean picks small swimmers on its own).
    var peeks = false

    var funKey: String { key + "-fun" }
}

@MainActor
enum Roster {
    /// Chance that a visitor with a fun look shows up wearing it.
    static let funChance = 0.05

    /// What lives in the world on screen.
    static var entries: [RosterEntry] { entries(for: Biome.current) }

    static func entries(for biome: Biome) -> [RosterEntry] {
        let own: [RosterEntry] = switch biome {
        case .ocean: oceanEntries
        case .swamp: swampEntries
        case .rainforest: rainforestEntries
        }
        return own + Workshop.entries(for: biome)
    }

    /// Every world's creatures, for looking one up by key.
    static var everyEntry: [RosterEntry] { oceanEntries + swampEntries + rainforestEntries + Workshop.everyEntry }

    /// Drops built Workshop creatures, so the next visit uses what was just saved.
    static func forgetWorkshop() { cache = cache.filter { !$0.key.hasPrefix("workshop-") } }

    static var swampEntries: [RosterEntry] { Swamp.entries }
    static var rainforestEntries: [RosterEntry] { Rainforest.entries }

    static let oceanEntries: [RosterEntry] = [
        RosterEntry(key: "sardine", name: "Sardines", weight: 9, group: 7...12, shark: false, build: Builtins.sardine, fun: nil),
        RosterEntry(key: "yellowtang", name: "Yellow Tang", weight: 8, group: 2...4, shark: false, build: Builtins.yellowTang, fun: nil),
        RosterEntry(key: "clownfish", name: "Clownfish", weight: 8, group: 1...3, shark: false, build: { ocean(Builtins.clownfish()) },
                    fun: Builtins.clownfishClown),
        RosterEntry(key: "bluetang", name: "Blue Tang", weight: 7, group: 1...3, shark: false, build: { ocean(Builtins.blueTang()) }, fun: nil),
        RosterEntry(key: "angelfish", name: "Angelfish", weight: 5, group: 1...2, shark: false, build: { ocean(Builtins.angelfish()) }, fun: nil),
        RosterEntry(key: "pufferfish", name: "Pufferfish", weight: 4, group: 1...1, shark: false, build: { ocean(Builtins.pufferfish()) }, fun: nil),
        RosterEntry(key: "jellyfish", name: "Jellyfish", weight: 4, group: 1...3, shark: false, build: { Builtins.jellyfish(jello: false) },
                    fun: { Builtins.jellyfish(jello: true) }),
        RosterEntry(key: "boxjelly", name: "Box Jellyfish", weight: 2, group: 1...2, shark: false, build: { Builtins.boxJelly(box: false) },
                    fun: { Builtins.boxJelly(box: true) }),
        RosterEntry(key: "catfish", name: "Catfish", weight: 3, group: 1...2, shark: false, build: Builtins.catfish, fun: Builtins.cat),
        RosterEntry(key: "mackerel", name: "Mackerel", weight: 5, group: 5...9, shark: false, build: Builtins.mackerel, fun: nil),
        RosterEntry(key: "butterflyfish", name: "Butterflyfish", weight: 5, group: 2...3, shark: false, build: Builtins.butterflyfish, fun: nil),
        RosterEntry(key: "moorishidol", name: "Moorish Idol", weight: 4, group: 1...3, shark: false, build: Builtins.moorishIdol, fun: nil),
        RosterEntry(key: "tuna", name: "Tuna", weight: 3, group: 2...4, shark: false, build: Builtins.tuna, fun: nil),
        RosterEntry(key: "salmon", name: "Salmon", weight: 3, group: 2...4, shark: false, build: Builtins.salmon, fun: nil),
        RosterEntry(key: "parrotfish", name: "Parrotfish", weight: 3, group: 1...2, shark: false, build: Builtins.parrotfish, fun: nil),
        RosterEntry(key: "mandarinfish", name: "Mandarinfish", weight: 2, group: 1...2, shark: false, build: Builtins.mandarinfish, fun: nil),
        RosterEntry(key: "lionfish", name: "Lionfish", weight: 2, group: 1...1, shark: false, build: Builtins.lionfish, fun: nil),
        RosterEntry(key: "seahorse", name: "Seahorse", weight: 2, group: 1...2, shark: false, build: Builtins.seahorse, fun: nil),
        RosterEntry(key: "stingray", name: "Stingray", weight: 2.2, group: 1...2, shark: false, build: Builtins.stingray, fun: nil),
        RosterEntry(key: "barracuda", name: "Barracuda", weight: 1.5, group: 1...2, shark: false, build: Builtins.barracuda, fun: nil),
        RosterEntry(key: "moray", name: "Moray Eel", weight: 1.5, group: 1...1, shark: false, build: Builtins.morayEel, fun: nil),
        RosterEntry(key: "octopus", name: "Octopus", weight: 1.2, group: 1...1, shark: false, build: Builtins.octopus, fun: nil),
        RosterEntry(key: "anglerfish", name: "Anglerfish", weight: 1, group: 1...1, shark: false, build: Builtins.anglerfish, fun: nil),
        RosterEntry(key: "sailfish", name: "Sailfish", weight: 0.9, group: 1...1, shark: false, build: Builtins.sailfish, fun: nil),
        RosterEntry(key: "turtle", name: "Sea Turtle", weight: 3, group: 1...1, shark: false, build: Builtins.turtle, fun: nil),
        RosterEntry(key: "swordfish", name: "Swordfish", weight: 2, group: 1...1, shark: false, build: { Builtins.swordfish(sword: false) },
                    fun: { Builtins.swordfish(sword: true) }),
        RosterEntry(key: "sawfish", name: "Sawfish", weight: 1.8, group: 1...1, shark: false, build: { Builtins.sawfish(saw: false) },
                    fun: { Builtins.sawfish(saw: true) }),
        RosterEntry(key: "dolphin", name: "Dolphin", weight: 1.8, group: 2...3, shark: false, build: { Builtins.dolphin(helmet: false) },
                    fun: { Builtins.dolphin(helmet: true) }),
        RosterEntry(key: "narwhal", name: "Narwhal", weight: 0.6, group: 1...1, shark: false, build: Builtins.narwhal, fun: nil),
        RosterEntry(key: "hammerhead", name: "Hammerhead Shark", weight: 0.45, group: 1...1, shark: true,
                    build: { Builtins.hammerhead(hammer: false) }, fun: { Builtins.hammerhead(hammer: true) }),
        RosterEntry(key: "tigershark", name: "Tiger Shark", weight: 0.4, group: 1...1, shark: true, build: Builtins.tigerShark,
                    fun: Builtins.tiger),
        RosterEntry(key: "reefshark", name: "Reef Shark", weight: 0.4, group: 1...1, shark: true, build: Builtins.reefShark, fun: nil),
        RosterEntry(key: "kraken", name: "Kraken", weight: 0.12, group: 1...1, shark: false, build: Builtins.kraken, fun: nil),
    ]

    private static var cache: [String: Species] = [:]

    /// Every look, fun ones included, built once.
    static var all: [Species] { entries.flatMap { e in [species(e.key)!] + (e.fun == nil ? [] : [species(e.funKey)!]) } }
    static var base: [Species] { entries.map { species($0.key)! } }

    static func species(_ key: String) -> Species? {
        if let s = cache[key] { return s }
        let base = key.hasSuffix("-fun") ? String(key.dropLast(4)) : key
        guard let e = everyEntry.first(where: { $0.key == base }) else { return nil }
        let s: Species
        if key == base {
            s = e.build()
        } else {
            guard let fun = e.fun else { return nil }
            s = fun()
        }
        s.key = key
        cache[key] = s
        return s
    }

    static func entry(for key: String) -> RosterEntry? {
        everyEntry.first { $0.key == key || $0.funKey == key }
    }

    static func isFun(_ key: String) -> Bool { key.hasSuffix("-fun") }

    /// Freshwater-tank species tuned for the open ocean.
    private static func ocean(_ s: Species) -> Species {
        s.depth = (max(0.15, s.depth.min), min(0.9, s.depth.max))
        return s
    }
}

// MARK: - Models

extension Builtins {
    static func fill(_ m: VoxelModel, _ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>, _ zs: ClosedRange<Int>, _ c: VoxelColor) {
        for x in xs { for y in ys { for z in zs { m.set(x, y, z, c) } } }
    }

    static func ellipsoid(_ m: VoxelModel, _ c: SIMD3<Float>, _ r: SIMD3<Float>, paint: (Int, Int, Int) -> VoxelColor?) {
        for x in Int((c.x - r.x).rounded(.down))...Int((c.x + r.x).rounded(.up)) {
            for y in Int((c.y - r.y).rounded(.down))...Int((c.y + r.y).rounded(.up)) {
                for z in Int((c.z - r.z).rounded(.down))...Int((c.z + r.z).rounded(.up)) {
                    let d = (SIMD3(Float(x), Float(y), Float(z)) - c) / r
                    if simd_length_squared(d) <= 1.05, let color = paint(x, y, z) { m.set(x, y, z, color) }
                }
            }
        }
    }

    /// Frontmost voxel in a column through the body (largest z), for putting faces on the front.
    static func front(_ m: VoxelModel, _ x: Int, _ y: Int) -> Int? { m.voxels.keys.filter { $0.x == x && $0.y == y }.map(\.z).max() }

    /// Wide, flat whale/dolphin tail flukes (they flap up and down).
    static func flukes(_ d: Species, _ len: Int, _ c: VoxelColor) {
        d.flukes = true
        for i in 0..<len {
            let span = 1 + Int(Float(i) * 1.6)
            for x in -span...span where !(i == len - 1 && abs(x) < 2) { d.tail.set(x, 0, -i, c) }
        }
    }

    /// A chain hanging from the body: `count` segments, each `len` voxels long, `width` thick.
    static func tentacle(at anchor: SIMD3<Float>, count: Int, len: Int, width: (Int) -> Int, curl: Float = 1,
                         color: (Int, Int, Int) -> VoxelColor) -> Species.Tentacle {
        var segments: [VoxelModel] = []
        for i in 0..<count {
            let m = VoxelModel()
            let w = width(i)
            for y in 0..<len {
                for x in 0..<w { for z in 0..<w { m.set(x, -y, z, color(i, y, x + z)) } }
            }
            segments.append(m)
        }
        return Species.Tentacle(anchor: anchor, segments: segments, segmentLength: Float(len), curl: curl)
    }

    // MARK: Fish

    static func sardine() -> Species {
        let d = Species(key: "sardine", name: "Sardine", blurb: "Silver, speedy and never alone.", accent: 0x9FB8C8)
        d.voxelSize = 0.042; d.speed = 1.9; d.turn = 3; d.wag = 13; d.depth = (0.3, 0.85)
        d.schooling = true; d.cruiser = true; d.crowd = 0.3
        let back = C(0x2F5F86), silver = C(0xC9D6DE), belly = C(0xEEF3F6), spot = C(0x1D2A36)
        loft(d, 12, 1.6, 1.0) { t, x, y, _, _ in
            if y >= 1 { return back }
            if y == 0 { return abs(x) == 1 && t > 0.45 && t < 0.8 && Int(t * 30) % 3 == 0 ? spot : silver }
            return belly
        }
        fin(d, 0.45, 0.6, up: true, height: { _ in 1 }) { _, _, _ in back }
        tailFan(d, 3, span: { (-0.5 - $0 * 1.8, 0.5 + $0 * 1.8) }) { u, y in u > 0.6 && y == 0 ? nil : silver }
        eye(d, 10, 0)
        return d
    }

    static func yellowTang() -> Species {
        let d = Species(key: "yellowtang", name: "Yellow Tang", blurb: "A bright little sunbeam of a fish.", accent: 0xFFD92E)
        d.speed = 1.2; d.wag = 8; d.depth = (0.25, 0.85); d.schooling = true
        let yellow = C(0xFFD92E), light = C(0xFFE873), white = C(0xFFFFFF)
        loft(d, 13, 4.2, 1.3, b: 0.95, p: 0.55) { t, x, y, h, _ in
            if t < 0.12 && y == 0 && abs(x) >= 1 { return white }
            return Float(y) < -h * 0.4 ? light : yellow
        }
        fin(d, 0.15, 0.9, up: true, height: { _ in 1.6 }) { _, _, _ in yellow }
        fin(d, 0.2, 0.75, up: false, height: { _ in 1.4 }) { _, _, _ in yellow }
        tailFan(d, 3, span: { (-1 - $0 * 2.5, 1 + $0 * 2.5) }) { _, _ in yellow }
        eye(d, 11, 1, big: true)
        // A little pointed snout.
        d.body.set(0, 0, 13, yellow)
        return d
    }

    static func clownfishClown() -> Species {
        let d = clownfish()
        d.name = "Clownfish (in costume)"
        d.blurb = "Takes the name very seriously."
        let white = C(0xF8F8F2)
        let dots = [C(0xE5303A), C(0x2457E8), C(0xFFD23A), C(0x5FD35A)]
        // Polka dots on the white bands.
        for (p, c) in d.body.voxels where c == white && vhash(p.x, p.y, p.z, 31) < 0.3 {
            d.body[p] = dots[Int(vhash(p.x, p.y, p.z, 32) * 4)]
        }
        // A frilly collar just behind the head.
        let ruffle = [C(0xFF4FA3), C(0xFFE14D), C(0x4FD8FF)]
        for y in -6...6 {
            for x in -4...4 {
                let a = Float(y) / 5.2, b = Float(x) / 3.6
                let inner = Float(y * y) / 11 + Float(x * x) / 3.6
                if a * a + b * b <= 1, inner > 1, !d.body.has(x, y, 9) {
                    d.body.set(x, y, 9, ruffle[(Int(atan2(Float(y), Float(x)) * 3) + 9) % 3])
                }
            }
        }
        // Big shiny red nose.
        let red = C(0xFF1E2E, 40)
        fill(d.body, -1...1, -1...1, 13...14, red)
        d.body.set(0, 0, 15, red)
        // Party hat with a pompom.
        let top = d.body.top(x: 1, z: 11) ?? 3
        for z in 10...12 { for x in -1...1 { d.body.set(x, top + 1, z, C(z == 11 ? 0x7B2AB8 : 0xFFD23A)) } }
        for z in 10...12 { for x in -1...1 where abs(x) + abs(z - 11) <= 1 { d.body.set(x, top + 2, z, C(0x2457E8)) } }
        d.body.set(0, top + 3, 11, C(0xE5303A))
        d.body.set(0, top + 4, 11, C(0xFFFFFF, 160))
        return d
    }

    static func catfish() -> Species {
        let d = Species(key: "catfish", name: "Catfish", blurb: "Whiskery, sleepy and fond of the sea floor.", accent: 0x8A7A5E)
        d.speed = 0.6; d.turn = 1.4; d.wag = 5; d.depth = (0.02, 0.22)
        let top = C(0x6E6250), belly = C(0xCDBFA0), mottle = C(0x564B3C), whisker = C(0x3A322A)
        loft(d, 16, 2.3, 2.1, a: 0.05, b: 0.97, p: 0.35) { t, x, y, h, _ in
            if Float(y) < -h * 0.3 { return belly }
            return vnoise(t * 8, Float(y), Float(x), 9) > 0.62 ? mottle : top
        }
        fin(d, 0.55, 0.65, up: true, height: { _ in 2 }) { _, _, _ in top }
        fin(d, 0.1, 0.45, up: false, height: { _ in 1 }) { _, _, _ in top }
        pectoral(d, 12, -1, top)
        tailFan(d, 4, span: { (-1 - $0 * 1.5, 1 + $0 * 1.5) }) { _, _ in top }
        eye(d, 13, 1)
        for s in [-1, 1] {
            for i in 0..<6 { d.body.set(s * (1 + i), -1 - i / 3, 15 + i / 2, whisker) }
            for i in 0..<4 { d.body.set(s * (1 + i), 0, 16 + i / 2, whisker) }
        }
        return d
    }

    /// A catfish, taken literally: a fish with a cat's head.
    static func cat() -> Species {
        let d = Species(key: "catfish-fun", name: "Catfish (literally)", blurb: "Fish below the neck. Cat above it.", accent: 0xE8913A)
        d.speed = 0.6; d.turn = 1.4; d.wag = 5; d.depth = (0.02, 0.3)
        let scales = C(0x6E6250), belly = C(0xCDBFA0), mottle = C(0x564B3C)
        let fur = C(0xE8913A), stripe = C(0xB8601E), white = C(0xF6EBDD), pink = C(0xF28CA0), green = C(0x6BD06B), dark = C(0x15151B)
        // A catfish body...
        loft(d, 12, 2.3, 2.1, a: 0.05, b: 0.75, p: 0.35) { t, x, y, h, _ in
            if Float(y) < -h * 0.3 { return belly }
            return vnoise(t * 8, Float(y), Float(x), 9) > 0.62 ? mottle : scales
        }
        fin(d, 0.4, 0.75, up: true, height: { _ in 2 }) { _, _, _ in scales }
        fin(d, 0.1, 0.45, up: false, height: { _ in 1 }) { _, _, _ in scales }
        pectoral(d, 10, -1, scales)
        tailFan(d, 4, span: { (-1 - $0 * 1.5, 1 + $0 * 1.5) }) { _, _ in scales }
        // ...wearing a cat's head.
        ellipsoid(d.body, SIMD3(0, 1, 14.5), SIMD3(4, 3.8, 3.4)) { x, y, z in
            if y < 0 && z > 15 && abs(x) <= 2 { return white }
            return y > 2 && abs(x) <= 1 && z % 2 == 0 ? stripe : fur
        }
        for s in [-1, 1] {
            fill(d.body, (s < 0 ? -4 ... -2 : 2...4), 5...5, 13...15, fur)
            fill(d.body, (s < 0 ? -3 ... -2 : 2...3), 6...6, 13...14, fur)
            d.body.set(s * 3, 7, 13, fur)
            d.body.set(s * 3, 6, 15, pink)
            d.body.set(s * 2, 2, 18, green)
            d.body.set(s * 2, 3, 18, dark)
            d.body.set(s * 1, 2, 18, green)
            for i in 1...4 { d.body.set(s * (2 + i), 0, 17, C(0xFFFFFF)) }
        }
        d.body.set(0, 1, 18, pink)
        d.body.set(0, 0, 18, white)
        return d
    }

    static func turtle() -> Species {
        let d = Species(key: "turtle", name: "Sea Turtle", blurb: "Unhurried. Has seen it all.", accent: 0x8A6A3A)
        d.speed = 0.5; d.turn = 1; d.wag = 2.5; d.wagAngle = 10; d.depth = (0.3, 0.8); d.crowd = 1.6
        let scute = [C(0x6B4E2E), C(0x8A6A3A), C(0x7A5C33)], line = C(0x4A3520), plastron = C(0xE8D9A8)
        let skin = C(0x9DB06A), spots = C(0x6E8048)
        ellipsoid(d.body, SIMD3(0, 0, 7), SIMD3(5.2, 3, 7.5)) { x, y, z in
            if y < 0 { return y == -1 ? plastron : nil }
            if (x + 40) % 4 == 0 || (z + 40) % 4 == 0 { return line }
            return scute[Int(vhash(x / 4, 0, z / 4, 5) * 3)]
        }
        // Head and neck.
        ellipsoid(d.body, SIMD3(0, 0.5, 16.5), SIMD3(1.7, 1.6, 2.4)) { x, y, z in vhash(x, y, z, 6) < 0.25 ? spots : skin }
        for s in [-1, 1] { d.body.set(s * 2, 1, 17, C(0x0A0A0E)) }
        // Flippers: long at the front, small at the back.
        for s in [-1, 1] {
            for i in 0..<6 { fill(d.body, (s * (5 + i))...(s * (5 + i)), -1 ... -1, (11 - i / 2)...(12 - i / 2), skin) }
            for i in 0..<3 { d.body.set(s * (4 + i), -1, 1 - i / 2, skin); d.body.set(s * (4 + i), -1, 2 - i / 2, skin) }
        }
        d.tail.set(0, 0, 0, skin)
        d.tail.set(0, 0, -1, skin)
        return d
    }

    static func swordfish(sword: Bool) -> Species {
        let d = Species(key: "swordfish", name: sword ? "Swordfish (armed)" : "Swordfish",
                        blurb: sword ? "Took the name literally. En garde!" : "Fast, sleek, and pointy.", accent: 0x23395E)
        d.speed = 2.1; d.turn = 1.6; d.wag = 6; d.wagAngle = 14; d.depth = (0.35, 0.85); d.cruiser = true; d.crowd = 2
        let back = C(0x23395E), belly = C(0x9FB4C8), sail = C(0x2D4A7A)
        loft(d, 22, 2.8, 1.8, a: 0.04, b: 0.92, p: 0.6) { _, _, y, h, _ in Float(y) < -h * 0.2 ? belly : back }
        fin(d, 0.62, 0.78, up: true, height: { 1 + 5 * (1 - $0) }) { _, _, _ in sail }
        fin(d, 0.15, 0.2, up: true, height: { _ in 1 }) { _, _, _ in sail }
        pectoral(d, 15, -1, sail)
        tailFan(d, 7, span: { (-1 - $0 * 5, 1 + $0 * 5) }) { u, y in u > 0.35 && abs(Float(y)) < (u - 0.35) * 9 ? nil : back }
        eye(d, 19, 1, big: true)
        if sword {
            let gold = C(0xE8C23C), steel = C(0xD8DEE6), edge = C(0xF4F8FC, 60), grip = C(0x5A3A22)
            fill(d.body, 0...0, -1...0, 22...23, grip)
            fill(d.body, -3...3, -1...0, 24...24, gold)
            fill(d.body, 0...0, -3...2, 24...24, gold)
            for z in 25...37 {
                d.body.set(0, -1, z, steel)
                d.body.set(0, 0, z, z < 37 ? edge : steel)
                if z < 36 { d.body.set(0, 1, z, steel) }
            }
            d.body.set(0, 0, 38, edge)
        } else {
            let bill = C(0x5A6370)
            for z in 22...31 { d.body.set(0, 0, z, bill); if z < 26 { d.body.set(0, -1, z, bill) } }
        }
        return d
    }

    static func sawfish(saw: Bool) -> Species {
        let d = Species(key: "sawfish", name: saw ? "Sawfish (handy)" : "Sawfish",
                        blurb: saw ? "Brought its own tools." : "A long, toothy nose for poking the sand.", accent: 0x8A7A5E)
        d.speed = 0.8; d.turn = 1.2; d.wag = 4; d.wagAngle = 16; d.depth = (0.0, 0.2); d.cruiser = true; d.crowd = 2.2
        let top = C(0x8A7A5E), belly = C(0xE6DCC6)
        loft(d, 26, 1.9, 3.0, a: 0.04, b: 0.9, p: 0.5, wp: 0.4) { _, _, y, _, _ in y < 0 ? belly : top }
        fin(d, 0.45, 0.55, up: true, height: { _ in 3 }) { _, _, _ in top }
        fin(d, 0.2, 0.26, up: true, height: { _ in 2 }) { _, _, _ in top }
        for s in [-1, 1] {
            for i in 0..<4 { fill(d.body, (s * (4 + i))...(s * (4 + i)), -1 ... -1, (17 - i)...(19 - i), top) }
        }
        tailFan(d, 5, span: { (-1 - $0 * 1.5, 1 + $0 * 4) }) { _, _ in top }
        eye(d, 22, 1)
        if saw {
            let wood = C(0x8B5A2B), steel = C(0xC4CBD2), tooth = C(0x8E979F)
            fill(d.body, 0...0, -2...1, 26...28, wood)
            d.body.set(0, -1, 27, C(0x3A2412))
            for z in 29...43 {
                let height = max(1, 4 - (z - 29) / 4)
                for y in (-height)...0 { d.body.set(0, y, z, steel) }
                if z % 2 == 0 { d.body.set(0, -height - 1, z, tooth) }
            }
        } else {
            let rostrum = C(0x9A8E78), teeth = C(0xF2EEE4)
            for z in 26...37 {
                fill(d.body, -1...1, 0...0, z...z, rostrum)
                if z % 2 == 0 { d.body.set(-2, 0, z, teeth); d.body.set(2, 0, z, teeth) }
            }
        }
        return d
    }

    static func dolphin(helmet: Bool) -> Species {
        let d = Species(key: "dolphin", name: helmet ? "Dolphin (ready for the big game)" : "Dolphin",
                        blurb: helmet ? "Safety first. Go team!" : "Playful, chatty and always smiling.", accent: 0x6F8FA8)
        d.speed = 1.9; d.turn = 1.8; d.wag = 3; d.wagAngle = 20; d.depth = (0.4, 0.9)
        d.porpoise = true; d.cruiser = true; d.crowd = 1.8
        let gray = C(0x6F8FA8), belly = C(0xD8E2EA), dark = C(0x56738C)
        loft(d, 24, 3.0, 2.4, a: 0.05, b: 0.9, p: 0.55) { _, _, y, h, _ in
            Float(y) < -h * 0.25 ? belly : Float(y) > h * 0.6 ? dark : gray
        }
        // Beak.
        fill(d.body, -1...1, -1...0, 23...25, gray)
        d.body.set(0, -1, 26, belly)
        fin(d, 0.42, 0.56, up: true, height: { 1 + 3.5 * sin($0 * .pi * 0.85) }) { _, _, _ in dark }
        pectoral(d, 17, -2, dark)
        flukes(d, 5, dark)
        eye(d, 21, 0)
        if helmet {
            // A classic white helmet: aqua and orange centre stripe, aqua face mask. No logo.
            let shell = C(0xF6F6F4), aqua = C(0x00A3AD), orange = C(0xF26A21), mask = aqua
            func paint(_ x: Int) -> VoxelColor { x == 0 ? orange : abs(x) == 1 ? aqua : shell }
            for (p, _) in d.body.voxels where p.z >= 17 && p.z <= 23 && p.y >= 1 {
                if !d.body.has(p.x, p.y + 1, p.z) { d.body.set(p.x, p.y + 1, p.z, paint(p.x)) }
                d.body[p] = paint(p.x)
            }
            for (p, _) in d.body.voxels where p.z >= 17 && p.z <= 22 && p.y == 1 {
                let x = p.x + (p.x > 0 ? 1 : p.x < 0 ? -1 : 0)
                if !d.body.has(x, p.y, p.z) { d.body.set(x, p.y, p.z, shell) }
            }
            for y in -2...1 { d.body.set(-2, y, 27, mask); d.body.set(2, y, 27, mask) }
            for x in -2...2 { d.body.set(x, 1, 27, mask); d.body.set(x, -1, 27, mask) }
            fill(d.body, -2...2, 1...1, 26...26, mask)
        }
        return d
    }

    static func narwhal() -> Species {
        let d = Species(key: "narwhal", name: "Narwhal", blurb: "The unicorn of the sea, and it knows it.", accent: 0xB57CFF)
        d.speed = 1.1; d.turn = 1.2; d.wag = 2.5; d.wagAngle = 18; d.depth = (0.45, 0.9); d.cruiser = true; d.crowd = 2.4
        let gray = C(0x8E9AA6), spot = C(0x5B6672), belly = C(0xDCE2E6)
        loft(d, 26, 3.3, 3.0, a: 0.05, b: 0.95, p: 0.5) { t, x, y, h, _ in
            if Float(y) < -h * 0.3 { return belly }
            return vhash(x, y, Int(t * 100), 3) < 0.22 ? spot : gray
        }
        pectoral(d, 19, -2, spot)
        flukes(d, 6, gray)
        eye(d, 23, 0)
        // The rainbow horn, glowing.
        let rainbow: [UInt32] = [0xFF3B3B, 0xFF9A2E, 0xFFE23B, 0x4BDE5A, 0x3BA8FF, 0x8E5BFF]
        for z in 26...40 {
            let c = C(rainbow[((z - 26) / 2) % rainbow.count], 120)
            d.body.set(0, 1, z, c)
            if z < 30 { d.body.set(0, 0, z, C(rainbow[((z - 25) / 2) % rainbow.count], 120)) }
        }
        return d
    }

    // MARK: Jellies

    static func jellyfish(jello: Bool) -> Species {
        let d = Species(key: "jellyfish", name: jello ? "Jellyfish (actual jelly)" : "Jellyfish",
                        blurb: jello ? "Wobbly, fruity, and served chilled." : "Drifts along, glowing softly.",
                        accent: jello ? 0xE3222F : 0xF7A8D8)
        d.voxelSize = 0.06; d.speed = 0.28; d.depth = (0.35, 0.95); d.motion = .drift; d.jelly = true; d.crowd = 1
        if jello {
            let red = C(0xE3222F), deep = C(0xB8121F), cream = C(0xFFF8EE), cherry = C(0xC8102E, 40)
            for y in 0...5 {
                let r = 5.3 - Float(y) * 0.55
                for x in -6...6 {
                    for z in -6...6 {
                        let rr = Float(x * x + z * z).squareRoot()
                        guard rr <= r else { continue }
                        let flute = rr > r - 1.2 && Int((atan2(Float(z), Float(x)) + .pi) / (2 * .pi) * 12) % 2 == 1
                        if !flute { d.body.set(x, y, z, y % 2 == 0 ? red : deep) }
                    }
                }
            }
            for x in -2...2 { for z in -2...2 where x * x + z * z <= 5 { d.body.set(x, 6, z, cream) } }
            for x in -1...1 { for z in -1...1 { d.body.set(x, 7, z, cream) } }
            d.body.set(0, 8, 0, cherry)
            d.body.set(1, 8, 0, cherry)
            d.body.set(0, 9, 0, C(0x3E8E3A))
            d.body.set(0, 10, 1, C(0x3E8E3A))
            for k in 0..<7 {
                let a = Float(k) / 7 * 2 * .pi
                d.tentacles.append(tentacle(at: SIMD3(cos(a) * 4, -0.5, sin(a) * 4), count: 6, len: 3, width: { _ in 1 }) { i, _, _ in
                    i % 2 == 0 ? C(0xFF5A5A) : C(0xFF8A8A)
                })
            }
        } else {
            let bell = C(0xF7A8D8), rim = C(0xFFD6EE, 90), core = C(0xFFC2E4, 140)
            ellipsoid(d.body, SIMD3(0, 0, 0), SIMD3(5.2, 4.6, 5.2)) { x, y, z in
                if y < 0 { return nil }
                if y == 0 { return (x + z) % 2 == 0 ? rim : bell }
                return abs(x) <= 1 && abs(z) <= 1 && y >= 1 && y <= 2 ? core : bell
            }
            for k in 0..<8 {
                let a = Float(k) / 8 * 2 * .pi
                d.tentacles.append(tentacle(at: SIMD3(cos(a) * 4.5, -0.5, sin(a) * 4.5), count: 7, len: 3, width: { _ in 1 }) { i, y, _ in
                    (i + y) % 3 == 0 ? C(0xFFFFFF, 90) : C(0xFFD6EE, 70)
                })
            }
            for k in 0..<4 {
                let a = Float(k) / 4 * 2 * .pi + 0.4
                d.tentacles.append(tentacle(at: SIMD3(cos(a), -0.5, sin(a)), count: 5, len: 3, width: { $0 < 2 ? 2 : 1 }, curl: 0.6) { _, _, _ in
                    C(0xFF7FC0)
                })
            }
        }
        return d
    }

    static func boxJelly(box: Bool) -> Species {
        let d = Species(key: "boxjelly", name: box ? "Box Jellyfish (an actual box)" : "Box Jellyfish",
                        blurb: box ? "Handle with care. This side up." : "Small, square and best admired from afar.",
                        accent: box ? 0xC8A066 : 0xB8ECFF)
        d.voxelSize = 0.06; d.speed = 0.3; d.depth = (0.3, 0.9); d.motion = .drift; d.jelly = !box; d.crowd = 1
        if box {
            let card = C(0xC8A066), edge = C(0xA27A44), tape = C(0xE2D3A8), ink = C(0x2A2018)
            for x in -3...3 {
                for y in 0...6 {
                    for z in -3...3 {
                        let edges = [abs(x) == 3, y == 0 || y == 6, abs(z) == 3].filter { $0 }.count
                        d.body.set(x, y, z, edges >= 2 ? edge : y == 6 && x == 0 ? tape : card)
                    }
                }
            }
            // Open flaps.
            for i in -3...3 {
                d.body.set(4, 7, i, card); d.body.set(5, 8, i, card)
                d.body.set(-4, 7, i, card); d.body.set(-5, 8, i, card)
                d.body.set(i, 7, 4, card); d.body.set(i, 7, -4, card)
            }
            // "This side up" arrows.
            for (x, y) in [(0, 2), (0, 3), (0, 4), (-1, 3), (1, 3)] { d.body.set(x, y, 4, ink); d.body.set(x, y, -4, ink) }
        } else {
            let body = C(0xB8ECFF), edge = C(0xE6FAFF, 90)
            for x in -3...3 {
                for y in 0...5 {
                    for z in -3...3 {
                        let edges = [abs(x) == 3, y == 5, abs(z) == 3].filter { $0 }.count
                        d.body.set(x, y, z, edges >= 2 ? edge : body)
                    }
                }
            }
        }
        for (x, z) in [(-3, -3), (3, -3), (-3, 3), (3, 3)] {
            for k in 0..<2 {
                d.tentacles.append(tentacle(at: SIMD3(Float(x) + Float(k) * 0.4, -0.5, Float(z)), count: 6, len: 3, width: { _ in 1 }) { i, _, _ in
                    i % 3 == 0 ? C(0xFFFFFF, 90) : C(0xD8F6FF, 70)
                })
            }
        }
        return d
    }

    // MARK: Sharks

    /// A shark's body: torpedo, tall dorsal fin, wing-like pectorals and a tail with a long top lobe.
    static func sharkBody(_ d: Species, _ len: Int, _ height: Float, _ width: Float, finColor: VoxelColor, tip: VoxelColor? = nil,
                          paint: (Float, Int, Int, Float, Float) -> VoxelColor) {
        d.voxelSize = 0.08; d.speed = 1.3; d.turn = 1.3; d.wag = 4; d.wagAngle = 16; d.depth = (0.3, 0.8)
        d.scary = true; d.cruiser = true; d.crowd = 3
        loft(d, len, height, width, a: 0.04, b: 0.86, p: 0.65, paint: paint)
        fin(d, 0.46, 0.62, up: true, height: { $0 < 0.65 ? 1 + 6 * $0 / 0.65 : 7 * (1 - $0) / 0.35 }) { _, k, n in
            k == n ? (tip ?? finColor) : finColor
        }
        fin(d, 0.16, 0.2, up: true, height: { _ in 2 }) { _, _, _ in finColor }
        fin(d, 0.18, 0.22, up: false, height: { _ in 1 }) { _, _, _ in finColor }
        let lp = Int(Float(len) * 0.62)
        for s in [-1, 1] {
            let x0 = d.body.side(y: -1, z: lp, sign: s)
            for k in 1...5 {
                for dz in 0...1 { d.body.set(s * (abs(x0) + k), -1 - k / 2, lp - k / 2 - dz, k == 5 ? (tip ?? finColor) : finColor) }
            }
        }
        tailFan(d, 8, span: { (-1 - $0 * 3, 1 + $0 * 7) }) { u, y in
            if y < 0 && u > 0.55 { return nil }
            if y >= 0 && y < 2 && u > 0.5 { return nil }
            return u > 0.85 ? (tip ?? finColor) : finColor
        }
        eye(d, len - 4, 1)
        // Gill slits.
        for s in [-1, 1] {
            for l in (len - 9)...(len - 7) { d.body.set(s * max(1, abs(d.body.side(y: 0, z: l, sign: s))), 0, l, C(0x3A4248)) }
        }
    }

    static func hammerhead(hammer: Bool) -> Species {
        let d = Species(key: "hammerhead", name: hammer ? "Hammerhead (literal)" : "Hammerhead Shark",
                        blurb: hammer ? "Every problem looks like a nail." : "A wide, curious head and a calm cruise.",
                        accent: 0x7E8C93)
        let skin = C(0x7E8C93), belly = C(0xE4E8EA)
        sharkBody(d, 30, 3.1, 2.4, finColor: skin) { _, _, y, h, _ in Float(y) < -h * 0.3 ? belly : skin }
        if hammer {
            let wood = C(0x9A6A3A), steel = C(0x8E979F), face = C(0x5E666E)
            fill(d.body, -1...1, -1...1, 29...34, wood)
            fill(d.body, -6...6, -2...2, 35...38, steel)
            fill(d.body, -7 ... -7, -2...2, 35...38, face)
            fill(d.body, 7...7, -2...2, 35...38, face)
            for s in [-1, 1] { d.body.set(s * 8, 0, 37, C(0x0A0A0E)); d.body.set(s * 8, 1, 37, C(0xFFFFFF, 200)) }
        } else {
            for x in -7...7 {
                d.body.set(x, 0, 30, skin)
                d.body.set(x, 0, 31, skin)
                if abs(x) < 6 { d.body.set(x, 1, 30, skin) }
            }
            for s in [-1, 1] { d.body.set(s * 8, 0, 30, C(0x0A0A0E)) }
        }
        return d
    }

    static func tigerShark() -> Species {
        let d = Species(key: "tigershark", name: "Tiger Shark", blurb: "Stripy, curious, and just passing through.", accent: 0x7D7563)
        let skin = C(0x7D7563), stripe = C(0x4F4838), belly = C(0xEDEAE0)
        sharkBody(d, 32, 3.2, 2.6, finColor: skin) { t, _, y, h, _ in
            if Float(y) < -h * 0.3 { return belly }
            return t > 0.15 && t < 0.8 && sin(t * 60) > 0.55 ? stripe : skin
        }
        return d
    }

    /// The tiger shark, if it were a tiger. With fins.
    static func tiger() -> Species {
        let d = Species(key: "tigershark-fun", name: "Tiger (shark)", blurb: "Grew fins. Still a tiger.", accent: 0xF08A24)
        d.voxelSize = 0.08; d.speed = 1.2; d.turn = 1.3; d.wag = 3.5; d.wagAngle = 18; d.depth = (0.3, 0.8)
        d.scary = true; d.cruiser = true; d.crowd = 3
        let fur = C(0xF08A24), black = C(0x1A1410), white = C(0xF7F1E6), pink = C(0xE07A8A), eye = C(0xD8E04A)
        ellipsoid(d.body, SIMD3(0, 0, 11), SIMD3(3, 3.2, 11)) { x, y, z in
            if y < -1 { return white }
            return sin(Float(z) * 1.2 + Float(abs(y)) * 0.35) > 0.6 ? black : fur
        }
        ellipsoid(d.body, SIMD3(0, 1.5, 23.5), SIMD3(3.4, 3.2, 3)) { x, y, z in
            if y < 1 && z > 23 && abs(x) <= 2 { return white }
            if y > 3 && abs(x) <= 1 && z % 2 == 0 { return black }
            return abs(x) == 3 && y % 2 == 0 ? black : fur
        }
        for s in [-1, 1] {
            fill(d.body, (s < 0 ? -3 ... -2 : 2...3), 5...5, 22...23, black)
            d.body.set(s * 2, 5, 22, white)
            d.body.set(s * 2, 3, 26, eye)
            d.body.set(s * 2, 3, 27, black)
            for i in 1...3 { d.body.set(s * (2 + i), 1, 26, C(0xFFFFFF)) }
            // Legs with white paws.
            for z in [5, 16] {
                fill(d.body, s * 2...s * 2, -5 ... -3, z...z + 1, fur)
                d.body.set(s * 2, -4, z, black)
                fill(d.body, s * 2...s * 2, -6 ... -6, z...z + 2, white)
            }
        }
        d.body.set(0, 2, 27, pink)
        d.body.set(0, 1, 27, white)
        // Shark fins: a striped dorsal and side fins.
        for k in 1...6 { for z in (10 - k / 3)...(14 - k) where z >= 9 { d.body.set(0, 3 + k, z, k % 2 == 0 ? black : fur) } }
        for s in [-1, 1] { for k in 1...4 { d.body.set(s * (3 + k), -1 - k / 2, 18 - k / 2, fur) } }
        tailFan(d, 7, span: { (-1 - $0 * 3, 1 + $0 * 6) }) { u, y in
            if y >= 0 && y < 2 && u > 0.5 { return nil }
            return Int(u * 7) % 2 == 0 ? fur : black
        }
        return d
    }

    static func reefShark() -> Species {
        let d = Species(key: "reefshark", name: "Reef Shark", blurb: "Sleek, grey, and only looking.", accent: 0x8A949C)
        let skin = C(0x8A949C), belly = C(0xF0F2F3)
        sharkBody(d, 30, 3, 2.4, finColor: skin, tip: C(0x22262A)) { _, _, y, h, _ in Float(y) < -h * 0.25 ? belly : skin }
        return d
    }

    // MARK: Kraken

    static func kraken() -> Species {
        let d = Species(key: "kraken", name: "Kraken", blurb: "Rises from the deep now and then. Just to look.", accent: 0xA3203A)
        d.voxelSize = 0.13; d.speed = 0.4; d.motion = .kraken; d.scary = true; d.crowd = 6; d.depth = (0, 0.3); d.splay = 1.15
        let red = C(0xA3203A), spot = C(0x7A1528), sucker = C(0xF1C9B0), yellow = C(0xF2C230), black = C(0x0A0A0E)
        ellipsoid(d.body, SIMD3(0, 9, 0), SIMD3(7, 9.5, 6.5)) { x, y, z in vhash(x, y, z, 17) < 0.18 ? spot : red }
        ellipsoid(d.body, SIMD3(0, 1, 0), SIMD3(7, 2.4, 7)) { _, _, _ in red }
        for s in [-1, 1] {
            for y in 6...10 {
                for dx in 0...3 {
                    let x = s * (1 + dx)
                    if let z = front(d.body, x, y) { let c = dx == 2 && y > 6 && y < 10 ? black : yellow
                        d.body.set(x, y, z, c)
                        d.body.set(x, y, z + 1, c) }
                }
            }
        }
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + 0.2
            d.tentacles.append(tentacle(at: SIMD3(cos(a) * 5.5, 0, sin(a) * 5.5), count: 8, len: 3, width: { $0 < 4 ? 2 : 1 }, curl: 1.6) { _, y, side in
                side == 0 && y == 1 ? sucker : red
            })
        }
        return d
    }
}

// MARK: - Rig

/// The nodes of one creature: body, wagging tail, and any tentacle chains, ready to pose.
@MainActor
final class CreatureRig {
    let model = SCNNode()
    let tail: SCNNode?
    /// The pufferfish's spines, hidden until it puffs.
    let spikes: SCNNode?
    private var wings: [(node: SCNNode, side: Float)] = []
    private var chains: [(nodes: [SCNNode], axis: SIMD3<Float>, splay: Float, curl: Float, phase: Float)] = []
    let species: Species

    init(_ s: Species, material: (SCNMaterial) -> SCNMaterial = { $0 }) {
        species = s
        func dress(_ g: SCNGeometry) -> SCNGeometry {
            let copy = g.copy() as! SCNGeometry
            copy.materials = g.materials.map { m in material(m === Materials.lit && s.jelly ? Materials.jelly : m) }
            return copy
        }
        model.geometry = dress(s.bodyGeometry)
        if s.tail.isEmpty {
            tail = nil
        } else {
            let t = SCNNode(geometry: dress(s.tailGeometry))
            t.simdPosition = SIMD3(0, 0, s.tailJointZ)
            model.addChildNode(t)
            tail = t
        }
        if let sp = s.spikes {
            let n = SCNNode(geometry: dress(sp.geometry(size: s.voxelSize, pivot: SIMD3(0, 0, s.zCenter))))
            n.opacity = 0
            model.addChildNode(n)
            spikes = n
        } else {
            spikes = nil
        }
        if let w = s.wings {
            let left = VoxelModel()
            for (p, c) in w.voxels { left.set(-p.x, p.y, p.z, c) }
            for (side, m) in [(Float(1), w), (Float(-1), left)] {
                let n = SCNNode(geometry: dress(m.geometry(size: s.voxelSize, pivot: SIMD3(0, 0, 0))))
                n.simdPosition = s.local(s.wingJoint)
                model.addChildNode(n)
                wings.append((n, side))
            }
        }
        for (i, t) in s.tentacles.enumerated() {
            var parent = model
            var nodes: [SCNNode] = []
            for (k, seg) in t.segments.enumerated() {
                let sw = Float(seg.bounds.map { $0.max.x - $0.min.x + 1 } ?? 1)
                let g = dress(seg.geometry(size: s.voxelSize, pivot: SIMD3((sw - 1) / 2, 0.5, (sw - 1) / 2)))
                let n = SCNNode(geometry: g)
                n.simdPosition = k == 0 ? s.local(t.anchor) : SIMD3(0, -t.segmentLength * s.voxelSize, 0)
                parent.addChildNode(n)
                nodes.append(n)
                parent = n
            }
            var radial = SIMD3<Float>(t.anchor.x, 0, t.anchor.z)
            if simd_length_squared(radial) < 0.01 { radial = SIMD3(cos(Float(i)), 0, sin(Float(i))) }
            let axis = simd_normalize(simd_cross(SIMD3(0, 1, 0), simd_normalize(radial)))
            chains.append((nodes, axis, s.splay, t.curl, Float(i) * 1.37))
        }
        pose(time: 0, wag: 0)
    }

    func set(mask: Int) {
        model.enumerateHierarchy { n, _ in n.categoryBitMask = mask }
    }

    /// Tail angle (wag, -1...1) and tentacle sway at a time.
    func pose(time: Float, wag: Float, pulse: Float = 0) {
        if let tail {
            let a = wag * species.wagAngle * .pi / 180
            tail.simdEulerAngles = species.flukes ? SIMD3(a, 0, 0) : SIMD3(0, a, 0)
        }
        // Wings beat up and down about the body's long axis, a little faster on the downstroke.
        let beat = sin(time * species.flap * 2 * .pi)
        for w in wings {
            let a = (beat * species.flapAngle + 8) * .pi / 180
            w.node.simdEulerAngles = SIMD3(0, 0, w.side * a)
        }
        for c in chains {
            for (k, n) in c.nodes.enumerated() {
                let sway = sin(time * 1.6 - Float(k) * 0.55 + c.phase)
                var angle = sway * 0.16 * c.curl * (0.4 + Float(k) * 0.12) - pulse * 0.2
                if k == 0 { angle += c.splay + pulse * 0.25 }
                n.simdOrientation = simd_quatf(angle: -angle, axis: c.axis)
            }
        }
    }
}

extension Materials {
    /// Glossy, see-through jelly.
    static let jelly: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = NSColor.white
        m.specular.contents = NSColor(white: 0.9, alpha: 1)
        m.shininess = 0.85
        m.transparency = 0.62
        m.transparencyMode = .dualLayer
        m.emission.contents = NSColor(white: 0.08, alpha: 1)
        return m
    }()
}
