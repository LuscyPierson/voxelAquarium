import SceneKit
import simd

/// Painted textures for the ocean: the caustic pattern the sunlight throws, and a dot for marine snow.
enum OceanArt {
    static func rgb(_ c: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255,
                blue: CGFloat(c & 0xFF) / 255, alpha: a)
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Tileable caustic light lines (white on black): the edges between cells of Worley noise.
    static func caustics(size n: Int = 256, cells: Int = 6, seed: Int = 3) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: n * n * 4)
        func point(_ cx: Int, _ cy: Int) -> SIMD2<Float> {
            let wx = (cx % cells + cells) % cells, wy = (cy % cells + cells) % cells
            return SIMD2(Float(cx) + 0.02 + 0.96 * vhash(wx, wy, 0, seed), Float(cy) + 0.02 + 0.96 * vhash(wx, wy, 1, seed))
        }
        for py in 0..<n {
            for px in 0..<n {
                let p = SIMD2(Float(px) + 0.5, Float(py) + 0.5) * Float(cells) / Float(n)
                let cx = Int(p.x), cy = Int(p.y)
                var d1: Float = 9, d2: Float = 9
                for oy in -1...1 {
                    for ox in -1...1 {
                        let d = simd_distance(p, point(cx + ox, cy + oy))
                        if d < d1 { d2 = d1; d1 = d } else if d < d2 { d2 = d }
                    }
                }
                let edge = 1 - min(1, (d2 - d1) / 0.16)
                let v = UInt8(min(255, pow(edge, 2.2) * 255 + 6))
                let i = (py * n + px) * 4
                pixels[i] = v
                pixels[i + 1] = v
                pixels[i + 2] = v
            }
        }
        let g = context(n, n)
        pixels.withUnsafeMutableBytes { memcpy(g.data!, $0.baseAddress!, n * n * 4) }
        return g.makeImage()!
    }

    static func dot() -> CGImage {
        let n = 32
        let g = context(n, n)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let grad = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        g.drawRadialGradient(grad, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16),
                             endRadius: 16, options: [])
        return g.makeImage()!
    }
}

extension Materials {
    /// The lit voxel material plus sunlight caustics: rippling light lines, anchored in the world and
    /// drifting over time, on every upward-facing surface. Used for the sand, rocks, coral and reef.
    static let caustic: SCNMaterial = {
        let m = lit.copy() as! SCNMaterial
        m.emission.contents = NSColor.black
        m.shaderModifiers = [.surface: """
        #pragma body
        float3 cwp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 cwn = (scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz;
        float cup = saturate(cwn.y * 1.4 - 0.2) * saturate((5.9 - cwp.y) * 0.5);
        float ct = scn_frame.time * 0.45 + 23.0;
        float2 cp = cwp.xz * 0.95 + float2(31.0, 17.0);
        float2 ci = cp;
        float cc = 1.0;
        for (int n = 0; n < 4; n++) {
            float tn = ct * (1.0 - (3.5 / float(n + 1)));
            ci = cp + float2(cos(tn - ci.x) + sin(tn + ci.y), sin(tn - ci.y) + cos(tn + ci.x));
            cc += 1.0 / length(float2(cp.x / (sin(ci.x + tn) / 0.006), cp.y / (cos(ci.y + tn) / 0.006)));
        }
        cc /= 4.0;
        cc = 1.17 - pow(cc, 1.4);
        float cv = pow(abs(cc), 11.0);
        _surface.emission.rgb += float3(0.45, 0.82, 1.0) * saturate(cv * 1.6) * cup * 0.55;
        """]
        return m
    }()
}

/// The living parts of the ocean: marine snow, the reef along the back (which things peek over)
/// and a small school of fish swimming back and forth behind everything.
@MainActor
final class OceanLife {
    static let reefSize: Float = 0.1
    /// The bottom of the back wall; in the forest it stands on the raised river bank.
    nonisolated static var reefBase: SIMD3<Float> { SIMD3(0, Biome.current == .rainforest ? 0.3 + Rainforest.bankRise : 0.3, 3.7) }

    /// Height of the top of the back reef at a world x.
    static func reefTop(_ x: Float) -> Float {
        reefBase.y + Float(reefHeight(Int((x / reefSize).rounded()))) * reefSize
    }

    private var school: [(node: SCNNode, offset: SIMD3<Float>, phase: Float)] = []
    private var heading: Float = 1

    init(root: SCNNode, biome: Biome = .ocean) {
        // The wall along the back that things peek over: reef in the ocean, a muddy bank in the swamp,
        // a mossy fallen log in the forest.
        let wall: VoxelModel
        switch biome {
        case .ocean: wall = Self.reef()
        case .swamp: wall = Swamp.bank()
        case .rainforest: wall = Rainforest.log()
        }
        TankDecor.place(root, "Back Reef", wall, size: Self.reefSize, at: Self.reefBase).castsShadow = false
        root.addChildNode(Self.particles(biome))
        addSchool(root, biome)
        update(time: 0, dt: 0)
    }

    /// Marine snow in the sea, murky specks in the bayou, rain in the forest.
    private static func particles(_ biome: Biome) -> SCNNode {
        let snow = SCNParticleSystem()
        snow.particleImage = OceanArt.dot()
        snow.birthRate = 12
        snow.particleLifeSpan = 16
        snow.particleLifeSpanVariation = 4
        snow.warmupDuration = 30
        snow.emitterShape = SCNBox(width: 30, height: 5.0, length: 5, chamferRadius: 0)
        snow.birthLocation = .volume
        snow.particleVelocity = 0.035
        snow.particleVelocityVariation = 0.03
        snow.spreadingAngle = 180
        snow.acceleration = SCNVector3(0.006, -0.012, 0)
        snow.particleSize = 0.03
        snow.particleSizeVariation = 0.018
        snow.particleColor = NSColor(white: 1, alpha: 0.5)
        snow.particleColorVariation = SCNVector4(0, 0, 0, 0.3)
        snow.blendMode = .additive
        snow.particleIntensity = 0.7
        snow.isLightingEnabled = false
        snow.sortingMode = .none
        let snowNode = SCNNode()
        snowNode.simdPosition = SIMD3(0, 3.2, 0.2)
        switch biome {
        case .ocean: break
        case .swamp:
            snow.birthRate = 18
            snow.particleColor = NSColor(srgbRed: 0.85, green: 0.9, blue: 0.6, alpha: 0.4)
            snow.particleSize = 0.025
            snow.blendMode = .alpha
        case .rainforest:
            // Rain: thin streaks falling fast, and a few glinting drops.
            snow.birthRate = 70
            snow.particleLifeSpan = 1.6
            snow.particleLifeSpanVariation = 0.3
            snow.warmupDuration = 3
            snow.emitterShape = SCNBox(width: 30, height: 0.1, length: 8, chamferRadius: 0)
            snow.birthLocation = .surface
            snow.emittingDirection = SCNVector3(0, -1, 0)
            snow.spreadingAngle = 3
            snow.particleVelocity = 6
            snow.particleVelocityVariation = 1
            snow.acceleration = SCNVector3(0.4, -2, 0)
            snow.particleSize = 0.012
            snow.particleSizeVariation = 0.004
            snow.stretchFactor = 0.035
            snow.particleColor = NSColor(white: 1, alpha: 0.4)
            snowNode.simdPosition = SIMD3(0, 8, 1.5)
        }
        snowNode.categoryBitMask = TankController.Mask.effect
        snowNode.addParticleSystem(snow)
        return snowNode
    }

    /// A school of small, hazy fish far back by the reef (or, in the forest, a flock of birds).
    private func addSchool(_ root: SCNNode, _ biome: Biome) {
        let fish = VoxelModel()
        let (b, f): (UInt32, UInt32) = biome == .ocean ? (0x3E7E9C, 0x2E6A88) : biome == .swamp ? (0x6E7A52, 0x56623E) : (0x3A4A3A, 0x2A382A)
        let body = C(b), fin = C(f)
        for z in 0..<7 {
            let h = z == 0 || z == 6 ? 0 : 1
            for y in -h...h { fish.set(0, y, z, body) }
        }
        if biome == .rainforest {
            for x in 1...3 { fish.set(x, x / 2, 3, fin); fish.set(-x, x / 2, 3, fin) }
            fish.set(0, 0, -1, fin)
        } else {
            for y in -2...2 { fish.set(0, y, -1, abs(y) == 2 ? fin : body) }
            fish.set(0, 2, 3, fin)
        }
        let geometry = fish.geometry(size: 0.05, pivot: SIMD3(0, 0, 3))
        for i in 0..<11 {
            let node = SCNNode(geometry: geometry)
            node.categoryBitMask = TankController.Mask.decor
            node.castsShadow = false
            root.addChildNode(node)
            let offset = SIMD3<Float>((vhash(i, 0, 0, 33) - 0.5) * 1.6, (vhash(i, 1, 0, 33) - 0.5) * 0.8, (vhash(i, 2, 0, 33) - 0.5) * 0.3)
            school.append((node, offset, vhash(i, 3, 0, 33) * 6.28))
        }
        flock = biome == .rainforest
    }

    private var flock = false

    func update(time: Float, dt: Float) {
        // The school sweeps from wall to wall, turning back before the glass.
        let x = 14 * sin(time * 0.035)
        let vx = cos(time * 0.035)
        heading += ((vx >= 0 ? 1 : -1) - heading) * min(1, dt * 0.8)
        let center = SIMD3<Float>(x, (flock ? 5.6 : 4.2) + 0.3 * sin(time * 0.11), flock ? 9 : 6.2)
        let yaw = atan2(heading, 0.25 * (1 - abs(heading)) + 0.0001)
        for f in school {
            let bob = SIMD3<Float>(0, 0.08 * sin(time * 1.3 + f.phase), 0.05 * sin(time * 0.9 + f.phase))
            f.node.simdPosition = center + f.offset * SIMD3(1, 1, 1) + bob
            f.node.simdEulerAngles = SIMD3(0, yaw, 0.05 * sin(time * 6 + f.phase))
        }
    }

    /// Reef height in blocks at a column: a long, uneven ridge with tall stacks every so often.
    nonisolated static func reefHeight(_ x: Int) -> Int {
        let edge = Float(abs((x / 2) % 40)) / 40
        let n = vnoise(Float(x) * 0.06, 0, 0, 41), n2 = vnoise(Float(x) * 0.18, 1, 0, 41)
        return Int(((4 + 7 * pow(edge, 1.5) + 5 * n + 1.5 * n2) * 2).rounded())
    }

    /// The reef along the back, in fine blocks: layered rock, moss, and sponges and fans on top.
    private static func reef() -> VoxelModel {
        let m = VoxelModel()
        let rocks: [UInt32] = [0x56708A, 0x4C6680, 0x627C96, 0x445C74, 0x6A849C]
        for x in -168...168 {
            let h = reefHeight(x)
            for z in 0..<5 {
                let hz = h - (4 - z) * (1 + Int(vhash(x, z, 0, 42) * 2))
                for y in 0..<max(1, hz) {
                    let layer = vnoise(Float(x) * 0.15, Float(y) * 0.4, Float(z), 46)
                    let moss = y >= hz - 2 && vhash(x, y, z, 43) < 0.4
                    let c: UInt32 = moss ? (vhash(x, y, z, 47) < 0.5 ? 0x4E9A5E : 0x62AE6A)
                        : layer > 0.66 ? 0x3A5068 : layer < 0.25 ? 0x7A8EA4 : rocks[Int(vhash(x, y, z, 44) * Float(rocks.count))]
                    m.set(x, y, z, C(c))
                }
            }
            // Sponges, fans and little corals along the top.
            if vhash(x, 0, 0, 45) < 0.04 {
                let c: UInt32 = [0xE0805A, 0x9C6AD0, 0xF2B33A, 0xF07AA0][Int(vhash(x, 1, 0, 45) * 4)]
                for y in 0..<(3 + Int(vhash(x, 2, 0, 45) * 7)) {
                    for (dx, dz) in [(0, 2), (1, 2), (0, 3), (1, 3)] { m.set(x + dx, h + y, dz, C(c)) }
                }
            } else if vhash(x, 3, 0, 45) < 0.03 {
                let c: UInt32 = [0xB070C0, 0xE0605A, 0x5FC0A0, 0x8A7FE0][Int(vhash(x, 4, 0, 45) * 4)]
                for r in 0..<5 { for dx in -r...r where vhash(x + dx, r, 0, 48) < 0.75 { m.set(x + dx, h + r, 2, C(c)) } }
            }
        }
        return m
    }
}
