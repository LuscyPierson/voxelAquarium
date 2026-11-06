import SceneKit
import simd

/// A rainforest floor in the rain: giant buttressed trunks, hanging vines, ferns, flowers and mushrooms,
/// a branch across the top for sloths and monkeys, and macaws, toucans, hummingbirds, morphos, frogs,
/// capybaras, a boa and, once in a while, a jaguar.
enum Rainforest {
    /// The branch along the top of the view, which hangers travel along: its top at a world x, and its depth.
    static let branchZ: Float = 0.9
    static func branchY(_ x: Float) -> Float { 5.75 + 0.18 * sin(x * 0.21 + 0.6) + 0.08 * sin(x * 0.57) }
    /// A river along the front of the floor: its surface, where the bank behind it starts, and how high the bank stands.
    static let riverLevel: Float = 1.85, bankEdge: Float = 2.0, bankRise: Float = 1.6

    @MainActor
    static func build(into root: SCNNode) -> TankDecor.Built {
        var rng = SeededRandom(seed: 23)
        TankDecor.place(root, "Farthest Ridge", TankDecor.ridge(seed: 267, width: 60, height: 14, colors: [0x6E9A6A, 0x689464, 0x74A070],
                                                               kelp: 0x5E8A5A, kelpChance: 0.12, detail: 2),
                        size: 0.3, at: SIMD3(0, -1.5, 19)).castsShadow = false
        for (x, z, r, s) in [(-12.0, 17.0, 6, 0.3), (6.0, 18.0, 7, 0.3), (-3.0, 12.0, 6, 0.2)] as [(Float, Float, Int, Float)] {
            TankDecor.place(root, "Trunk", trunk(&rng, radius: r, height: Int(16 / s), far: z > 12), size: s,
                            at: SIMD3(x, z > 12 ? -0.8 : -0.3, z)).castsShadow = false
        }
        TankDecor.place(root, "Near Ridge", TankDecor.ridge(seed: 273, width: 62, height: 5, colors: [0x3E6A30, 0x36622A, 0x467236],
                                                           kelp: 0x4E8A3A, kelpChance: 0.08, detail: 2),
                        size: 0.175, at: SIMD3(0, 0.1, 6.5)).castsShadow = false
        for (x, z) in [(10.2, 3.3)] as [(Float, Float)] {
            TankDecor.place(root, "Trunk", trunk(&rng, radius: 7, height: 75, far: false), size: 0.1, at: SIMD3(x, TankDecor.floor(x, z) - 0.2, z))
        }

        // The branch across the top, mossy, with bromeliads sitting on it.
        TankDecor.place(root, "Branch", branch(), size: 0.06, at: SIMD3(0, 0, branchZ))

        // The river: water along the front, stones and water grass on its bed.
        TankDecor.addWater(root, level: riverLevel, back: bankEdge + 0.05, color: 0x2E5A4A)
        for (x, z) in [(-9.0, -0.6), (3.5, 0.2), (11.0, -1.0)] as [(Float, Float)] {
            TankDecor.place(root, "Rock", TankDecor.rock(&rng, 10, 6, 8), size: 0.06, at: SIMD3(x, TankDecor.floor(x, z) - 0.1, z))
        }

        // The bank: ferns, heliconia, mushrooms, a rock or two.
        var spots: [SIMD2<Float>] = []
        var tries = 0
        while spots.count < 13 && tries < 400 {
            tries += 1
            let p = SIMD2(Float(rng.next(3000)) / 100 - 15, bankEdge + 0.3 + Float(rng.next(110)) / 100)
            if spots.contains(where: { simd_distance($0, p) < 1.6 }) { continue }
            spots.append(p)
            let model: VoxelModel
            switch rng.next(6) {
            case 0, 1: model = fern(&rng)
            case 2: model = heliconia(&rng)
            case 3: model = mushrooms(&rng)
            case 4: model = bromeliad(&rng)
            default: model = TankDecor.rock(&rng, 8, 5, 7)
            }
            TankDecor.place(root, "Plant", model, size: 0.05, at: SIMD3(p.x, TankDecor.floor(p.x, p.y) - 0.02, p.y))
        }

        // Vines hanging from the branch, swaying.
        var vines: [Seaweed] = []
        for i in 0..<7 {
            let x = Float(i) * 4.6 - 14 + Float(rng.next(80)) / 100
            vines.append(Seaweed(root: root, at: SIMD3(x, branchY(x) - 0.1, branchZ + 0.1), segments: 4 + rng.next(8), seed: i,
                                 colors: [0x4E8A3A, 0x3E7A2E, 0x5E9A44, 0x6AA84A], hanging: true))
        }
        for i in 0..<9 {
            let x = Float(i) * 3.4 - 14 + Float(rng.next(80)) / 100, z = Float(rng.next(300)) / 100 - 1.5
            vines.append(Seaweed(root: root, at: SIMD3(x, TankDecor.floor(x, z), z), segments: 2 + rng.next(2), seed: 20 + i,
                                 colors: [0x3E7A4A, 0x4E8A52, 0x5E9A5A, 0x2E6A3E]))
        }
        return TankDecor.Built(chests: [], seaweed: vines, vent: nil, water: (riverLevel, bankEdge + 0.05))
    }

    // MARK: - Scenery

    /// A rainforest giant: buttress roots fanning out at the bottom, a straight trunk up out of sight.
    static func trunk(_ rng: inout SeededRandom, radius: Int, height: Int, far: Bool) -> VoxelModel {
        let m = VoxelModel()
        let seed = rng.next(1000)
        let bark: [UInt32] = far ? [0x5A7A56, 0x547452, 0x60805C] : [0x6A5640, 0x5E4A36, 0x76624A, 0x564434]
        let r0 = Float(radius)
        for y in 0..<height {
            let r = r0 + vnoise(0, Float(y) * 0.15, 0, seed) * 1.0
            let buttress = max(0, 1 - Float(y) / (r0 * 2.5))
            let ri = Int((r * (1 + buttress * 2.4)).rounded(.up))
            for x in -ri...ri {
                for z in -ri...ri {
                    let a = atan2(Float(z), Float(x))
                    // Buttresses: thin fins out in five directions.
                    let fin = pow(max(0, cos(a * 5 + Float(seed))), 18) * buttress * r * 2.4
                    let d = (sq(Float(x)) + sq(Float(z))).squareRoot()
                    if d > r + fin || d < r + fin - 2.5 { continue }
                    let moss = !far && vnoise(Float(x) * 0.3, Float(y) * 0.1, Float(z) * 0.3, seed + 2) > 0.62
                    m.set(x, y, z, C(moss ? 0x5E9A3A : bark[Int(vhash(x, y, z, seed + 1) * Float(bark.count))]))
                }
            }
        }
        return m
    }

    /// The long branch along the top of the view, following `branchY`, with moss and bromeliads.
    static func branch() -> VoxelModel {
        let m = VoxelModel()
        let s: Float = 0.06
        for x in -340...340 {
            let topY = Int((branchY(Float(x) * s) / s).rounded())
            for y in (topY - 4)...topY {
                for z in -3...3 where sq(Float(y - topY + 2)) + sq(Float(z)) <= 7 {
                    let moss = y >= topY - 1 && vhash(x, y, z, 31) < 0.55
                    m.set(x, y, z, C(moss ? (vhash(x, y, z, 32) < 0.5 ? 0x5E9A3A : 0x7AB84A) : vhash(x, y, z, 33) < 0.5 ? 0x5E4632 : 0x6A5038))
                }
            }
            if vhash(x / 9, 0, 0, 34) < 0.06 && x % 9 == 0 {
                let c: UInt32 = [0xE0303A, 0xF2A23A, 0xD8408A][Int(vhash(x, 1, 0, 34) * 3)]
                for k in 0..<5 { for i in 0..<4 { m.set(x + (k - 2) * (i / 2 + 1) / 2, topY + 1 + i, (k % 2) - (k / 4), C(i == 3 && k == 2 ? c : 0x4E8A3A)) } }
                m.set(x, topY + 2, 0, C(c, 60))
            }
        }
        return m
    }

    static func fern(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        let green: UInt32 = [0x3E8A3A, 0x4E9A44, 0x2E7A30][rng.next(3)]
        for k in 0..<(5 + rng.next(3)) {
            let a = Float(k) / 6 * 2 * .pi + Float(rng.next(50)) / 100
            let len = 9 + rng.next(6)
            for i in 0..<len {
                let x = Int((cos(a) * Float(i)).rounded()), z = Int((sin(a) * Float(i)).rounded())
                let y = Int(Float(i) * 1.2 - sq(Float(i)) * 0.07)
                m.set(x, y, z, C(i == len - 1 ? TankDecor.lighter(green, 0.3) : green))
                if i > 1 && i < len - 1 && i % 2 == 0 {
                    m.set(x + Int((-sin(a)).rounded()), y, z + Int(cos(a).rounded()), C(TankDecor.lighter(green, 0.15)))
                    m.set(x - Int((-sin(a)).rounded()), y, z - Int(cos(a).rounded()), C(TankDecor.lighter(green, 0.15)))
                }
            }
        }
        return m
    }

    /// Heliconia: tall leaves and zig-zag red and yellow "lobster claw" flowers.
    static func heliconia(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        let h = 14 + rng.next(8)
        for y in 0..<h { m.set(0, y, 0, C(0x3E7A30)) }
        for i in 0..<6 {
            let side = i % 2 == 0 ? 1 : -1
            m.set(side, h + i, 0, C(0xE0302A))
            m.set(side * 2, h + i, 0, C(0xE0302A))
            m.set(side * 3, h + i + 1, 0, C(0xF2C23A, 60))
        }
        for k in [-1, 1] {
            for i in 0..<10 { m.set(k * (1 + i / 3), 4 + i, k, C(0x4E8A3A)); m.set(k * (2 + i / 3), 4 + i, k, C(0x5E9A44)) }
        }
        return m
    }

    static func mushrooms(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        for _ in 0..<(2 + rng.next(3)) {
            let cx = rng.next(9) - 4, cz = rng.next(9) - 4, h = 2 + rng.next(5), r = 2 + rng.next(2)
            let cap: UInt32 = [0xE0402A, 0xF29A3A, 0xE8D8B0][rng.next(3)]
            for y in 0..<h { m.set(cx, y, cz, C(0xF0E6D0)) }
            for x in -r...r {
                for z in -r...r where x * x + z * z <= r * r + 1 {
                    m.set(cx + x, h, cz + z, C(vhash(x, 0, z, cx) < 0.2 ? 0xFFFFFF : cap))
                    if x * x + z * z < r * r - 1 { m.set(cx + x, h + 1, cz + z, C(cap)) }
                }
            }
        }
        return m
    }

    static func bromeliad(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        let flower: UInt32 = [0xE0303A, 0xF2A23A, 0xD8408A, 0xF2D23A][rng.next(4)]
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi
            for i in 0..<6 {
                m.set(Int((cos(a) * Float(i) * 0.6).rounded()), i, Int((sin(a) * Float(i) * 0.6).rounded()), C(i > 3 ? 0x6AA84A : 0x4E8A3A))
            }
        }
        for y in 0..<4 { m.set(0, 4 + y, 0, C(flower, y == 3 ? 80 : 0)) }
        return m
    }

    /// A fallen, moss-covered log along the back, with mushrooms and ferns sprouting on top.
    static func log() -> VoxelModel {
        let m = VoxelModel()
        let bark: [UInt32] = [0x5A4430, 0x4E3A28, 0x664E36]
        for x in -168...168 {
            let h = OceanLife.reefHeight(x)
            for z in 0..<5 {
                let hz = h - (4 - z) * (1 + Int(vhash(x, z, 0, 242) * 2))
                for y in 0..<max(1, hz) {
                    let moss = y >= hz - 2 - Int(vnoise(Float(x) * 0.1, 0, Float(z), 243) * 3)
                    let crack = vnoise(Float(x) * 0.3, Float(y) * 0.05, Float(z), 246) > 0.8
                    m.set(x, y, z, C(moss ? 0x62A03E : crack ? 0x46321F : bark[Int(vhash(x, y, z, 244) * 3)]))
                }
            }
            if vhash(x, 0, 0, 245) < 0.015 {
                let cap: UInt32 = [0xE0402A, 0xF29A3A][Int(vhash(x, 1, 0, 245) * 2)]
                for y in 0..<2 { m.set(x, h + y, 2, C(0xF0E6D0)) }
                for dx in -2...2 { for dz in 1...3 { m.set(x + dx, h + 2, dz, C(cap)) } }
            } else if vhash(x, 3, 0, 245) < 0.03 {
                for i in 0..<6 { m.set(x + i / 2, h + i, 2, C(0x4E9A44)); m.set(x - i / 2, h + i, 3, C(0x3E8A3A)) }
            }
        }
        return m
    }

    // MARK: - Creatures

    @MainActor static let entries: [RosterEntry] = [
        RosterEntry(key: "morpho", name: "Blue Morpho", weight: 6, group: 2...4, shark: false, build: morpho, fun: nil),
        RosterEntry(key: "macaw", name: "Scarlet Macaw", weight: 5, group: 1...3, shark: false, build: { macaw(pirate: false) },
                    fun: { macaw(pirate: true) }),
        RosterEntry(key: "toucan", name: "Toucan", weight: 4, group: 1...2, shark: false, build: { toucan(banana: false) },
                    fun: { toucan(banana: true) }, peeks: true),
        RosterEntry(key: "hummingbird", name: "Hummingbird", weight: 4, group: 1...2, shark: false, build: hummingbird, fun: nil),
        RosterEntry(key: "dartfrog", name: "Poison Dart Frog", weight: 4, group: 1...3, shark: false,
                    build: { frog(key: "dartfrog", name: "Poison Dart Frog", blurb: "Tiny, bright blue, and says 'don't touch' in colour.",
                                  skin: 0x2E6BE0, spots: 0x0E0E14, eyes: 0x0E0E14, feet: 0x1E4AB0) }, fun: nil),
        RosterEntry(key: "treefrog", name: "Red-Eyed Tree Frog", weight: 3, group: 1...2, shark: false,
                    build: { frog(key: "treefrog", name: "Red-Eyed Tree Frog", blurb: "Big red eyes, orange toes, and a lot of hopping.",
                                  skin: 0x5EC83A, spots: 0x3E9AD8, eyes: 0xE0302A, feet: 0xF29A3A) }, fun: nil, peeks: true),
        RosterEntry(key: "capybara", name: "Capybara", weight: 2.5, group: 1...2, shark: false, build: { capybara(orange: false) },
                    fun: { capybara(orange: true) }, peeks: true),
        RosterEntry(key: "monkey", name: "Capuchin Monkey", weight: 2.2, group: 1...2, shark: false, build: monkey, fun: nil, peeks: true),
        RosterEntry(key: "sloth", name: "Sloth", weight: 1.6, group: 1...1, shark: false, build: { sloth(nightcap: false) },
                    fun: { sloth(nightcap: true) }),
        RosterEntry(key: "boa", name: "Emerald Boa", weight: 1.2, group: 1...1, shark: false, build: boa, fun: nil, peeks: true),
        RosterEntry(key: "tetra", name: "Neon Tetras", weight: 4, group: 6...10, shark: false, build: tetra, fun: nil),
        RosterEntry(key: "piranha", name: "Red-Bellied Piranha", weight: 3, group: 3...5, shark: false, build: piranha, fun: nil),
        RosterEntry(key: "arapaima", name: "Arapaima", weight: 1.2, group: 1...1, shark: false, build: arapaima, fun: nil),
        RosterEntry(key: "boto", name: "Pink River Dolphin", weight: 1, group: 1...2, shark: false, build: boto, fun: nil),
        RosterEntry(key: "jaguar", name: "Jaguar", weight: 0.6, group: 1...1, shark: true, build: { jaguar(sneakers: false) },
                    fun: { jaguar(sneakers: true) }, peeks: true),
    ]

    static func box(_ m: VoxelModel, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ c: VoxelColor) {
        Swamp.box(m, x0, x1, y0, y1, z0, z1, c)
    }

    /// A bird's right wing: `span` blocks out from the body, `chord` deep, coloured from the shoulder out.
    static func wing(_ span: Int, _ chord: Int, _ color: (Float) -> UInt32) -> VoxelModel {
        let m = VoxelModel()
        for x in 0..<span {
            let u = Float(x) / Float(span)
            let c = max(1, Int((Float(chord) * (1 - u * 0.55)).rounded()))
            for z in -(c - 1)...min(1, c - 1) { m.set(x + 1, 0, z, C(color(u))) }
        }
        return m
    }

    static func macaw(pirate: Bool) -> Species {
        let d = Species(key: "macaw", name: pirate ? "Pirate Parrot" : "Scarlet Macaw",
                        blurb: pirate ? "Says 'pieces of eight' to nobody in particular." : "Loud, bright and always in a hurry.", accent: 0xD8241E)
        d.voxelSize = 0.05; d.speed = 1.3; d.turn = 2.4; d.wag = 3; d.wagAngle = 8; d.depth = (0.45, 0.95)
        d.flap = 3.2; d.flapAngle = 42
        let red = C(0xD8241E), white = C(0xF4F0E8), beak = C(0xE8E0D0), black = C(0x1A1A1A)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 7), SIMD3(1.8, 2, 4)) { _, _, _ in red }
        Builtins.ellipsoid(d.body, SIMD3(0, 1.5, 11.5), SIMD3(1.7, 1.8, 1.8)) { _, _, _ in red }
        for s in [-1, 1] { box(d.body, s, s * 2, 1, 2, 12, 13, white); d.body.set(s * 2, 2, 12, black) }
        d.body.set(0, 2, 14, beak); d.body.set(0, 1, 14, beak); d.body.set(0, 1, 15, beak); d.body.set(0, 0, 15, beak); d.body.set(0, 0, 14, black)
        d.length = 14
        for i in 0..<14 {
            let c: UInt32 = i < 4 ? 0xD8241E : i < 10 ? 0x2E5FC8 : 0xD8241E
            for x in -(i < 8 ? 1 : 0)...(i < 8 ? 1 : 0) { d.tail.set(x, 0, -i, C(c)) }
        }
        d.wings = wing(10, 6) { u in u < 0.3 ? 0xD8241E : u < 0.5 ? 0xF2C230 : u < 0.62 ? 0x2E9A45 : 0x2E5FC8 }
        d.wingJoint = SIMD3(1.5, 1, 8)
        if pirate {
            box(d.body, 2, 2, 1, 3, 11, 13, black)
            box(d.body, -2, 2, 3, 3, 10, 13, black)
            box(d.body, -1, 1, 4, 4, 10, 13, black)
            d.body.set(0, 4, 13, C(0xFFFFFF, 100))
        }
        return d
    }

    static func toucan(banana: Bool) -> Species {
        let d = Species(key: "toucan", name: banana ? "Toucan (banana)" : "Toucan",
                        blurb: banana ? "Brings a snack everywhere. On its face." : "Mostly beak. Very proud of it.", accent: 0xF28A1E)
        d.voxelSize = 0.05; d.speed = 1; d.turn = 2; d.wag = 2; d.wagAngle = 8; d.depth = (0.4, 0.9)
        d.flap = 4.2; d.flapAngle = 36
        let black = C(0x15151B), throat = C(0xF6E27A), blue = C(0x3E8AD8), red = C(0xD8243A)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 6), SIMD3(2, 2.3, 4.5)) { _, y, z in z > 7 && y < 1 ? throat : black }
        Builtins.ellipsoid(d.body, SIMD3(0, 1.4, 10.5), SIMD3(1.8, 1.8, 1.8)) { _, y, _ in y < 1 ? throat : black }
        for s in [-1, 1] { d.body.set(s * 2, 2, 11, blue); d.body.set(s * 2, 2, 12, C(0x0A0A0E)) }
        for z in 12...20 {
            let h = z < 16 ? 2 : z < 19 ? 1 : 0
            for y in (1 - h / 2)...(1 + h) {
                let c: UInt32 = banana ? (z > 19 ? 0x5A4020 : 0xF6D84A) : z < 14 ? 0x6BB83A : z < 17 ? 0xF28A1E : z < 19 ? 0xF2C230 : 0xD8243A
                d.body.set(0, y, z, C(c))
                if z < 17 { d.body.set(1, y, z, C(c)); d.body.set(-1, y, z, C(c)) }
            }
        }
        if banana { d.body.set(0, 2, 12, C(0x5A4020)); d.body.set(0, 3, 12, C(0x5A4020)) }
        d.body.set(0, -2, 4, red)
        d.length = 20
        for i in 0..<8 { for x in -1...1 { d.tail.set(x, 0, -i, black) } }
        d.wings = wing(8, 6) { _ in 0x15151B }
        d.wingJoint = SIMD3(1.8, 1, 7)
        return d
    }

    static func hummingbird() -> Species {
        let d = Species(key: "hummingbird", name: "Hummingbird", blurb: "Zips, stops dead, zips again.", accent: 0x2EA866)
        d.voxelSize = 0.045; d.speed = 1.6; d.turn = 4; d.wag = 3; d.wagAngle = 10; d.depth = (0.2, 0.85); d.crowd = 0.4
        d.flap = 14; d.flapAngle = 55
        let green = C(0x2EA866), ruby = C(0xD8243A, 50), white = C(0xE8F0E0)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 4), SIMD3(1.6, 1.7, 3.5)) { _, y, z in y < -1 ? white : z > 5 && y < 0 ? ruby : green }
        Builtins.ellipsoid(d.body, SIMD3(0, 1, 8), SIMD3(1.3, 1.3, 1.4)) { _, _, _ in green }
        for s in [-1, 1] { d.body.set(s, 1, 9, C(0x0A0A0E)) }
        for z in 10...15 { d.body.set(0, 1, z, C(0x1A1A1A)) }
        d.length = 15
        for i in 0..<4 { for x in -1...1 { d.tail.set(x, 0, -i, C(0x1E7A4A)) } }
        d.wings = wing(7, 3) { _ in 0x6AB89A }
        d.wingJoint = SIMD3(1.2, 1, 5)
        return d
    }

    /// The blue morpho: huge, shimmering blue wings with black edges. It flutters about, bobbing as it goes.
    static func morpho() -> Species {
        let d = Species(key: "morpho", name: "Blue Morpho", blurb: "A flash of blue, then gone, then back again.", accent: 0x2E7BF0)
        d.voxelSize = 0.035; d.speed = 0.55; d.turn = 3; d.wag = 2; d.wagAngle = 4; d.depth = (0.3, 0.9); d.crowd = 0.4
        d.porpoise = true; d.flap = 2.6; d.flapAngle = 62
        let black = C(0x101018)
        Builtins.fill(d.body, 0...0, 0...0, 0...7, black)
        for s in [-1, 1] { for i in 0..<4 { d.body.set(s * (i / 2), 1 + i / 2, 8 + i, black) } }
        d.length = 8
        let w = VoxelModel()
        for x in 1...11 {
            for z in -6...6 {
                let fore = sq(Float(x - 6) / 6) + sq(Float(z - 2) / 4.5) <= 1
                let hind = sq(Float(x - 4) / 4.5) + sq(Float(z + 3) / 3.8) <= 1
                guard fore || hind else { continue }
                let edgeF = sq(Float(x - 6) / 5) + sq(Float(z - 2) / 3.5) > 1, edgeH = sq(Float(x - 4) / 3.6) + sq(Float(z + 3) / 2.9) > 1
                let edge = (fore && edgeF && !hind) || (hind && edgeH && !fore) || (fore && hind && edgeF && edgeH)
                let dot = edge && (x + z) % 3 == 0
                w.set(x, 0, z, dot ? C(0xF4F0E8) : edge ? black : C(x < 4 ? 0x1E5ED0 : 0x2E8BF8, 90))
            }
        }
        d.wings = w
        d.wingJoint = SIMD3(0, 0, 4)
        return d
    }

    static func frog(key: String, name: String, blurb: String, skin: UInt32, spots: UInt32, eyes: UInt32, feet: UInt32) -> Species {
        let d = Species(key: key, name: name, blurb: blurb, accent: skin)
        d.voxelSize = 0.05; d.speed = 0.45; d.wag = 4; d.motion = .walk; d.hops = true; d.depth = (0, 0.02); d.crowd = 0.4
        Builtins.ellipsoid(d.body, SIMD3(0, 3, 5), SIMD3(2.6, 2, 3.6)) { x, y, z in vhash(x, y, z, 71) < 0.22 ? C(spots) : C(skin) }
        for s in [-1, 1] {
            d.body.set(s * 2, 5, 7, C(eyes, 40)); d.body.set(s * 2, 5, 8, C(eyes, 40)); d.body.set(s * 2, 6, 7, C(eyes, 40))
            d.body.set(s * 3, 5, 8, C(0x0A0A0E))
            // Folded back legs and little front legs.
            box(d.body, s * 2, s * 4, 1, 2, 1, 3, C(skin))
            box(d.body, s * 3, s * 5, 0, 0, 2, 5, C(feet))
            box(d.body, s * 2, s * 2, 0, 1, 7, 7, C(skin))
            d.body.set(s * 3, 0, 8, C(feet))
        }
        return d
    }

    static func capybara(orange: Bool) -> Species {
        let d = Species(key: "capybara", name: orange ? "Capybara (with orange)" : "Capybara",
                        blurb: orange ? "Completely unbothered. There is an orange on its head." : "The calmest animal in the forest, and it knows it.",
                        accent: 0x9A6A3E)
        d.voxelSize = 0.055; d.speed = 0.3; d.wag = 3; d.motion = .walk; d.depth = (0, 0.02); d.crowd = 1.4
        let fur = C(0x9A6A3E), dark = C(0x7A5230), light = C(0xB08050)
        Builtins.ellipsoid(d.body, SIMD3(0, 6, 8), SIMD3(3.4, 3.4, 7)) { x, y, z in y > 8 ? dark : vhash(x, y, z, 72) < 0.15 ? light : fur }
        Builtins.ellipsoid(d.body, SIMD3(0, 7, 16), SIMD3(2.6, 2.8, 3.4)) { _, _, _ in fur }
        for s in [-1, 1] {
            d.body.set(s * 2, 10, 15, dark)
            d.body.set(s * 2, 8, 17, C(0x0A0A0E))
            for z in [3, 13] { box(d.body, s * 2, s * 2, 0, 3, z, z + 1, dark) }
        }
        box(d.body, -1, 1, 6, 7, 19, 19, dark)
        if orange {
            Builtins.ellipsoid(d.body, SIMD3(0, 11.5, 16), SIMD3(1.6, 1.4, 1.6)) { x, y, z in C(vhash(x, y, z, 73) < 0.3 ? 0xF29A2A : 0xF2862A, 30) }
            d.body.set(0, 13, 16, C(0x4E8A3A))
        }
        return d
    }

    /// Capuchin hanging from the branch by its arms, tail curled.
    static func monkey() -> Species {
        let d = Species(key: "monkey", name: "Capuchin Monkey", blurb: "Swings along the branch, hand over hand, very pleased with itself.", accent: 0x5A3A22)
        d.voxelSize = 0.05; d.speed = 0.9; d.wag = 3; d.wagAngle = 25; d.motion = .walk; d.hangs = true; d.depth = (1, 1); d.crowd = 1
        let fur = C(0x5A3A22), cream = C(0xF0DCC0), dark = C(0x2A1A10)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 6), SIMD3(2.4, 3.2, 2.4)) { _, _, _ in fur }
        Builtins.ellipsoid(d.body, SIMD3(0, 4.5, 7.5), SIMD3(2.2, 2, 2)) { _, y, z in y > 5 ? dark : z > 7 ? cream : fur }
        for s in [-1, 1] {
            d.body.set(s, 4, 9, C(0x0A0A0E))
            for y in 2...10 { d.body.set(s * 2, y, 6 + s * (y > 7 ? 1 : 0), fur) }
            box(d.body, s * 2, s * 2, -5, -3, 6, 6, fur)
        }
        d.length = 9
        for i in 0..<12 { d.tail.set(0, -i / 2, -i + (i > 8 ? (i - 8) * 2 : 0), fur) }
        return d
    }

    static func sloth(nightcap: Bool) -> Species {
        let d = Species(key: "sloth", name: nightcap ? "Sleepy Sloth" : "Sloth",
                        blurb: nightcap ? "Wore its nightcap to work. Again." : "Hangs about. Hangs about some more.", accent: 0x8A7458)
        d.voxelSize = 0.06; d.speed = 0.08; d.wag = 1; d.motion = .walk; d.hangs = true; d.depth = (1, 1); d.crowd = 1.2
        let fur = [C(0x8A7458), C(0x7A6A4E), C(0x7A8A58)], face = C(0xE8DCC0), mask = C(0x3A2A1E)
        Builtins.ellipsoid(d.body, SIMD3(0, 0, 6), SIMD3(2.6, 2.2, 5)) { x, y, z in fur[Int(vhash(x, y, z, 74) * 3)] }
        Builtins.ellipsoid(d.body, SIMD3(0, -0.5, 12), SIMD3(2, 1.8, 1.8)) { _, _, z in z > 12 ? face : fur[0] }
        for s in [-1, 1] {
            d.body.set(s, 0, 14, mask); d.body.set(s * 2, 0, 13, mask)
            for z in [3, 9] {
                for y in 1...5 { d.body.set(s * 2, y, z, fur[0]) }
                d.body.set(s * 2, 6, z, mask); d.body.set(s * 2, 6, z + 1, mask)
            }
        }
        d.body.set(0, -1, 14, mask)
        if nightcap {
            // A striped cap on top of its head, flopping forwards, with a bobble on the end.
            for i in 0..<5 {
                let r = 2 - i / 2
                for x in -r...r { for z in -r...r { d.body.set(x, 1 + i, 11 + i / 2 + z, C(i % 2 == 0 ? 0x3E6AC8 : 0xF4F0E8)) } }
            }
            d.body.set(0, 5, 15, C(0xFFFFFF, 60))
        }
        return d
    }

    static func boa() -> Species {
        let d = Species(key: "boa", name: "Emerald Boa", blurb: "Slides across the leaf litter in no hurry at all.", accent: 0x2E9A45)
        d.voxelSize = 0.045; d.speed = 0.3; d.wag = 1.4; d.wagAngle = 28; d.motion = .walk; d.depth = (0, 0.02); d.crowd = 1
        let green = C(0x2E9A45), white = C(0xE8F0D0), belly = C(0xC8D84A)
        Builtins.ellipsoid(d.body, SIMD3(0, 1.5, 3), SIMD3(1.7, 1.4, 2.4)) { _, y, _ in y < 1 ? belly : green }
        for z in 0..<2 { box(d.body, -1, 1, 0, 2, -z, -z, green) }
        for s in [-1, 1] { d.body.set(s * 2, 2, 4, C(0xE0C030)) }
        d.length = 6
        for i in 0..<34 {
            let r = i < 28 ? 1 : 0
            for x in -r...r { for y in 0...(1 + r) { d.tail.set(x, y, -i, y == 2 && i % 5 == 0 ? white : y == 0 ? belly : green) } }
        }
        return d
    }

    static func jaguar(sneakers: Bool) -> Species {
        let d = Species(key: "jaguar", name: sneakers ? "Jaguar (sneakers)" : "Jaguar",
                        blurb: sneakers ? "Fastest cat in the forest. Now with arch support." : "Pads by without a sound. Everyone else finds somewhere to be.",
                        accent: 0xE0A040)
        d.voxelSize = 0.06; d.speed = 0.9; d.turn = 1.3; d.wag = 2; d.wagAngle = 20; d.motion = .walk; d.depth = (0, 0.02)
        d.scary = true; d.cruiser = true; d.crowd = 2.5
        let gold = C(0xE0A040), ring = C(0x2A1E14), inner = C(0xC08030), white = C(0xF2E6CC)
        func coat(_ x: Int, _ y: Int, _ z: Int) -> VoxelColor {
            if y < 4 { return white }
            let n = vnoise(Float(x) * 0.6, Float(y) * 0.6, Float(z) * 0.6, 75)
            return n > 0.72 ? inner : n > 0.62 ? ring : gold
        }
        Builtins.ellipsoid(d.body, SIMD3(0, 6, 10), SIMD3(3, 3, 9)) { x, y, z in coat(x, y, z) }
        Builtins.ellipsoid(d.body, SIMD3(0, 8, 21), SIMD3(3, 2.8, 3)) { x, y, z in z > 22 && y < 8 ? white : coat(x, y + 2, z) }
        for s in [-1, 1] {
            d.body.set(s * 2, 11, 20, gold); d.body.set(s * 2, 11, 19, ring)
            d.body.set(s * 2, 9, 23, C(0xC8D040)); d.body.set(s * 2, 9, 24, C(0x0A0A0E))
            for z in [4, 16] {
                box(d.body, s * 2, s * 2, 1, 4, z, z + 1, gold)
                if sneakers {
                    box(d.body, s * 2, s * 2, 0, 0, z - 1, z + 2, C(0xF4F4F4))
                    d.body.set(s * 2, 1, z + 2, C(0xD8243A))
                } else {
                    box(d.body, s * 2, s * 2, 0, 0, z, z + 2, gold)
                }
            }
        }
        d.body.set(0, 8, 24, C(0xD07A6A))
        d.length = 24
        for i in 0..<16 { d.tail.set(0, 6 - i / 3 + (i > 10 ? (i - 10) / 2 : 0), -i, i % 4 == 3 ? ring : gold) }
        return d
    }

    // MARK: In the river

    static func tetra() -> Species {
        let d = Species(key: "tetra", name: "Neon Tetras", blurb: "A glowing little stripe of blue and red, in a crowd.", accent: 0x2EA8F0)
        d.voxelSize = 0.035; d.speed = 1.1; d.wag = 11; d.aquatic = true; d.schooling = true; d.depth = (0.2, 0.9); d.crowd = 0.2
        let blue = C(0x2EC8F8, 120), red = C(0xE0302A), silver = C(0xD8DCE0)
        Builtins.loft(d, 10, 2, 1, a: 0.08, b: 0.92, p: 0.6) { t, _, y, _, _ in
            if y == 1 && t > 0.15 { return blue }
            if y <= 0 && t < 0.5 { return red }
            return silver
        }
        Builtins.tailFan(d, 2, span: { (-1 - $0, 1 + $0) }) { _, _ in silver }
        Builtins.eye(d, 8, 1)
        return d
    }

    static func piranha() -> Species {
        let d = Species(key: "piranha", name: "Red-Bellied Piranha", blurb: "Mostly just shy and hungry for fruit. Mostly.", accent: 0xD8402A)
        d.voxelSize = 0.05; d.speed = 1; d.wag = 8; d.aquatic = true; d.schooling = true; d.depth = (0.1, 0.8); d.crowd = 0.6
        let grey = C(0x7A8490), sparkle = C(0xA8B0BA), red = C(0xD8402A), tooth = C(0xF4F4EE)
        Builtins.loft(d, 11, 3.2, 1.4, a: 0.1, b: 0.94, p: 0.5) { t, x, y, h, _ in
            if Float(y) < -h * 0.25 && t > 0.3 { return red }
            return vhash(x, y, Int(t * 50), 81) < 0.2 ? sparkle : grey
        }
        for x in -1...1 { d.body.set(x, -1, 11, tooth) }
        Builtins.fin(d, 0.35, 0.6, up: true, height: { _ in 1.4 }) { _, _, _ in grey }
        Builtins.tailFan(d, 3, span: { (-1 - $0 * 2, 1 + $0 * 2) }) { u, _ in u > 0.7 ? C(0x2A2A2A) : grey }
        Builtins.eye(d, 9, 1)
        return d
    }

    static func arapaima() -> Species {
        let d = Species(key: "arapaima", name: "Arapaima", blurb: "A giant of the river, with a tail end painted red.", accent: 0x5A6A5A)
        d.voxelSize = 0.06; d.speed = 0.6; d.turn = 1.1; d.wag = 3.5; d.wagAngle = 16; d.aquatic = true; d.depth = (0.2, 0.7); d.crowd = 2
        let olive = C(0x5A6A5A), scale = C(0xB8402A), belly = C(0xD8D4C0)
        Builtins.loft(d, 30, 2.2, 1.8, a: 0.04, b: 0.96, p: 0.4) { t, x, y, h, _ in
            if Float(y) < -h * 0.4 { return belly }
            return t < 0.4 && vhash(x, y, Int(t * 80), 82) < 0.5 + (0.4 - t) ? scale : olive
        }
        Builtins.fin(d, 0.08, 0.25, up: true, height: { _ in 2 }) { _, _, _ in scale }
        Builtins.fin(d, 0.08, 0.25, up: false, height: { _ in 2 }) { _, _, _ in scale }
        Builtins.tailFan(d, 4, span: { (-1 - $0 * 2, 1 + $0 * 2) }) { _, _ in scale }
        Builtins.eye(d, 27, 1)
        return d
    }

    /// The Amazon river dolphin: pink, with a long thin beak and a low ridge instead of a fin.
    static func boto() -> Species {
        let d = Species(key: "boto", name: "Pink River Dolphin", blurb: "Pink, bendy and curious. Swims up for a look, then away.", accent: 0xE8A0A8)
        d.voxelSize = 0.06; d.speed = 0.8; d.turn = 1.4; d.wag = 2.2; d.wagAngle = 16; d.aquatic = true; d.porpoise = true
        d.depth = (0.3, 0.8); d.crowd = 1.6
        let pink = C(0xE8A0A8), deep = C(0xC87A88), pale = C(0xF4CCD0)
        Builtins.loft(d, 22, 2.4, 2.2, a: 0.05, b: 0.9, p: 0.5) { _, _, y, h, _ in Float(y) < -h * 0.35 ? pale : Float(y) > h * 0.5 ? deep : pink }
        for z in 22..<27 { d.body.set(0, 0, z, pink); d.body.set(0, -1, z, pale) }
        for z in 9...13 { if let t = d.body.top(x: 0, z: z) { d.body.set(0, t + 1, z, deep) } }
        for s in [-1, 1] { box(d.body, s * 3, s * 5, -1, -1, 14, 15, pink) }
        Builtins.eye(d, 20, 0)
        Builtins.flukes(d, 4, deep)
        return d
    }

    static func sq(_ v: Float) -> Float { v * v }
}
