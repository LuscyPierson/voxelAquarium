import SceneKit

/// Builds the ocean diorama: a slab of sea floor cut away at the front, rocks, coral, seaweed and
/// treasure chests on top, and behind it all the open water, built from blocks too.
enum TankDecor {
    struct Built {
        let chests: [Chest]
        let seaweed: [Seaweed]
        /// Where a stream of bubbles rises from the floor, if anywhere.
        var vent: SIMD3<Float>? = nil
        /// Water you can tap: its surface height and how far back it goes.
        var water: (level: Float, back: Float)? = nil
    }

    @MainActor
    static func build(into root: SCNNode, biome: Biome) -> Built {
        // The far distance, behind everything: a wallpaper of giant blocks.
        let wall = SCNNode(geometry: farWall(biome).geometry(size: farBlock / Float(farSub), pivot: .zero, bevel: 0.02, jitter: 0))
        wall.name = "Far Wall"
        wall.simdPosition = SIMD3(0, 0, 26)
        wall.categoryBitMask = TankController.Mask.wall
        wall.castsShadow = false
        root.addChildNode(wall)
        place(root, "Sand", sand(), size: sandSize, at: sandOrigin)
        let built = switch biome {
        case .ocean: buildOcean(into: root)
        case .swamp: Swamp.build(into: root)
        case .rainforest: Rainforest.build(into: root)
        }
        Workshop.decorate(root, biome: biome)
        return built
    }

    @MainActor
    private static func buildOcean(into root: SCNNode) -> Built {
        var rng = SeededRandom(seed: 7)
        // Ridge after ridge, further and hazier each time, so the floor runs a long way back.
        place(root, "Farthest Ridge", ridge(seed: 67, width: 60, height: 12, colors: [0x98D2E2, 0x92CEDF, 0x9ED6E5], kelp: nil, detail: 2),
              size: 0.3, at: SIMD3(0, -1.5, 19)).castsShadow = false
        // One far-off rock spire in the haze.
        place(root, "Spire", spire(seed: 83, height: 20, detail: 2), size: 0.25, at: SIMD3(13, -1.5, 19)).castsShadow = false
        place(root, "Near Ridge", ridge(seed: 73, width: 62, height: 5, colors: [0x78B8CC, 0x74B4C9, 0x7CBBCE], kelp: 0x68AEA2, kelpChance: 0.05, detail: 2),
              size: 0.175, at: SIMD3(0, 0.1, 6.5)).castsShadow = false

        // Rocks, in fine blocks.
        let rocks: [(Int, Int, Int, Float, Float)] = [
            (18, 12, 14, -4.6, 1.6), (12, 8, 10, 4.4, 1.9), (16, 10, 12, -9.5, 1.2), (14, 10, 12, 9.8, 2.0), (12, 8, 10, -13, 2.4),
        ]
        for (rx, ry, rz, x, z) in rocks {
            place(root, "Rock", rock(&rng, rx, ry, rz), size: 0.075, at: SIMD3(x, floor(x, z) - 0.12, z))
        }

        // A reef's worth of coral, scattered over the floor and kept clear of the chests.
        let chestSpots: [SIMD2<Float>] = [SIMD2(1.9, 0.9), SIMD2(-6.8, 1.8)]
        var placed: [SIMD2<Float>] = rocks.map { SIMD2($0.3, $0.4) }
        var tries = 0
        while placed.count < rocks.count + 13 && tries < 400 {
            tries += 1
            let p = SIMD2(Float(rng.next(2800)) / 100 - 14, Float(rng.next(460)) / 100 - 1.2)
            if chestSpots.contains(where: { simd_distance($0, p) < 0.9 }) { continue }
            if placed.contains(where: { simd_distance($0, p) < 1.4 }) { continue }
            placed.append(p)
            let model: VoxelModel
            switch rng.next(8) {
            case 0, 1: model = staghorn(&rng, [0xFF6F91, 0xFF9F43, 0xA55EEA, 0x4FD1C5, 0xFFD23A][rng.next(5)])
            case 2: model = brain(&rng, [0xC9D46A, 0xE8A0B8, 0x9AD0A0][rng.next(3)])
            case 3: model = fan(&rng, [0xA55EEA, 0xE0507A, 0xF29A3A][rng.next(3)])
            case 4: model = tubes(&rng, [0xF2B33A, 0x7A6EE0, 0xE06A4A][rng.next(3)])
            case 5: model = anemone(&rng, [0xF27BA8, 0x7AD8C0, 0xF2D25A][rng.next(3)])
            case 6: model = table(&rng, [0x8FCF9A, 0xD8A0E0, 0xF2C08A][rng.next(3)])
            default: model = rng.next(2) == 0 ? starfish(&rng) : shell(&rng)
            }
            place(root, "Coral", model, size: 0.05, at: SIMD3(p.x, floor(p.x, p.y) - 0.01, p.y))
        }

        var spots: [SIMD2<Float>] = [
            SIMD2(-5.6, 2.4), SIMD2(-5.1, 2.0), SIMD2(-0.6, 2.4), SIMD2(5.6, 1.0), SIMD2(5.0, 2.4),
        ]
        for i in 0..<6 {
            let x = Float(i % 2 == 0 ? -1 : 1) * (7 + Float(i / 2) * 1.2 + Float(rng.next(10)) * 0.05)
            spots.append(SIMD2(x, Float(rng.next(40)) / 10 - 1.5))
        }
        let weeds = spots.enumerated().map { i, p in
            Seaweed(root: root, at: SIMD3(p.x, floor(p.x, p.y), p.y), segments: 7 + rng.next(8), seed: i)
        }

        let chests = [Chest(root: root, at: SIMD3(1.9, floor(1.9, 0.9), 0.9), turn: -18),
                      Chest(root: root, at: SIMD3(-6.8, floor(-6.8, 1.8), 1.8), turn: 24)]
        return Built(chests: chests, seaweed: weeds, vent: SIMD3(-1.6, floor(-1.6, 1.9) + 0.05, 1.9))
    }

    // MARK: - Pieces

    static let sandSize: Float = 0.125, sandOrigin = SIMD3<Float>(0, -0.12, 0)
    private static let sandFront = -20, sandBack = 30, sandWidth = 120

    /// How many blocks tall the sand is in a column.
    static func sandHeight(_ x: Int, _ z: Int) -> Int {
        let back = Float(z - sandFront) / Float(sandBack - sandFront)
        var h = 2 + Int((vnoise(Float(x) * 0.09, 0, Float(z) * 0.09, 1) * 4.4 + back * 1.2).rounded())
        // The forest's river runs along the front; behind it the ground steps up into a bank.
        if Biome.current == .rainforest {
            let edge = Rainforest.bankEdge / sandSize + (vhash(x, 0, 0, 5) < 0.3 ? 1 : 0)
            if Float(z) >= edge { h += Int(Rainforest.bankRise / sandSize) } else { h = max(1, h - 1) }
        }
        return h
    }

    /// Height of the sand's surface at a world position.
    static func floor(_ x: Float, _ z: Float) -> Float {
        let xi = Int((x / sandSize).rounded()), zi = Int(((z - sandOrigin.z) / sandSize).rounded())
        return sandWorld(xi, sandHeight(xi, zi) - 1, zi).y + sandSize / 2
    }

    static func sandColor(_ x: Int, _ y: Int, _ z: Int, top: Bool) -> VoxelColor {
        let (colors, bits) = Biome.current.floorColors
        let pebble = top && vhash(x, y, z, 9) < 0.03
        return C(pebble ? bits[Int(vhash(x, 1, z, 4) * Float(bits.count))] : colors[Int(vhash(x, y, z, 3) * Float(colors.count))])
    }

    /// Centre of a sand block in the world.
    static func sandWorld(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) * sandSize + sandOrigin }

    /// The sea floor slab: sand on top, and down the cut-away front, layers of sand, earth and rock.
    static func sand() -> VoxelModel {
        let m = VoxelModel()
        let front = sandFront
        for x in -sandWidth...sandWidth {
            for z in front...sandBack {
                let h = sandHeight(x, z)
                for y in 0..<h { m.set(x, y, z, sandColor(x, y, z, top: y == h - 1)) }
            }
            // Strata down the front face, a couple of blocks deep.
            for z in front...(front + 1) {
                for y in -8 ... -1 {
                    let wobble = Int(vnoise(Float(x) * 0.1, Float(z), 0, 8) * 2.5)
                    let d = -y + wobble
                    let c: UInt32 = d <= 2 ? 0xC9AE7A : d <= 4 ? 0x8E6A44 : d <= 6 ? 0x6B5A4A : 0x4F4A48
                    let speck = vhash(x, y, z, 12) < 0.08
                    m.set(x, y, z, C(speck ? (d <= 5 ? 0xB59A6A : 0x7A7470) : c))
                }
            }
        }
        return m
    }

    /// The far wallpaper is made of giant blocks, each `farBlock` across, drawn as `farSub` × `farSub` little ones
    /// so every block gets a light top-left rim and a shadowed bottom-right one, and reads as a block, not a blur.
    static let farBlock: Float = 2.4, farSub = 6

    static func farWall(_ biome: Biome) -> VoxelModel {
        let m = VoxelModel()
        let n = farSub
        for bx in -17...17 {
            for by in -5...9 {
                let c = farColor(biome, bx, by)
                let raised = vhash(bx, by, 0, 64) < 0.1
                for i in 0..<n {
                    for j in 0..<n {
                        // Bevel: light along the top and left edges, dark along the bottom and right.
                        var f: Float = 1
                        if j == n - 1 || i == 0 { f = raised ? 1.1 : 1.06 }
                        if j == 0 || i == n - 1 { f = raised ? 0.88 : 0.93 }
                        if (j == n - 1 && i == n - 1) || (j == 0 && i == 0) { f = 1 }
                        let rgb = SIMD3<UInt32>(simd_clamp(c * f, .zero, SIMD3(repeating: 1)) * 255)
                        m.set(bx * n + i, by * n + j, raised ? -1 : 0, C(rgb.x << 16 | rgb.y << 8 | rgb.z, 255))
                    }
                }
            }
        }
        return m
    }

    /// The colour of one giant block: a gradient from the bottom to the top, with patches and shapes for the world.
    static func farColor(_ biome: Biome, _ bx: Int, _ by: Int) -> SIMD3<Float> {
        let stops = biome.farColors
        let t = Float(by + 5) / 14
        var c = t < 0.5 ? simd_mix(stops[0], stops[1], SIMD3(repeating: t * 2)) : simd_mix(stops[1], stops[2], SIMD3(repeating: (t - 0.5) * 2))
        let v = vhash(bx, by, 0, 66), n = vnoise(Float(bx) * 0.35, Float(by) * 0.35, 0, 67)
        switch biome {
        case .ocean:
            // Light coming through in brighter patches, deeper water in darker ones.
            c *= 0.95 + 0.1 * v
            if n > 0.7 && t > 0.35 { c = simd_mix(c, SIMD3(0.75, 0.95, 0.98), SIMD3(repeating: 0.2)) }
        case .swamp:
            c *= 0.95 + 0.1 * v
            // A few far-off cypress trunks, as darker columns, and grey moss hanging up in the air.
            if vhash(bx, 0, 0, 68) < 0.1 { c = simd_mix(c, SIMD3(0.18, 0.2, 0.12), SIMD3(repeating: 0.35)) }
            if t > 0.6 && n > 0.66 { c = simd_mix(c, SIMD3(0.62, 0.66, 0.56), SIMD3(repeating: 0.25)) }
        case .rainforest:
            // Leaves in clumps of greens, sky peeking through near the top, and the odd trunk.
            let leaves: [SIMD3<Float>] = [SIMD3(0.22, 0.42, 0.18), SIMD3(0.3, 0.52, 0.22), SIMD3(0.38, 0.6, 0.26), SIMD3(0.26, 0.46, 0.3)]
            c = simd_mix(c, leaves[Int(n * 3.99)], SIMD3(repeating: 0.3)) * (0.95 + 0.1 * v)
            if t > 0.7 && n > 0.66 { c = simd_mix(c, SIMD3(0.86, 0.94, 0.84), SIMD3(repeating: 0.4)) }
        }
        return c
    }

    /// A long, hazy ridge of distant reef, with the odd kelp stalk standing up from it.
    /// `detail` splits each block into smaller ones (place it at a matching fraction of the size).
    static func ridge(seed: Int, width: Int, height: Float, colors: [UInt32], kelp: UInt32?, kelpChance: Float = 0.05,
                      detail: Int = 1) -> VoxelModel {
        let m = VoxelModel()
        let k = Float(detail)
        for x in -width * detail...width * detail {
            let fx = Float(x) / k
            let n = vnoise(fx * 0.09, 0, 0, seed), n2 = vnoise(fx * 0.3, 1, 0, seed), n3 = vnoise(fx * 0.9, 2, 0, seed)
            let h = max(1, Int(((height * (0.25 + pow(n, 1.4)) + 2 * n2) * k + n3 * 1.5).rounded()))
            for z in 0..<(2 * detail) {
                let hz = h - z / detail - (z % 2) * Int(vhash(x, z, 0, seed) * 2)
                for y in 0..<max(1, hz) { m.set(x, y, z, C(colors[Int(vhash(x, y, z, seed) * Float(colors.count))])) }
            }
            if let kelp, vhash(x / detail, 0, 0, seed + 1) < kelpChance, x % detail == 0 {
                let tall = (3 + Int(vhash(x, 1, 0, seed + 1) * 6)) * detail
                for y in h..<(h + tall) {
                    let sway = Int((sin(Float(y) / k * 0.7 + fx) * 0.8 * k).rounded())
                    m.set(x + sway, y, 0, C(kelp))
                    if y % 3 == 0 { m.set(x + sway + (y % 6 == 0 ? 1 : -1), y, 0, C(kelp)) }
                }
            }
        }
        return m
    }

    /// The same model in blocks a fraction of the size, each one shaded a touch differently.
    static func refined(_ model: VoxelModel, by n: Int) -> VoxelModel {
        let m = VoxelModel()
        for (p, c) in model.voxels {
            for dx in 0..<n { for dy in 0..<n { for dz in 0..<n {
                let q = V3(p.x * n + dx, p.y * n + dy, p.z * n + dz)
                let f = (vhash(q.x, q.y, q.z, 77) - 0.5) * 0.08
                m.set(q.x, q.y, q.z, C(f > 0 ? lighter(c.rgb, f) : darker(c.rgb, -f), c.glow))
            } } }
        }
        return m
    }

    static func rock(_ rng: inout SeededRandom, _ rx: Int, _ ry: Int, _ rz: Int) -> VoxelModel {
        let m = VoxelModel()
        let seed = rng.next(1000)
        for x in -rx...rx {
            for y in 0...ry {
                for z in -rz...rz {
                    let d = Float(x * x) / Float(rx * rx) + Float(y * y) / Float(ry * ry) + Float(z * z) / Float(rz * rz)
                    if d > 0.75 + vnoise(Float(x) * 0.2, Float(y) * 0.2, Float(z) * 0.2, seed) * 0.45 { continue }
                    let streak = vnoise(Float(x) * 0.3, Float(y) * 0.9, Float(z) * 0.3, seed + 2) > 0.68
                    m.set(x, y, z, C(streak ? 0x7E8590 : vhash(x, y, z, seed) < 0.5 ? 0x6E7480 : 0x5A606B))
                }
            }
        }
        // Moss on top.
        for (p, _) in m.voxels where !m.has(p.x, p.y + 1, p.z) && vnoise(Float(p.x) * 0.25, 0, Float(p.z) * 0.25, seed + 1) > 0.5 {
            m[p] = C(vhash(p.x, p.y, p.z, 5) < 0.5 ? 0x4E8F3A : 0x3C7A30)
        }
        return m
    }

    // MARK: Corals (built in fine, half-size blocks)

    static func lighter(_ c: UInt32, _ f: Float) -> UInt32 {
        func ch(_ v: UInt32) -> UInt32 { UInt32(min(255, Float(v) + (255 - Float(v)) * f)) }
        return ch(c >> 16 & 0xFF) << 16 | ch(c >> 8 & 0xFF) << 8 | ch(c & 0xFF)
    }

    static func darker(_ c: UInt32, _ f: Float) -> UInt32 {
        func ch(_ v: UInt32) -> UInt32 { UInt32(Float(v) * (1 - f)) }
        return ch(c >> 16 & 0xFF) << 16 | ch(c >> 8 & 0xFF) << 8 | ch(c & 0xFF)
    }

    /// Branching staghorn coral with pale, glowing tips.
    static func staghorn(_ rng: inout SeededRandom, _ color: UInt32) -> VoxelModel {
        let m = VoxelModel()
        let tip = lighter(color, 0.55), deep = darker(color, 0.15)
        func branch(_ x0: Int, _ y0: Int, _ z0: Int, _ len: Int, _ dx: Int, _ dz: Int, _ depth: Int, _ rng: inout SeededRandom) {
            var x = x0, y = y0, z = z0
            for i in 0..<len {
                let thick = depth == 0 && i < len / 2
                m.set(x, y, z, i >= len - 2 ? C(tip, 110) : C(i % 3 == 0 ? deep : color))
                if thick { m.set(x + 1, y, z, C(deep)); m.set(x, y, z + 1, C(color)) }
                y += 1
                if rng.next(3) == 0 { x += dx; z += dz }
                if depth < 3 && len - i > 5 && rng.next(5) == 0 {
                    branch(x, y, z, len - i - 2, rng.next(3) - 1, rng.next(3) - 1, depth + 1, &rng)
                }
            }
        }
        for _ in 0..<(4 + rng.next(3)) {
            branch(rng.next(7) - 3, 0, rng.next(7) - 3, 12 + rng.next(12), rng.next(3) - 1, rng.next(3) - 1, 0, &rng)
        }
        return m
    }

    /// A rounded brain coral with winding grooves.
    static func brain(_ rng: inout SeededRandom, _ color: UInt32) -> VoxelModel {
        let m = VoxelModel()
        let r = Float(6 + rng.next(4)), seed = rng.next(100)
        let groove = darker(color, 0.35), ridge = lighter(color, 0.15)
        for x in -Int(r)...Int(r) {
            for z in -Int(r)...Int(r) {
                for y in 0...Int(r) {
                    let d = (Float(x * x) + Float(z * z)) / (r * r) + Float(y * y) / (r * r * 0.55)
                    guard d <= 1 else { continue }
                    let w = sin(Float(x) * 0.9 + vnoise(Float(z) * 0.3, Float(y) * 0.3, 0, seed) * 6)
                    m.set(x, y, z, C(w > 0.45 ? groove : w < -0.6 ? ridge : color))
                }
            }
        }
        return m
    }

    /// A flat, lacy sea fan on a short trunk.
    static func fan(_ rng: inout SeededRandom, _ color: UInt32) -> VoxelModel {
        let m = VoxelModel()
        let w = 7 + rng.next(4), h = 12 + rng.next(6), seed = rng.next(100)
        let trunk = darker(color, 0.3), edge = lighter(color, 0.3)
        for y in 0..<3 { m.set(0, y, 0, C(trunk)) }
        for y in 3...h {
            for x in -w...w {
                let e = sq(Float(x) / Float(w)) + sq(Float(y - 3 - h / 2) / Float(h / 2 + 1))
                guard e <= 1 else { continue }
                let lace = (x + y) % 3 == 0 || (x - y + 99) % 3 == 0 || x == 0
                if lace && vhash(x, y, 0, seed) > 0.08 { m.set(x, y, 0, C(e > 0.8 ? edge : color)) }
            }
        }
        return m
    }

    /// A cluster of hollow tube sponges.
    static func tubes(_ rng: inout SeededRandom, _ color: UInt32) -> VoxelModel {
        let m = VoxelModel()
        let rim = lighter(color, 0.35), inside = darker(color, 0.5)
        for _ in 0..<(3 + rng.next(3)) {
            let cx = rng.next(9) - 4, cz = rng.next(9) - 4, h = 6 + rng.next(12)
            for y in 0..<h {
                for x in -2...2 {
                    for z in -2...2 {
                        let d = x * x + z * z
                        if d <= 5 && d >= 2 { m.set(cx + x, y, cz + z, C(y == h - 1 ? rim : color)) }
                        else if d < 2 && y < h - 1 { m.set(cx + x, y, cz + z, C(inside)) }
                    }
                }
            }
        }
        return m
    }

    /// An anemone: a squat column crowned with soft tentacles.
    static func anemone(_ rng: inout SeededRandom, _ color: UInt32) -> VoxelModel {
        let m = VoxelModel()
        let base = darker(color, 0.25), tip = lighter(color, 0.6)
        for y in 0..<3 { for x in -3...3 { for z in -3...3 where x * x + z * z <= 9 { m.set(x, y, z, C(base)) } } }
        for x in -3...3 {
            for z in -3...3 where x * x + z * z <= 10 && rng.next(4) != 0 {
                let len = 3 + rng.next(4)
                for i in 0..<len {
                    let lean = i * 2 / 3
                    m.set(x + (x > 0 ? lean / 2 : x < 0 ? -lean / 2 : 0), 3 + i, z + (z > 0 ? lean / 2 : z < 0 ? -lean / 2 : 0),
                          C(i == len - 1 ? tip : color, i == len - 1 ? 120 : 0))
                }
            }
        }
        return m
    }

    /// Table coral: a stalk with a wide, flat top.
    static func table(_ rng: inout SeededRandom, _ color: UInt32) -> VoxelModel {
        let m = VoxelModel()
        let r = Float(6 + rng.next(4)), stalk = darker(color, 0.25), top = lighter(color, 0.2)
        for y in 0..<6 { for x in 0...1 { for z in 0...1 { m.set(x, y, z, C(stalk)) } } }
        for x in -Int(r)...Int(r) + 1 {
            for z in -Int(r)...Int(r) + 1 {
                let d = (sq(Float(x) - 0.5) + sq(Float(z) - 0.5)).squareRoot()
                guard d <= r else { continue }
                m.set(x, 6, z, C(color))
                if d < r - 1.5 { m.set(x, 7, z, C(vhash(x, 7, z, 3) < 0.3 ? top : color)) }
                if d > r - 1 && vhash(x, 8, z, 4) < 0.5 { m.set(x, 7, z, C(top)) }
            }
        }
        return m
    }

    static func starfish(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        let color = [0xF26A3A, 0xE84A7A, 0xF2B33A][rng.next(3)], dot = lighter(UInt32(color), 0.5)
        for k in 0..<5 {
            let a = Float(k) / 5 * 2 * .pi + Float(rng.next(10)) * 0.05
            for i in 0...5 {
                let x = Int((cos(a) * Float(i)).rounded()), z = Int((sin(a) * Float(i)).rounded())
                m.set(x, 0, z, C(i % 2 == 1 ? dot : UInt32(color)))
                if i < 3 { m.set(x, 1, z, C(UInt32(color))) }
            }
        }
        return m
    }

    static func shell(_ rng: inout SeededRandom) -> VoxelModel {
        let m = VoxelModel()
        let color = [0xF4E2C8, 0xF2C0B0, 0xE8D8F0][rng.next(3)], ridge = darker(UInt32(color), 0.2)
        for x in -3...3 {
            for z in 0...4 where sq(Float(x) / 3.5) + sq(Float(z - 2) / 2.6) <= 1 {
                m.set(x, 0, z, C(abs(x) % 2 == 1 ? ridge : UInt32(color)))
                if abs(x) < 2 && z > 0 && z < 4 { m.set(x, 1, z, C(UInt32(color))) }
            }
        }
        return m
    }

    static func sq(_ v: Float) -> Float { v * v }

    // MARK: Far-off shapes

    /// A tall, knobbly rock spire for the distance.
    static func spire(seed: Int, height: Int, detail: Int = 1) -> VoxelModel {
        let m = VoxelModel()
        let k = Float(detail)
        for y in 0..<height * detail {
            let fy = Float(y) / k
            let t = fy / Float(height)
            let r = (2.6 * (1 - t * 0.7) + vnoise(0, fy * 0.3, 0, seed) * 1.2 + vnoise(fy, 0, 0, seed + 1) * 0.4) * k
            let lean = Int((sin(fy * 0.12 + Float(seed)) * 1.5 * k).rounded())
            for x in -4 * detail...4 * detail {
                for z in -3 * detail...3 * detail where sq(Float(x) / r) + sq(Float(z) / r) <= 1 {
                    m.set(x + lean, y, z, C(vhash(x, y, z, seed) < 0.5 ? 0x7DB4C8 : 0x74ACC2))
                }
            }
        }
        return m
    }

    /// The broken hull of an old wooden ship, half sunk in the far sand.
    static func wreck() -> VoxelModel {
        let m = VoxelModel()
        let wood: [UInt32] = [0x86A6B0, 0x7C9EAA, 0x90AEB8], dark: UInt32 = 0x6A8E9C
        for x in -18...18 {
            let half = 6 * (1 - sq(Float(x) / 19))
            let depth = Int(4 * (1 - sq(Float(x) / 20)))
            for y in 0...(depth + 3) {
                for z in -Int(half)...Int(half) {
                    let side = abs(Float(z)) >= half - 1 || y == 0
                    if !side { continue }
                    if x > 8 && y > depth - 1 && vhash(x, y, z, 91) < 0.5 { continue }   // a broken bow
                    m.set(x, y, z, C(y == depth + 3 ? dark : wood[Int(vhash(x, y, z, 92) * 3)]))
                }
            }
        }
        // A snapped mast, leaning.
        for y in 0..<16 { m.set(-3 + y / 4, 4 + y, 0, C(dark)) }
        for x in -4...3 { m.set(x, 14, 0, C(dark)) }
        return m
    }

    // MARK: - Helpers

    /// Water up to `level`, from the front of the diorama back to `back`: everything below the line is seen through
    /// a murky tint, with a pale sheet on top so the water line reads clearly.
    @MainActor
    static func addWater(_ root: SCNNode, level: Float, back: Float, color: UInt32) {
        let front = TankController.front + 0.1, length = back - front
        func layer(_ height: Float, _ y: Float, _ c: UInt32, _ transparency: CGFloat) {
            let node = SCNNode(geometry: SCNBox(width: 160, height: CGFloat(height), length: CGFloat(length), chamferRadius: 0))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = NSColor(rgb: c)
            m.transparency = transparency
            m.writesToDepthBuffer = false
            node.geometry!.materials = [m]
            node.name = "Water"
            node.simdPosition = SIMD3(0, y, front + length / 2)
            node.categoryBitMask = TankController.Mask.wall
            node.castsShadow = false
            root.addChildNode(node)
        }
        layer(level + 5, (level - 5) / 2, color, 0.5)
        root.addChildNode(surface(level: level, front: front, back: min(back, front + 7), color: color))
    }

    static let surfaceSize: Float = 0.2

    /// The top of the water in blocks: pale, see-through tiles with the odd raised cap, all bobbing on slow waves.
    @MainActor
    static func surface(level: Float, front: Float, back: Float, color: UInt32) -> SCNNode {
        let m = VoxelModel()
        let s = surfaceSize
        let shades = [lighter(color, 0.22), lighter(color, 0.28), lighter(color, 0.34)]
        for x in -130...130 {
            for z in 0..<Int((back - front) / s) {
                let n = vnoise(Float(x) * 0.18, Float(z) * 0.18, 0, 91)
                m.set(x, 0, z, C(n > 0.72 ? lighter(color, 0.45) : shades[Int(vhash(x, 0, z, 92) * 3)]))
                if n > 0.8 && vhash(x, 1, z, 93) < 0.35 { m.set(x, 1, z, C(lighter(color, 0.6))) }
            }
        }
        let geometry = m.geometry(size: s, pivot: .zero, bevel: 0.1, jitter: 0)
        geometry.materials = geometry.materials.map { base in
            let mat = base.copy() as! SCNMaterial
            mat.transparency = 0.38
            mat.shaderModifiers = [.geometry: """
            float wv = sin(_geometry.position.x * 1.6 + scn_frame.time * 1.5) + sin(_geometry.position.z * 2.2 - scn_frame.time * 1.1);
            _geometry.position.y += wv * 0.018;
            """]
            return mat
        }
        let node = SCNNode(geometry: geometry)
        node.name = "Water Surface"
        node.simdPosition = SIMD3(0, level - s / 2, front + s / 2)
        node.categoryBitMask = TankController.Mask.wall
        node.castsShadow = false
        return node
    }

    @discardableResult
    static func place(_ root: SCNNode, _ name: String, _ model: VoxelModel, size: Float, at p: SIMD3<Float>) -> SCNNode {
        let geometry = model.geometry(size: size, pivot: .zero)
        if Biome.current == .ocean {
            geometry.materials = geometry.materials.map { $0 === Materials.lit ? Materials.caustic : $0 }
        }
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.simdPosition = p
        node.categoryBitMask = TankController.Mask.decor
        node.castsShadow = name != "Sand"
        root.addChildNode(node)
        return node
    }
}

/// Bends a chain of segments back and forth like seaweed in a current.
final class Seaweed {
    private var segments: [SCNNode] = []
    private let seed: Float, speed: Float

    /// `hanging` vines hang down from where they start instead of growing up.
    init(root: SCNNode, at p: SIMD3<Float>, segments count: Int, seed: Int,
         colors greens: [UInt32] = [0x2E8B57, 0x3CB371, 0x6BCB77, 0x2F9E5B], hanging: Bool = false) {
        self.seed = Float(seed) * 1.7
        speed = (0.9 + Float(seed % 3) * 0.2) * (hanging ? 0.5 : 1)
        var parent = SCNNode()
        parent.simdPosition = p
        if hanging { parent.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3(0, 0, 1)) }
        root.addChildNode(parent)
        for i in 0..<count {
            let m = VoxelModel()
            for y in 0..<3 { m.set(0, y, 0, C(greens[(seed + i) % greens.count])) }
            if i % 2 == 0 { m.set(i % 4 == 0 ? 1 : -1, 1, 0, C(greens[(seed + i + 1) % greens.count])) }
            let node = SCNNode(geometry: m.geometry(size: 0.1, pivot: SIMD3(0, -0.5, 0)))
            node.categoryBitMask = TankController.Mask.decor
            node.simdPosition = i == 0 ? .zero : SIMD3(0, 0.3, 0)
            parent.addChildNode(node)
            segments.append(node)
            parent = node
        }
    }

    func update(time: Float) {
        for (i, s) in segments.enumerated() {
            let a = sin(time * speed + Float(i) * 0.55 + seed) * 7 * (0.4 + Float(i) * 0.12) * .pi / 180
            s.simdEulerAngles = SIMD3(a * 0.3, 0, a)
        }
    }
}

/// The treasure chest: tap it and the lid pops open with a rush of bubbles.
final class Chest {
    let node: SCNNode
    private let lid: SCNNode
    private var openUntil: Float = 0, angle: Float = 0

    init(root: SCNNode, at p: SIMD3<Float>, turn: Float) {
        let wood = C(0x8B5A2B), dark = C(0x6B4220), gold = C(0xFFC93C)
        let body = VoxelModel()
        for x in 0..<9 {
            for y in 0..<5 {
                for z in 0..<6 {
                    let edge = x == 0 || x == 8 || z == 0 || z == 5
                    if !edge && y > 0 { continue }
                    body.set(x, y, z, x == 2 || x == 6 ? gold : y == 0 ? dark : wood)
                }
            }
        }
        body.set(4, 3, -1, gold)
        let lidModel = VoxelModel()
        for x in 0..<9 {
            for y in 0..<2 {
                for z in 0..<6 { lidModel.set(x, y, z, x == 2 || x == 6 ? gold : y == 1 ? dark : wood) }
            }
        }

        node = SCNNode(geometry: body.geometry(size: 0.1, pivot: SIMD3(4, -0.5, 2.5)))
        node.name = "Chest"
        node.categoryBitMask = TankController.Mask.chest
        node.simdPosition = p
        node.simdEulerAngles = SIMD3(0, turn * .pi / 180, 0)
        root.addChildNode(node)

        // The lid hinges on the back edge of the box.
        lid = SCNNode(geometry: lidModel.geometry(size: 0.1, pivot: SIMD3(4, -0.5, 5.5)))
        lid.categoryBitMask = TankController.Mask.chest
        lid.simdPosition = SIMD3(0, 0.5, 0.3)
        node.addChildNode(lid)

        let seed = Int(abs(p.x * 10))
        let coins = SCNNode(geometry: Self.coins(seed: seed).geometry(size: 0.05, pivot: .zero, jitter: 0.1))
        coins.categoryBitMask = TankController.Mask.chest
        coins.simdPosition = SIMD3(0, 0.025, 0)
        node.addChildNode(coins)
        let spill = SCNNode(geometry: Self.spill(seed: seed).geometry(size: 0.09, pivot: .zero, jitter: 0.1))
        spill.categoryBitMask = TankController.Mask.chest
        spill.simdPosition = SIMD3(0, 0.045, 0)
        node.addChildNode(spill)
        update(time: 0, dt: 1)
    }

    private static let golds: [UInt32] = [0xFFD23A, 0xF5BC2A, 0xFFDF62, 0xEDB024]

    /// A gold coin lying flat, now and then one that catches the light.
    private static func coin(_ m: VoxelModel, _ x: Int, _ y: Int, _ z: Int, seed: Int) {
        let h = vhash(x, y, z, seed)
        let shine = h < 0.07
        m.set(x, y, z, VoxelColor(rgb: shine ? 0xFFF2A8 : golds[Int(h * 97) % golds.count], glow: shine ? 150 : 0,
                                  shape: .coin, turn: UInt8(Int(h * 31) % 4)))
    }

    /// A heap of gold coins filling the chest and rising well over its rim.
    /// Half-size blocks: x −6...6 and z −3...3 fit inside the box.
    private static func coins(seed: Int) -> VoxelModel {
        let m = VoxelModel()
        for x in -6...6 {
            for z in -3...3 {
                let d = Float(x * x) / 42 + Float(z * z) / 12
                let top = 9 + Int(((1 - min(1, d)) * 4.6).rounded())
                for y in 2..<top { m.set(x, y, z, C(golds[Int(vhash(x, y, z, seed + 1) * 4)])) }
                coin(m, x, top, z, seed: seed)
            }
        }
        return m
    }

    /// Coins spilled on the floor in front of the chest.
    private static func spill(seed: Int) -> VoxelModel {
        let m = VoxelModel()
        for i in 0..<10 {
            let x = Int(vhash(i, 0, 0, seed + 2) * 11) - 5, z = -4 - Int(vhash(i, 1, 0, seed + 2) * 3)
            coin(m, x, 0, z, seed: seed)
        }
        return m
    }

    func isOpen(at time: Float) -> Bool { time < openUntil }

    func open(at time: Float) { openUntil = time + 3 }

    func update(time: Float, dt: Float) {
        // At rest the lid sits ajar so the gold shows; a tap throws it wide open.
        let target: Float = isOpen(at: time) ? 88 : 58
        let step = dt * (isOpen(at: time) ? 300 : 90)
        angle += max(-step, min(step, target - angle))
        lid.simdEulerAngles = SIMD3(angle * .pi / 180, 0, 0)
    }
}

/// A small deterministic random generator so the decor looks the same every launch.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}
