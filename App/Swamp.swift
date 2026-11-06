import SceneKit
import simd

/// Under the water of a Louisiana bayou: muddy floor, cypress trunks and knees, lily pads overhead,
/// a sunken pirogue, and bass, bluegill, crawfish, gar, snapping turtles, frogs, nutria and the odd alligator.
enum Swamp {
    @MainActor
    static func build(into root: SCNNode) -> TankDecor.Built {
        var rng = SeededRandom(seed: 11)
        // Hazy banks, one behind the other, with far-off trunks between them.
        TankDecor.place(root, "Farthest Ridge", TankDecor.ridge(seed: 167, width: 60, height: 10, colors: [0x6E7E4E, 0x687A4A, 0x748452],
                                                               kelp: 0x5E6E42, kelpChance: 0.06, detail: 2),
                        size: 0.3, at: SIMD3(0, -1.5, 19)).castsShadow = false
        for (x, z, r, s) in [(-11.0, 16.0, 6, 0.25), (8.0, 17.5, 5, 0.25), (-3.0, 11.5, 5, 0.2)] as [(Float, Float, Int, Float)] {
            let far = z > 12
            TankDecor.place(root, "Cypress", cypress(&rng, radius: r, height: Int(14 / s), far: far), size: s,
                            at: SIMD3(x, far ? -0.8 : -0.3, z)).castsShadow = false
        }
        TankDecor.place(root, "Near Ridge", TankDecor.ridge(seed: 173, width: 62, height: 4, colors: [0x5A5A36, 0x524F30, 0x625F3C],
                                                           kelp: 0x5E7A3A, kelpChance: 0.06, detail: 2),
                        size: 0.175, at: SIMD3(0, 0.1, 6.5)).castsShadow = false
        // The water: everything below the line is seen through murky green, everything above is open air.
        let level = TankController.waterLevel
        TankDecor.addWater(root, level: level, back: 31, color: 0x2E4A26)

        // Lily pads floating on the surface, their long stems going down to the mud.
        for i in 0..<7 {
            let x = Float(i) * 4.4 - 14 + Float(rng.next(100)) / 100, z = Float(rng.next(500)) / 100 - 1
            TankDecor.place(root, "Lily", lily(&rng), size: 0.06, at: SIMD3(x, level + 0.02, z)).castsShadow = false
        }
        // Cattails standing up out of the water at the edges.
        for (x, z) in [(-12.5, 2.2), (-11.8, 2.6), (-13.2, 1.8), (11.6, 2.4), (12.4, 2.0), (-6.4, 2.8), (6.8, 2.9)] as [(Float, Float)] {
            let base = TankDecor.floor(x, z)
            TankDecor.place(root, "Cattail", cattail(&rng, height: Int((level + 0.8 + Float(rng.next(60)) / 100 - base) / 0.05)),
                            size: 0.05, at: SIMD3(x, base - 0.02, z))
        }

        // Cypress knees poking out of the mud, and a couple of trunks right up close.
        for (x, z) in [(-3.4, 2.4), (-3.0, 2.0), (8.2, 1.4), (-8.6, 2.2)] as [(Float, Float)] {
            TankDecor.place(root, "Knee", knee(&rng), size: 0.06, at: SIMD3(x, TankDecor.floor(x, z) - 0.05, z))
        }
        for (x, z) in [(9.6, 3.2)] as [(Float, Float)] {
            TankDecor.place(root, "Cypress", cypress(&rng, radius: 7, height: 75, far: false), size: 0.1,
                            at: SIMD3(x, TankDecor.floor(x, z) - 0.2, z))
        }
        TankDecor.place(root, "Log", sunkenLog(), size: 0.08, at: SIMD3(-1.6, TankDecor.floor(-1.6, 2.2) - 0.08, 2.2))
        TankDecor.place(root, "Pirogue", pirogue(), size: 0.06, at: SIMD3(5.6, TankDecor.floor(5.6, 1.0) - 0.05, 1.0))
        for (x, z) in [(-12.4, 1.6)] as [(Float, Float)] {
            TankDecor.place(root, "Rock", TankDecor.rock(&rng, 10, 6, 8), size: 0.06, at: SIMD3(x, TankDecor.floor(x, z) - 0.1, z))
        }

        // Eelgrass and coontail, swaying.
        var weeds: [Seaweed] = []
        for i in 0..<13 {
            let x = Float(i) * 2.4 - 15 + Float(rng.next(60)) / 100, z = Float(rng.next(420)) / 100 - 1.2
            weeds.append(Seaweed(root: root, at: SIMD3(x, TankDecor.floor(x, z), z), segments: 3 + rng.next(4), seed: i,
                                 colors: [0x5E7A2E, 0x6E8A3A, 0x4E6A26, 0x7A9244]))
        }

        // Lafitte's treasure, of course.
        let chests = [Chest(root: root, at: SIMD3(-4.8, TankDecor.floor(-4.8, 1.0), 1.0), turn: 14)]
        return TankDecor.Built(chests: chests, seaweed: weeds, vent: SIMD3(3.4, TankDecor.floor(3.4, 1.6) + 0.05, 1.6),
                               water: (level, 31))
    }

    // MARK: - Scenery

    /// A bald cypress: a flared, ridged trunk that rises out of the top of the view.
    static func cypress(_ rng: inout SeededRandom, radius: Int, height: Int, far: Bool) -> VoxelModel {
        let m = VoxelModel()
        let seed = rng.next(1000)
        let bark: [UInt32] = far ? [0x56603E, 0x4E5838, 0x5E6844] : [0x5A4632, 0x4E3C2A, 0x66503A, 0x46362A]
        let r0 = Float(radius)
        for y in 0..<height {
            let flare = max(0, 1 - Float(y) / Float(radius * 3))
            let r = r0 * (1 + flare * flare * 1.4) + vnoise(0, Float(y) * 0.2, 0, seed) * 1.2
            let ri = Int(r.rounded(.up))
            for x in -ri...ri {
                for z in -ri...ri {
                    let a = atan2(Float(z), Float(x))
                    let groove = sin(a * 9 + Float(y) * 0.05) * (0.6 + flare)
                    let d2 = sq(Float(x)) + sq(Float(z))
                    // Just the bark: the inside never shows.
                    if d2 > sq(r + groove) || d2 < sq(max(0, r + groove - 2.2)) { continue }
                    let moss = !far && y < radius && vhash(x, y, z, seed) < 0.25
                    m.set(x, y, z, C(moss ? 0x5E7A3A : bark[Int(vhash(x, y, z, seed + 1) * Float(bark.count))]))
                }
            }
        }
        // Spanish moss hanging in grey-green beards from the upper trunk, above the water.
        for k in 0..<10 {
            let a = Float(k) / 10 * 2 * .pi + Float(rng.next(60)) / 100
            let y0 = height / 2 + rng.next(height / 2)
            let rx = Int((cos(a) * (r0 + 1.5)).rounded()), rz = Int((sin(a) * (r0 + 1.5)).rounded())
            for s in -1...1 {
                let len = 6 + rng.next(10)
                for i in 0..<len where vhash(k, i, s, seed) > 0.12 {
                    m.set(rx + s, y0 - i, rz, C(far ? 0x8A9478 : [0x9AA48A, 0xA8B098, 0x8A967A][(i + s + 3) % 3]))
                }
            }
        }
        return m
    }

    /// A cattail: a tall stalk with a brown, sausage-shaped head and a couple of long leaves.
    static func cattail(_ rng: inout SeededRandom, height h: Int) -> VoxelModel {
        let m = VoxelModel()
        for y in 0..<h { m.set(0, y, 0, C(0x6E8A3A)) }
        for y in (h - 14)..<(h - 4) { for (x, z) in [(1, 0), (-1, 0), (0, 1), (0, -1), (0, 0)] { m.set(x, y, z, C(0x6A4428)) } }
        for y in (h - 4)..<h { m.set(0, y, 0, C(0x8A9A5A)) }
        for k in [-1, 1] {
            let len = h - 10 - rng.next(10)
            for y in 0..<len { m.set(k * (y * 2 / max(1, len)), y, k, C(y > len * 2 / 3 ? 0x8AA048 : 0x6E8A3A)) }
        }
        return m
    }

    /// A cypress knee: a knobbly cone sticking up from the roots.
    static func knee(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        let h = 8 + rng.next(10), seed = rng.next(100)
        for y in 0..<h {
            let r = 3.2 * (1 - Float(y) / Float(h + 2)) + 0.6
            let lean = Int(Float(y) * 0.12 * (seed % 2 == 0 ? 1 : -1))
            for x in -4...4 {
                for z in -4...4 where sq(Float(x)) + sq(Float(z)) <= r * r {
                    m.set(x + lean, y, z, C(vhash(x, y, z, seed) < 0.5 ? 0x6E5A40 : 0x5A4834))
                }
            }
        }
        return m
    }

    /// A lily pad seen from below (flat, notched, a stem dropping away) and sometimes a flower above it.
    static func lily(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        let r = Float(5 + rng.next(4)), notch = Float(rng.next(628)) / 100
        for x in -Int(r)...Int(r) {
            for z in -Int(r)...Int(r) {
                let d = (sq(Float(x)) + sq(Float(z))).squareRoot()
                guard d <= r else { continue }
                var da = atan2(Float(z), Float(x)) - notch
                da = atan2(sin(da), cos(da))
                if abs(da) < 0.25 { continue }
                m.set(x, 0, z, C(d > r - 1 ? 0x4E7A2E : vhash(x, 0, z, 9) < 0.5 ? 0x6A9A3A : 0x5E8E34, 40))
            }
        }
        for y in 1...30 { m.set(Int(sin(Float(y) * 0.2) * 1.5), -y, 0, C(0x5E7A3A)) }
        if rng.next(3) == 0 {
            for (x, z) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] { m.set(x, 1, z, C(0xF2B8D0, 80)) }
            m.set(0, 2, 0, C(0xF2D25A, 120))
        }
        return m
    }

    /// An old log, waterlogged and mossy, half buried in the mud.
    static func sunkenLog() -> VoxelModel {
        let m = VoxelModel()
        for z in -30...30 {
            for x in -4...4 {
                for y in -4...4 where x * x + y * y <= 17 {
                    let rings = (x * x + y * y) < 7
                    let end = abs(z) == 30
                    let moss = y >= 3 && vhash(x, y, z, 3) < 0.6
                    m.set(x + z / 6, y, z, C(end ? (rings ? 0xA88A5E : 0x7A5E3E) : moss ? 0x5E7A3A : vhash(x, y, z, 2) < 0.5 ? 0x4E3C2A : 0x5E4A34))
                }
            }
        }
        // A broken-off branch.
        for i in 0..<12 { m.set(3 + i / 2, 3 + i, 8, C(0x4E3C2A)) }
        return m
    }

    /// A Cajun pirogue: a flat-bottomed wooden canoe, sunk and settled on its side a little.
    static func pirogue() -> VoxelModel {
        let m = VoxelModel()
        let wood: [UInt32] = [0x7A5A3A, 0x6E5034, 0x86643E]
        for z in -24...24 {
            let half = 5 * (1 - sq(Float(z) / 25)), hi = Int(4 * (1 - sq(Float(z) / 27))) + 1
            for x in -Int(half)...Int(half) {
                for y in 0...hi {
                    let wall = abs(Float(x)) >= half - 1 || y == 0
                    if wall { m.set(x, y + abs(x) / 3, z, C(wood[Int(vhash(x, y, z, 5) * 3)])) }
                }
            }
        }
        // A paddle left inside.
        for z in -14...10 { m.set(1, 2, z, C(0xA07A4A)) }
        for z in 10...15 { for x in 0...2 { m.set(x, 2, z, C(0xA07A4A)) } }
        return m
    }

    /// A wire crawfish trap, its float rope going up out of sight.
    static func trap() -> VoxelModel {
        let m = VoxelModel()
        for x in -6...6 {
            for y in 0...8 {
                for z in -6...6 where abs(x) == 6 || abs(z) == 6 || y == 0 || y == 8 {
                    if (x + y + z) % 2 == 0 { m.set(x, y, z, C(0x8A9A8A)) }
                }
            }
        }
        for y in 9...60 { m.set(0, y, 0, C(0xC8B890)) }
        return m
    }

    /// The muddy bank along the back, roots tangled through it, eelgrass on top.
    static func bank() -> VoxelModel {
        let m = VoxelModel()
        let mud: [UInt32] = [0x5A4834, 0x4E3E2C, 0x66533C, 0x463828]
        for x in -168...168 {
            let h = OceanLife.reefHeight(x)
            for z in 0..<5 {
                let hz = h - (4 - z) * (1 + Int(vhash(x, z, 0, 142) * 2))
                for y in 0..<max(1, hz) {
                    let root = abs(vnoise(Float(x) * 0.05, Float(y) * 0.1, Float(z), 146) - 0.5) < 0.02
                    let grass = y >= hz - 1 && vnoise(Float(x) * 0.2, 0, Float(z), 143) > 0.5
                    let c: UInt32 = grass ? 0x5E7A34 : root ? 0x2E2418 : mud[Int(vhash(x, y, z, 144) * Float(mud.count))]
                    m.set(x, y, z, C(c))
                }
            }
            // Grass blades, and every so often a cypress knee.
            if vhash(x, 0, 0, 145) < 0.08 {
                for y in 0..<(2 + Int(vhash(x, 2, 0, 145) * 6)) { m.set(x, h + y, 2, C(y > 3 ? 0x8AA048 : 0x6E8A3A)) }
            }
            if x % 60 == 0 && vhash(x, 5, 0, 145) < 0.5 {
                for y in 0..<9 { for dx in -(2 - y / 4)...(2 - y / 4) { m.set(x + dx, h + y, 3, C(0x6E5A40)) } }
            }
        }
        return m
    }

    // MARK: - Creatures

    @MainActor static let entries: [RosterEntry] = [
        RosterEntry(key: "bluegill", name: "Bluegill", weight: 8, group: 3...6, shark: false, build: bluegill, fun: nil),
        RosterEntry(key: "bass", name: "Largemouth Bass", weight: 6, group: 1...3, shark: false, build: bass, fun: nil, peeks: true),
        RosterEntry(key: "redfish", name: "Redfish", weight: 4, group: 1...3, shark: false, build: redfish, fun: nil),
        RosterEntry(key: "crawfish", name: "Crawfish", weight: 5, group: 1...3, shark: false, build: { crawfish(mardiGras: false) },
                    fun: { crawfish(mardiGras: true) }),
        RosterEntry(key: "channelcat", name: "Channel Catfish", weight: 3, group: 1...2, shark: false, build: Builtins.catfish,
                    fun: Builtins.cat),
        RosterEntry(key: "bullfrog", name: "Bullfrog", weight: 3, group: 1...1, shark: false, build: { bullfrog(prince: false) },
                    fun: { bullfrog(prince: true) }, peeks: true),
        RosterEntry(key: "gar", name: "Alligator Gar", weight: 1.8, group: 1...2, shark: false, build: gar, fun: nil, peeks: true),
        RosterEntry(key: "snapper", name: "Snapping Turtle", weight: 1.6, group: 1...1, shark: false, build: snapper, fun: nil, peeks: true),
        RosterEntry(key: "nutria", name: "Nutria", weight: 1.6, group: 1...1, shark: false, build: nutria, fun: nil, peeks: true),
        RosterEntry(key: "cottonmouth", name: "Cottonmouth", weight: 1.2, group: 1...1, shark: false, build: cottonmouth, fun: nil),
        RosterEntry(key: "mallard", name: "Mallard", weight: 3.5, group: 1...3, shark: false, build: { mallard(rubber: false) },
                    fun: { mallard(rubber: true) }),
        RosterEntry(key: "woodduck", name: "Wood Duck", weight: 2, group: 1...2, shark: false, build: woodDuck, fun: nil),
        RosterEntry(key: "flyingducks", name: "Ducks Flying Over", weight: 1.4, group: 3...5, shark: false, build: flyingDuck, fun: nil),
        RosterEntry(key: "egret", name: "Great Egret", weight: 1.2, group: 1...1, shark: false, build: egret, fun: nil),
        RosterEntry(key: "dragonfly", name: "Dragonfly", weight: 2.5, group: 1...2, shark: false, build: dragonfly, fun: nil),
        RosterEntry(key: "alligator", name: "Alligator", weight: 0.6, group: 1...1, shark: true, build: { alligator(king: false) },
                    fun: { alligator(king: true) }, peeks: true),
    ]

    static func bass() -> Species {
        let d = Species(key: "bass", name: "Largemouth Bass", blurb: "Louisiana's favourite. Big mouth, bigger appetite.", accent: 0x5E7A34)
        d.speed = 0.9; d.wag = 6; d.depth = (0.15, 0.7)
        let green = C(0x6E8A3A), dark = C(0x2F3E1C), belly = C(0xE8E2C0), pale = C(0xA8B86E)
        Builtins.loft(d, 17, 3.0, 1.8, a: 0.06, b: 0.95, p: 0.55) { t, _, y, h, _ in
            let fy = Float(y)
            if fy < -h * 0.35 { return belly }
            if abs(fy) < 0.9 && t > 0.12 && t < 0.88 && vnoise(t * 12, 0, 0, 3) > 0.35 { return dark }
            return fy > h * 0.55 ? dark : green
        }
        Builtins.fin(d, 0.35, 0.8, up: true, height: { 1 + 2 * sin($0 * .pi) }) { _, _, _ in dark }
        Builtins.fin(d, 0.2, 0.4, up: false, height: { _ in 1 }) { _, _, _ in green }
        Builtins.pectoral(d, 12, -1, pale)
        Builtins.tailFan(d, 4, span: { (-1 - $0 * 2.4, 1 + $0 * 2.4) }) { _, _ in green }
        Builtins.eye(d, 15, 1)
        for x in -1...1 { d.body.set(x, -1, 16, C(0x2A2018)) }
        return d
    }

    static func bluegill() -> Species {
        let d = Species(key: "bluegill", name: "Bluegill", blurb: "Round, bold and always in a little gang.", accent: 0x6E8A4A)
        d.voxelSize = 0.055; d.speed = 1; d.wag = 9; d.depth = (0.2, 0.8); d.schooling = true; d.crowd = 0.5
        let olive = C(0x6E8A4A), bar = C(0x4E6A34), blue = C(0x4A6E9A), breast = C(0xF29A3A), black = C(0x15151B)
        Builtins.loft(d, 11, 3.4, 1.2, a: 0.1, b: 0.92, p: 0.5) { t, _, y, h, _ in
            let fy = Float(y)
            if sq((t - 0.78) / 0.07) + sq((fy - 0.4) / 0.9) < 1 { return black }
            if fy < -h * 0.3 && t > 0.4 { return breast }
            if t > 0.75 && fy < h * 0.2 { return blue }
            return sin(t * 32) > 0.55 ? bar : olive
        }
        Builtins.fin(d, 0.15, 0.7, up: true, height: { _ in 1.6 }) { _, _, _ in bar }
        Builtins.fin(d, 0.15, 0.45, up: false, height: { _ in 1.2 }) { _, _, _ in bar }
        Builtins.pectoral(d, 7, -1, olive)
        Builtins.tailFan(d, 3, span: { (-1 - $0 * 2.6, 1 + $0 * 2.6) }) { _, _ in olive }
        Builtins.eye(d, 9, 1)
        return d
    }

    static func redfish() -> Species {
        let d = Species(key: "redfish", name: "Redfish", blurb: "Copper-bronze, with a spot on its tail to fool anyone chasing.", accent: 0xC8743A)
        d.speed = 1; d.wag = 6; d.depth = (0.1, 0.6)
        let copper = C(0xC8743A), top = C(0x8A4A2A), belly = C(0xF0D8B8)
        Builtins.loft(d, 16, 2.8, 1.7, a: 0.06, b: 0.95, p: 0.55) { _, _, y, h, _ in
            Float(y) < -h * 0.35 ? belly : Float(y) > h * 0.5 ? top : copper
        }
        Builtins.fin(d, 0.3, 0.75, up: true, height: { 1 + 1.5 * sin($0 * .pi) }) { _, _, _ in top }
        Builtins.fin(d, 0.2, 0.35, up: false, height: { _ in 1 }) { _, _, _ in copper }
        Builtins.pectoral(d, 11, -1, copper)
        Builtins.tailFan(d, 4, span: { (-1 - $0 * 2, 1 + $0 * 2) }) { u, y in u < 0.5 && (y == 0 || y == 1) ? C(0x15151B) : copper }
        Builtins.eye(d, 14, 1)
        return d
    }

    /// Fills a box whatever order its corners come in.
    static func box(_ m: VoxelModel, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ c: VoxelColor) {
        Builtins.fill(m, min(x0, x1)...max(x0, x1), min(y0, y1)...max(y0, y1), min(z0, z1)...max(z0, z1), c)
    }

    /// A ring of beads around a body at a z: purple, green and gold.
    static func beads(_ m: VoxelModel, z: Int, center: SIMD2<Float>, radius: SIMD2<Float>) {
        let colors: [UInt32] = [0x7B2D8E, 0x2E9A45, 0xF2C230]
        let n = Int((radius.x + radius.y) * 3.2)
        for k in 0..<n {
            let a = Float(k) / Float(n) * 2 * .pi
            let x = Int((center.x + cos(a) * radius.x).rounded()), y = Int((center.y + sin(a) * radius.y).rounded())
            m.set(x, y, z, C(colors[k % 3], 70))
        }
    }

    static func crawfish(mardiGras: Bool) -> Species {
        let d = Species(key: "crawfish", name: mardiGras ? "Crawfish (Mardi Gras)" : "Crawfish",
                        blurb: mardiGras ? "Laissez les bons temps rouler! Beads, mask, the works." : "Walks the mud backwards and forwards, claws up.",
                        accent: 0xB8321E)
        d.voxelSize = 0.06; d.speed = 0.3; d.wag = 6; d.motion = .walk; d.depth = (0, 0.02); d.crowd = 0.5
        let red = C(0xB8321E), dark = C(0x7A1E12), light = C(0xE0603A)
        Builtins.ellipsoid(d.body, SIMD3(0, 2, 10), SIMD3(2.3, 1.8, 3.6)) { _, y, z in y < 1 ? light : z % 2 == 0 ? red : dark }
        for z in 0..<7 {
            let w = 1 + z / 3
            box(d.body, -w, w, 1, 2, z, z, z % 2 == 0 ? red : dark)
        }
        box(d.body, -3, 3, 1, 1, -2, -1, red)
        for s in [-1, 1] {
            for i in 0..<4 { d.body.set(s * (2 + i / 2), 2, 13 + i, red) }
            box(d.body, s * 3, s * 5, 1, 3, 17, 20, red)
            box(d.body, s * 3, s * 3, 2, 2, 21, 22, dark)
            box(d.body, s * 5, s * 5, 2, 2, 21, 22, dark)
            for z in [7, 9, 11] { d.body.set(s * 3, 1, z, dark); d.body.set(s * 3, 0, z, dark); d.body.set(s * 4, -1, z, dark) }
            d.body.set(s, 4, 14, C(0x0A0A0E))
            for i in 0..<9 { d.body.set(s * (1 + i / 3), 3 + i / 4, 14 + i, dark) }
        }
        if mardiGras {
            beads(d.body, z: 12, center: SIMD2(0, 2), radius: SIMD2(2.8, 2.4))
            beads(d.body, z: 11, center: SIMD2(0, 1.6), radius: SIMD2(2.6, 2.2))
            for s in [-1, 1] { box(d.body, s, s * 2, 4, 5, 14, 14, C(0x7B2D8E)); d.body.set(s * 2, 5, 14, C(0xF2C230, 90)) }
            box(d.body, 0, 0, 4, 4, 14, 14, C(0x7B2D8E))
            for (i, c) in [0x7B2D8E, 0x2E9A45, 0xF2C230].enumerated() {
                for y in 5...7 { d.body.set(i - 1, y + (i == 1 ? 1 : 0), 11, C(UInt32(c))) }
            }
        }
        return d
    }

    static func gar() -> Species {
        let d = Species(key: "gar", name: "Alligator Gar", blurb: "An armoured fish older than the dinosaurs' grandparents.", accent: 0x5A6A3A)
        d.voxelSize = 0.07; d.speed = 0.65; d.turn = 1.2; d.wag = 4; d.wagAngle = 18; d.depth = (0.4, 0.85); d.crowd = 1.6
        let olive = C(0x5A6A3A), spot = C(0x2E3420), belly = C(0xD8D0A8), tooth = C(0xF0EEE0)
        Builtins.loft(d, 28, 1.8, 1.5, a: 0.03, b: 0.95, p: 0.35, wp: 0.35) { t, x, y, h, _ in
            if Float(y) < -h * 0.35 { return belly }
            return vhash(x, y, Int(t * 80), 61) < 0.22 || (t < 0.25 && vhash(x, y, Int(t * 80), 62) < 0.4) ? spot : olive
        }
        for z in 28..<36 {
            d.body.set(0, 0, z, olive)
            d.body.set(0, -1, z, belly)
            if z % 2 == 0 { for s in [-1, 1] { d.body.set(s, -1, z, tooth) } }
        }
        Builtins.fin(d, 0.08, 0.2, up: true, height: { _ in 2 }) { _, _, _ in spot }
        Builtins.fin(d, 0.08, 0.22, up: false, height: { _ in 2 }) { _, _, _ in spot }
        Builtins.pectoral(d, 22, -1, olive)
        Builtins.tailFan(d, 4, span: { (-1 - $0 * 1.6, 1 + $0 * 1.8) }) { u, _ in u > 0.5 ? spot : olive }
        Builtins.eye(d, 27, 1)
        return d
    }

    static func snapper() -> Species {
        let d = Species(key: "snapper", name: "Snapping Turtle", blurb: "Spiky, grumpy-looking, and very slow about it.", accent: 0x4A4430)
        d.speed = 0.35; d.turn = 0.9; d.wag = 2; d.wagAngle = 14; d.depth = (0.05, 0.5); d.crowd = 1.6
        let shell = [C(0x4A4430), C(0x56503A), C(0x3E3A28)], keel = C(0x2E2A1E), skin = C(0x6A6440), belly = C(0xC8B888)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 7), SIMD3(5, 3, 7)) { x, y, z in
            if y < 0 { return y == -1 ? belly : nil }
            return shell[Int(vhash(x / 3, y, z / 3, 8) * 3)]
        }
        for z in stride(from: 1, through: 13, by: 3) {
            for x in [-3, 0, 3] { if let t = d.body.top(x: x, z: z) { d.body.set(x, t + 1, z, keel) } }
        }
        Builtins.ellipsoid(d.body, SIMD3(0, 0.5, 16), SIMD3(2.4, 2, 2.6)) { x, y, z in vhash(x, y, z, 9) < 0.2 ? keel : skin }
        d.body.set(0, 0, 19, keel)
        d.body.set(0, -1, 19, keel)
        for s in [-1, 1] {
            d.body.set(s * 2, 1, 17, C(0xC8A030))
            box(d.body, s * 5, s * 7, -1, -1, 11, 12, skin)
            box(d.body, s * 4, s * 6, -1, -1, 1, 2, skin)
        }
        for i in 0..<8 {
            d.tail.set(0, 0, -i, skin)
            if i % 2 == 0 { d.tail.set(0, 1, -i, keel) }
        }
        return d
    }

    static func bullfrog(prince: Bool) -> Species {
        let d = Species(key: "bullfrog", name: prince ? "Frog Prince" : "Bullfrog",
                        blurb: prince ? "Wears the crown. Still waiting on that kiss." : "Kicks along like it's late for something.",
                        accent: 0x5E8A3A)
        d.voxelSize = 0.055; d.speed = 0.7; d.wag = 2.2; d.wagAngle = 22; d.depth = (0.3, 0.9); d.flukes = true
        let green = C(0x5E8A3A), spot = C(0x3E5E2A), belly = C(0xE8E0B0), gold = C(0xE0B040)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 6), SIMD3(3.4, 2.2, 5)) { x, y, z in
            if y < -1 { return belly }
            return vhash(x, y, z, 21) < 0.2 ? spot : green
        }
        for s in [-1, 1] {
            d.body.set(s * 2, 2, 9, gold)
            d.body.set(s * 2, 3, 9, gold)
            d.body.set(s * 2, 3, 10, C(0x0A0A0E))
            d.body.set(s * 3, 1, 7, C(0x6E5A34))
            box(d.body, s * 3, s * 4, -2, -3, 8, 9, green)
        }
        for x in -2...2 { d.body.set(x, -1, 11, C(0x3A4A22)) }
        // The back legs are the "tail": long, stretched out behind, webbed feet.
        for s in [-1, 1] {
            for i in 0..<7 { d.tail.set(s * (2 + i / 3), 0, -i, green) }
            box(d.tail, s * 3, s * 6, 0, 0, -8, -7, C(0x4E7A30))
        }
        if prince {
            let crown = C(0xF2C230, 70)
            for k in 0..<12 {
                let a = Float(k) / 12 * 2 * .pi
                let x = Int((cos(a) * 1.8).rounded()), z = 7 + Int((sin(a) * 1.8).rounded())
                d.body.set(x, 3, z, crown)
                if k % 3 == 0 { d.body.set(x, 4, z, crown) }
            }
            d.body.set(0, 4, 9, C(0xD8243A, 120))
        }
        return d
    }

    static func cottonmouth() -> Species {
        let d = Species(key: "cottonmouth", name: "Cottonmouth", blurb: "Swims with its head held high. Best admired from a distance.", accent: 0x4A4030)
        d.voxelSize = 0.05; d.speed = 0.6; d.turn = 1.6; d.wag = 3; d.wagAngle = 30; d.depth = (0.65, 0.95); d.crowd = 1
        let brown = C(0x4A4030), band = C(0x2A2418), belly = C(0x8A7A5A)
        Builtins.loft(d, 16, 1.2, 1.3, a: 0.02, b: 0.9, p: 0.2, wp: 0.2) { t, _, y, h, _ in
            Float(y) < -h * 0.4 ? belly : sin(t * 34) > 0.4 ? band : brown
        }
        Builtins.ellipsoid(d.body, SIMD3(0, 0.3, 17), SIMD3(1.8, 1.2, 2.2)) { _, y, _ in y < 0 ? belly : brown }
        for s in [-1, 1] { d.body.set(s * 2, 1, 18, C(0xC8A030)) }
        for z in 18...19 { d.body.set(0, -1, z, C(0xF4F0E0, 40)) }
        // A long body behind, which swishes side to side.
        for i in 0..<24 {
            let r = i < 16 ? 1 : 0
            for x in -r...r { for y in -r...r where abs(x) + abs(y) <= r { d.tail.set(x, y, -i, (i / 3) % 2 == 0 ? brown : band) } }
        }
        return d
    }

    static func nutria() -> Species {
        let d = Species(key: "nutria", name: "Nutria", blurb: "Paddles along the top, flashing its orange teeth.", accent: 0x6E5238)
        d.voxelSize = 0.06; d.speed = 0.5; d.turn = 1.4; d.wag = 3; d.wagAngle = 18; d.depth = (0.82, 0.96); d.crowd = 1.1
        let fur = C(0x6E5238), top = C(0x5A4230), light = C(0x8A6E50)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 6), SIMD3(2.8, 2.3, 5)) { _, y, _ in y > 1 ? top : y < -1 ? light : fur }
        Builtins.ellipsoid(d.body, SIMD3(0, 0.8, 12), SIMD3(2, 1.8, 2.4)) { _, _, _ in fur }
        for s in [-1, 1] {
            d.body.set(s * 2, 2, 13, C(0x0A0A0E))
            d.body.set(s * 2, 3, 11, top)
            for i in 0..<3 { d.body.set(s * (2 + i), 0, 14, C(0xE8E0D0)) }
            box(d.body, s * 2, s * 3, -2, -3, 9, 9, top)
            box(d.body, s * 2, s * 3, -2, -3, 2, 3, top)
        }
        d.body.set(0, 1, 15, C(0x2A2018))
        d.body.set(0, -1, 14, C(0xF07A1A))
        d.body.set(0, -2, 14, C(0xF07A1A))
        for i in 0..<10 { d.tail.set(0, -i / 4, -i, C(0x4A403A)) }
        return d
    }

    static func alligator(king: Bool) -> Species {
        let d = Species(key: "alligator", name: king ? "King Gator" : "Alligator",
                        blurb: king ? "Rex of the bayou, crowned for Mardi Gras." : "Glides by with just a little smile. Everyone gives it room.",
                        accent: 0x3E4A2A)
        d.voxelSize = 0.08; d.speed = 0.75; d.turn = 1.1; d.wag = 2.5; d.wagAngle = 20; d.depth = (0.5, 0.88)
        d.scary = true; d.cruiser = true; d.crowd = 3
        let top = C(king ? 0x3E5A2A : 0x3E4A2A), scute = C(0x2A3220), belly = C(0xD8D0A0), tooth = C(0xF4F0E4)
        Builtins.loft(d, 24, 2.0, 3.0, a: 0.05, b: 0.9, p: 0.35, wp: 0.4) { _, x, y, h, _ in
            if Float(y) < -h * 0.4 { return belly }
            return Float(y) >= h * 0.4 && (x + y) % 3 == 0 ? scute : top
        }
        for z in 24..<36 {
            let w = max(1, 2 - (z - 24) / 7)
            box(d.body, -w, w, 0, 0, z, z, top)
            box(d.body, -w, w, -1, -1, z, z, belly)
            if z % 2 == 0 && z > 26 { for s in [-1, 1] { d.body.set(s * (w + 1), -1, z, tooth) } }
        }
        for s in [-1, 1] {
            d.body.set(s * 2, 1, 26, C(0xE0D040))
            d.body.set(s * 2, 2, 26, top)
            d.body.set(s, 1, 35, scute)
            for (z, len) in [(18, 4), (4, 4)] {
                box(d.body, s * 3, s * (3 + len), -1, -1, z, z + 1, top)
                box(d.body, s * (3 + len), s * (3 + len), -2, -2, z - 1, z + 2, top)
            }
        }
        for i in 0..<18 {
            let h = max(0, 1 - i / 9), w = max(0, 2 - i / 6)
            box(d.tail, -w, w, -h, h, -i, -i, top)
            if i % 2 == 0 { d.tail.set(0, h + 1, -i, scute) }
        }
        if king {
            let gold = C(0xF2C230, 80)
            for x in -2...2 { for z in 26...28 where abs(x) == 2 || z != 27 { d.body.set(x, 3, z, gold) } }
            for (x, z) in [(-2, 26), (2, 26), (0, 26), (-2, 28), (2, 28), (0, 28)] { d.body.set(x, 4, z, gold) }
            d.body.set(0, 4, 26, C(0x7B2D8E, 120))
            d.body.set(0, 4, 28, C(0x2E9A45, 120))
            beads(d.body, z: 23, center: SIMD2(0, 0), radius: SIMD2(3.4, 2.4))
            beads(d.body, z: 22, center: SIMD2(0, -0.3), radius: SIMD2(3.4, 2.4))
        }
        return d
    }

    // MARK: Above the water

    /// A duck's body, sat on the water: shared by the mallard, the wood duck and the rubber duck.
    private static func duckBody(_ d: Species, body: (Int, Int, Int) -> VoxelColor, head: (Int, Int, Int) -> VoxelColor,
                                 bill: UInt32, eye: UInt32 = 0x0A0A0E) {
        Builtins.ellipsoid(d.body, SIMD3(0, 2, 5), SIMD3(2.6, 2, 4.4)) { x, y, z in body(x, y, z) }
        Builtins.ellipsoid(d.body, SIMD3(0, 5, 9), SIMD3(1.6, 1.8, 1.8)) { x, y, z in head(x, y, z) }
        box(d.body, -1, 1, 4, 4, 11, 12, C(bill))
        box(d.body, -1, 1, 5, 5, 11, 11, C(bill))
        for s in [-1, 1] { d.body.set(s * 2, 6, 10, C(eye)) }
        d.length = 12
    }

    static func mallard(rubber: Bool) -> Species {
        let d = Species(key: "mallard", name: rubber ? "Rubber Ducky" : "Mallard",
                        blurb: rubber ? "Squeaks if you tap it. (It doesn't. But it would.)" : "Paddles about on top of the water, very busy.",
                        accent: rubber ? 0xF6D23A : 0x1E6A3A)
        d.voxelSize = 0.065; d.speed = 0.35; d.wag = 3; d.wagAngle = 12; d.motion = .walk; d.floats = true; d.depth = (0.47, 0.47)
        d.crowd = 0.7
        if rubber {
            let yellow = C(0xF6D23A), shine = C(0xFFF0A0, 60)
            duckBody(d, body: { x, y, z in y > 3 && x == 1 && z % 3 == 0 ? shine : yellow }, head: { _, _, _ in yellow }, bill: 0xF28A1E)
            for i in 0..<3 { d.tail.set(0, 2 + i, -i, yellow) }
        } else {
            let grey = C(0xA8A8A0), chest = C(0x7A3E22), green = C(0x1E6A3A), ring = C(0xF4F4F0), dark = C(0x2A2A2A), wing = C(0x8A7A62)
            duckBody(d, body: { x, y, z in
                if z > 7 && y < 3 { return chest }
                if y > 2 && abs(x) >= 2 { return wing }
                return grey
            }, head: { _, y, _ in y < 4 ? ring : green }, bill: 0xE8C23A)
            for s in [-1, 1] { d.body.set(s * 2, 3, 3, C(0x2E5FC8)) }
            for i in 0..<3 { d.tail.set(0, 2 + i / 2, -i, i == 2 ? dark : C(0xF4F4F0)) }
            d.tail.set(0, 4, -1, dark)
        }
        return d
    }

    static func woodDuck() -> Species {
        let d = Species(key: "woodduck", name: "Wood Duck", blurb: "The fanciest duck on the bayou, and it knows it.", accent: 0x2E7A5A)
        d.voxelSize = 0.065; d.speed = 0.4; d.wag = 3; d.wagAngle = 12; d.motion = .walk; d.floats = true; d.depth = (0.47, 0.47)
        d.crowd = 0.7
        let side = C(0xD8B888), chest = C(0x7A2E2E), dot = C(0xF4F0E8), back = C(0x3A3A4A), green = C(0x1E6A4A), purple = C(0x5A3A7A)
        duckBody(d, body: { x, y, z in
            if z > 7 && y < 3 { return (x + y + z) % 3 == 0 ? dot : chest }
            if y > 2 { return back }
            return side
        }, head: { x, y, z in
            if y == 5 && abs(x) >= 1 && z < 10 { return dot }
            return y > 5 ? green : z < 9 ? purple : green
        }, bill: 0xD8402A, eye: 0xD8243A)
        for i in 0..<4 { d.tail.set(0, 2 + i / 2, -i, back) }
        for i in 0..<3 { d.body.set(0, 7, 9 - i, green) }
        return d
    }

    /// A mallard in flight, for the little groups that fly over the swamp.
    static func flyingDuck() -> Species {
        let d = Species(key: "flyingducks", name: "Ducks Flying Over", blurb: "Off somewhere in a hurry, in a wobbly line.", accent: 0x1E6A3A)
        d.voxelSize = 0.04; d.speed = 1.5; d.turn = 1.6; d.wag = 2; d.wagAngle = 6; d.flies = true; d.schooling = true
        d.depth = (0.3, 0.9); d.crowd = 0.5; d.flap = 4.5; d.flapAngle = 40
        let grey = C(0xA8A8A0), chest = C(0x7A3E22), green = C(0x1E6A3A), ring = C(0xF4F4F0)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 5), SIMD3(2, 1.8, 4.2)) { _, y, z in z > 7 && y < 1 ? chest : grey }
        Builtins.fill(d.body, 0...0, 0...0, 9...10, ring)
        Builtins.ellipsoid(d.body, SIMD3(0, 0.5, 12), SIMD3(1.3, 1.3, 1.5)) { _, _, _ in green }
        Builtins.fill(d.body, 0...0, 0...0, 14...15, C(0xE8C23A))
        d.length = 15
        for i in 0..<3 { d.tail.set(0, 0, -i, ring) }
        d.wings = Rainforest.wing(9, 5) { u in u > 0.35 && u < 0.5 ? 0x2E5FC8 : 0x8A7A62 }
        d.wingJoint = SIMD3(1.5, 0.5, 6)
        return d
    }

    static func egret() -> Species {
        let d = Species(key: "egret", name: "Great Egret", blurb: "Glides over slow and white, legs trailing behind.", accent: 0xF4F4EE)
        d.voxelSize = 0.045; d.speed = 0.9; d.turn = 1.2; d.wag = 1; d.wagAngle = 4; d.flies = true; d.depth = (0.4, 0.9)
        d.crowd = 1; d.flap = 1.8; d.flapAngle = 32
        let white = C(0xF4F4EE)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 5), SIMD3(1.8, 1.8, 4.5)) { _, _, _ in white }
        // An S-shaped neck tucked back, then the head and a long yellow bill.
        for (y, z) in [(1, 9), (2, 10), (2, 11), (1, 12), (1, 13)] { d.body.set(0, y, z, white) }
        Builtins.ellipsoid(d.body, SIMD3(0, 1.5, 14.5), SIMD3(1, 1, 1.4)) { _, _, _ in white }
        Builtins.fill(d.body, 0...0, 1...1, 16...20, C(0xE8C23A))
        for s in [-1, 1] { d.body.set(s, 2, 15, C(0x0A0A0E)) }
        d.length = 20
        for i in 0..<9 { for s in [-1, 1] { d.tail.set(s, -1, -i, C(0x1A1A1A)) } }
        d.wings = Rainforest.wing(13, 7) { u in u > 0.85 ? 0xE8E8E0 : 0xF4F4EE }
        d.wingJoint = SIMD3(1.5, 1, 6)
        return d
    }

    static func dragonfly() -> Species {
        let d = Species(key: "dragonfly", name: "Dragonfly", blurb: "Zips over the water, stops dead in mid-air, zips off again.", accent: 0x2E9AC8)
        d.voxelSize = 0.03; d.speed = 1.4; d.turn = 4; d.wag = 2; d.wagAngle = 4; d.flies = true; d.depth = (0, 0.5); d.crowd = 0.3
        d.flap = 16; d.flapAngle = 25
        let blue = C(0x2E9AC8, 40), dark = C(0x1E3A5A)
        Builtins.fill(d.body, 0...0, 0...0, 0...12, blue)
        for z in stride(from: 1, through: 9, by: 2) { d.body.set(0, 0, z, dark) }
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 14), SIMD3(1.4, 1, 1.2)) { x, _, _ in x == 0 ? blue : C(0x3E7A3A) }
        d.length = 15
        let w = VoxelModel()
        for x in 1...9 { for z in [-1, 0, 2, 3] where !(x > 7 && (z == -1 || z == 3)) { w.set(x, 0, z, C(0xD8F0F4, 60)) } }
        d.wings = w
        d.wingJoint = SIMD3(0.5, 0.5, 11)
        return d
    }

    static func sq(_ v: Float) -> Float { v * v }
}
