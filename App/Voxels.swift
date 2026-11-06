import AppKit
import SceneKit
import simd

/// An integer voxel coordinate.
struct V3: Hashable, Codable {
    var x: Int, y: Int, z: Int

    init(_ x: Int, _ y: Int, _ z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func + (a: V3, b: V3) -> V3 { V3(a.x + b.x, a.y + b.y, a.z + b.z) }

    subscript(axis: Int) -> Int {
        get { axis == 0 ? x : axis == 1 ? y : z }
        set {
            switch axis {
            case 0: x = newValue
            case 1: y = newValue
            default: z = newValue
            }
        }
    }

    var float: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }
}

/// The shape a block can take. Plain cubes join up into rounded blobs; the others stand alone.
enum BlockShape: UInt8, CaseIterable, Codable {
    case cube, slab, slope, stair, pillar, ball, pyramid, coin
}

/// A voxel's colour, and its shape. Glow of 100 or more draws it unlit, so it shines.
/// `turn` is quarter turns about y (0–3); add 4 to flip the block upside down.
struct VoxelColor: Hashable, Codable {
    var rgb: UInt32
    var glow: UInt8 = 0
    var shape: BlockShape = .cube
    var turn: UInt8 = 0

    init(rgb: UInt32, glow: UInt8 = 0, shape: BlockShape = .cube, turn: UInt8 = 0) {
        self.rgb = rgb
        self.glow = glow
        self.shape = shape
        self.turn = turn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rgb = try c.decode(UInt32.self, forKey: .rgb)
        glow = try c.decodeIfPresent(UInt8.self, forKey: .glow) ?? 0
        shape = try c.decodeIfPresent(BlockShape.self, forKey: .shape) ?? .cube
        turn = try c.decodeIfPresent(UInt8.self, forKey: .turn) ?? 0
    }
}

func C(_ rgb: UInt32, _ glow: UInt8 = 0) -> VoxelColor { VoxelColor(rgb: rgb, glow: glow) }

/// One voxel in a saved design. Shape and turn are left out for plain cubes.
struct VoxelEntry: Codable, Hashable {
    var x: Int, y: Int, z: Int
    var rgb: UInt32
    var glow: UInt8
    var shape: UInt8? = nil
    var turn: UInt8? = nil

    var color: VoxelColor {
        VoxelColor(rgb: rgb, glow: glow, shape: BlockShape(rawValue: shape ?? 0) ?? .cube, turn: turn ?? 0)
    }
}

/// A sparse grid of coloured cubes that turns into a SceneKit mesh of slightly rounded blocks.
final class VoxelModel {
    private(set) var voxels: [V3: VoxelColor] = [:]

    init() {}

    init(entries: [VoxelEntry]) {
        for e in entries { voxels[V3(e.x, e.y, e.z)] = e.color }
    }

    var entries: [VoxelEntry] {
        voxels.map {
            VoxelEntry(x: $0.key.x, y: $0.key.y, z: $0.key.z, rgb: $0.value.rgb, glow: $0.value.glow,
                       shape: $0.value.shape == .cube ? nil : $0.value.shape.rawValue, turn: $0.value.turn == 0 ? nil : $0.value.turn)
        }
            .sorted { ($0.z, $0.y, $0.x) < ($1.z, $1.y, $1.x) }
    }

    var count: Int { voxels.count }
    var isEmpty: Bool { voxels.isEmpty }

    subscript(p: V3) -> VoxelColor? {
        get { voxels[p] }
        set { voxels[p] = newValue }
    }

    func set(_ x: Int, _ y: Int, _ z: Int, _ c: VoxelColor) { voxels[V3(x, y, z)] = c }
    func has(_ x: Int, _ y: Int, _ z: Int) -> Bool { voxels[V3(x, y, z)] != nil }

    /// Highest occupied y in the column (x, z).
    func top(x: Int, z: Int) -> Int? { voxels.keys.filter { $0.x == x && $0.z == z }.map(\.y).max() }

    /// Lowest occupied y in the column (x, z).
    func bottom(x: Int, z: Int) -> Int? { voxels.keys.filter { $0.x == x && $0.z == z }.map(\.y).min() }

    /// Outermost occupied x on one side (sign ±1) of the row (y, z), or 0.
    func side(y: Int, z: Int, sign: Int) -> Int {
        for x in stride(from: 16, to: 0, by: -1) where has(x * sign, y, z) { return x * sign }
        return 0
    }

    var bounds: (min: V3, max: V3)? {
        guard let first = voxels.keys.first else { return nil }
        var lo = first, hi = first
        for p in voxels.keys {
            for a in 0..<3 {
                lo[a] = min(lo[a], p[a])
                hi[a] = max(hi[a], p[a])
            }
        }
        return (lo, hi)
    }

    /// The most used colour, for picking an accent.
    var dominantColor: UInt32 {
        var counts: [UInt32: Int] = [:]
        for c in voxels.values { counts[c.rgb, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? 0xFF9A1C
    }

    // MARK: - Meshing

    /// Builds rounded blocks: every cube gets its edges and corners bevelled, with normals that blend
    /// across the bevel so it shades like a soft, rounded edge. Faces between neighbours are skipped.
    /// `pivot` (in voxel units) becomes the mesh origin; `jitter` varies brightness per block.
    func geometry(size: Float, pivot: SIMD3<Float>, bevel: Float = 0.16, jitter: Float = 0.06) -> SCNGeometry {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var lit: [UInt32] = []
        var glow: [UInt32] = []
        let h: Float = 0.5, i: Float = 0.5 - bevel

        for (p, c) in voxels {
            func filled(_ d: V3) -> Bool { voxels[p + d]?.shape == .cube }
            let shade = 1 + (vhash(p.x, p.y, p.z) - 0.5) * 2 * jitter
            var rgb = SIMD3<Float>(Float((c.rgb >> 16) & 0xFF), Float((c.rgb >> 8) & 0xFF), Float(c.rgb & 0xFF)) / 255 * shade
            // A touch more colour than the raw palette, so everything reads a little brighter.
            let grey = simd_dot(rgb, SIMD3(0.299, 0.587, 0.114))
            rgb = simd_mix(SIMD3(repeating: grey), rgb, SIMD3(repeating: 1.22)) * 1.03
            let color = SIMD4<Float>(simd_clamp(rgb, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1)), 1)
            let center = (p.float - pivot) * size
            let glowing = c.glow >= 100

            func emit(_ pts: [SIMD3<Float>], _ ns: [SIMD3<Float>]) {
                let base = UInt32(positions.count)
                for k in pts.indices {
                    positions.append(SCNVector3(center + pts[k] * size))
                    normals.append(SCNVector3(ns[k]))
                    colors.append(color)
                }
                // Every piece lies on the outside of the cube, so its centroid points outward.
                let centroid = pts.reduce(SIMD3<Float>(repeating: 0), +) / Float(pts.count)
                for k in 1..<(pts.count - 1) {
                    var tri = [base, base + UInt32(k), base + UInt32(k + 1)]
                    if simd_dot(simd_cross(pts[k] - pts[0], pts[k + 1] - pts[0]), centroid) < 0 { tri.swapAt(1, 2) }
                    if glowing { glow += tri } else { lit += tri }
                }
            }

            func axis(_ a: Int, _ s: Int) -> V3 {
                var d = V3(0, 0, 0)
                d[a] = s
                return d
            }
            func unit(_ a: Int, _ s: Int) -> SIMD3<Float> {
                var n = SIMD3<Float>(repeating: 0)
                n[a] = Float(s)
                return n
            }

            // Shaped blocks are flat-shaded solids of their own.
            if c.shape != .cube {
                for face in BlockShapes.faces(c.shape, turn: c.turn) {
                    let base = UInt32(positions.count)
                    for q in face.points {
                        positions.append(SCNVector3(center + q * size))
                        normals.append(SCNVector3(face.normal))
                        colors.append(color)
                    }
                    for k in 1..<(face.points.count - 1) {
                        let tri = [base, base + UInt32(k), base + UInt32(k + 1)]
                        if glowing { glow += tri } else { lit += tri }
                    }
                }
                continue
            }

            // Faces, inset by the bevel.
            for a in 0..<3 {
                for s in [-1, 1] where !filled(axis(a, s)) {
                    let b = (a + 1) % 3, e = (a + 2) % 3
                    let pts: [SIMD3<Float>] = [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { u, v in
                        var q = SIMD3<Float>(repeating: 0)
                        q[a] = Float(s) * h
                        q[b] = Float(u) * i
                        q[e] = Float(v) * i
                        return q
                    }
                    let n = unit(a, s)
                    emit(pts, [n, n, n, n])
                }
            }

            // Edge bevels, unless both neighbours and the diagonal fill the space.
            for a1 in 0..<3 {
                for a2 in (a1 + 1)..<3 {
                    for s1 in [-1, 1] {
                        for s2 in [-1, 1] {
                            let d1 = axis(a1, s1), d2 = axis(a2, s2)
                            if filled(d1) && filled(d2) && filled(d1 + d2) { continue }
                            let a3 = 3 - a1 - a2
                            func P(_ f1: Float, _ f2: Float, _ f3: Float) -> SIMD3<Float> {
                                var q = SIMD3<Float>(repeating: 0)
                                q[a1] = Float(s1) * f1
                                q[a2] = Float(s2) * f2
                                q[a3] = f3
                                return q
                            }
                            let n1 = unit(a1, s1), n2 = unit(a2, s2)
                            emit([P(h, i, -i), P(h, i, i), P(i, h, i), P(i, h, -i)], [n1, n1, n2, n2])
                        }
                    }
                }
            }

            // Corner triangles, unless the whole octant around the corner is filled.
            for sx in [-1, 1] {
                for sy in [-1, 1] {
                    for sz in [-1, 1] {
                        var enclosed = true
                        for dx in [0, sx] {
                            for dy in [0, sy] {
                                for dz in [0, sz] where dx != 0 || dy != 0 || dz != 0 {
                                    if !filled(V3(dx, dy, dz)) { enclosed = false }
                                }
                            }
                        }
                        if enclosed { continue }
                        let fx = Float(sx), fy = Float(sy), fz = Float(sz)
                        emit([SIMD3(fx * h, fy * i, fz * i), SIMD3(fx * i, fy * h, fz * i), SIMD3(fx * i, fy * i, fz * h)],
                             [SIMD3(fx, 0, 0), SIMD3(0, fy, 0), SIMD3(0, 0, fz)])
                    }
                }
            }
        }

        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let sources = [
            SCNGeometrySource(vertices: positions),
            SCNGeometrySource(normals: normals),
            SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                              componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride),
        ]
        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []
        if !lit.isEmpty {
            elements.append(SCNGeometryElement(indices: lit, primitiveType: .triangles))
            materials.append(Materials.lit)
        }
        if !glow.isEmpty {
            elements.append(SCNGeometryElement(indices: glow, primitiveType: .triangles))
            materials.append(Materials.glow)
        }
        let geometry = SCNGeometry(sources: sources, elements: elements)
        geometry.materials = materials
        return geometry
    }
}

enum Materials {
    /// Vertex-coloured, softly shiny.
    static let lit: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = NSColor.white
        m.specular.contents = NSColor(white: 0.22, alpha: 1)
        m.shininess = 0.35
        return m
    }()

    /// Vertex-coloured, ignores lighting.
    static let glow: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        return m
    }()
}

// MARK: - Noise

/// A stable pseudo-random value in [0, 1) for a grid position.
func vhash(_ x: Int, _ y: Int, _ z: Int, _ seed: Int = 0) -> Float {
    var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ z &* 2147483647 &+ seed &* 144665)
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Float(h & 0xFFFFFF) / 16777216
}

/// Smooth value noise in [0, 1).
func vnoise(_ x: Float, _ y: Float, _ z: Float, _ seed: Int = 0) -> Float {
    let xi = Int(floor(x)), yi = Int(floor(y)), zi = Int(floor(z))
    func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }
    let xf = smooth(x - Float(xi)), yf = smooth(y - Float(yi)), zf = smooth(z - Float(zi))
    func layer(_ dz: Int) -> Float {
        let a = simd_mix(vhash(xi, yi, zi + dz, seed), vhash(xi + 1, yi, zi + dz, seed), xf)
        let b = simd_mix(vhash(xi, yi + 1, zi + dz, seed), vhash(xi + 1, yi + 1, zi + dz, seed), xf)
        return simd_mix(a, b, yf)
    }
    return simd_mix(layer(0), layer(1), zf)
}

extension SCNVector3 {
    init(_ v: SIMD3<Float>) { self.init(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)) }
}

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }

    var rgb: UInt32 {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }
}

// MARK: - Block shapes

/// The faces of each block shape, in a unit cell centred on the origin, wound so they face outward.
enum BlockShapes {
    struct Face {
        var points: [SIMD3<Float>]
        var normal: SIMD3<Float>
    }

    nonisolated(unsafe) private static var cache: [Int: [Face]] = [:]

    static func faces(_ shape: BlockShape, turn: UInt8) -> [Face] {
        let key = Int(shape.rawValue) * 8 + Int(turn & 7)
        if let f = cache[key] { return f }
        let angle = Float(turn & 3) * .pi / 2, flip = turn & 4 != 0
        let (cs, sn) = (cos(angle), sin(angle))
        func move(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let r = SIMD3(v.x * cs + v.z * sn, v.y, -v.x * sn + v.z * cs)
            return flip ? SIMD3(r.x, -r.y, r.z) : r
        }
        let f = solids(shape).flatMap { solid -> [Face] in
            let mid = solid.flatMap { $0 }.reduce(SIMD3<Float>(repeating: 0), +) / Float(solid.flatMap { $0 }.count)
            return solid.map { poly in
                var pts = poly.map(move)
                var n = simd_normalize(simd_cross(pts[1] - pts[0], pts[2] - pts[0]))
                let centre = pts.reduce(SIMD3<Float>(repeating: 0), +) / Float(pts.count)
                if simd_dot(n, centre - move(mid)) < 0 {
                    pts.reverse()
                    n = -n
                }
                return Face(points: pts, normal: n)
            }
        }
        cache[key] = f
        return f
    }

    /// Each shape as one or more convex solids, each a list of polygons.
    private static func solids(_ shape: BlockShape) -> [[[SIMD3<Float>]]] {
        let h: Float = 0.5
        switch shape {
        case .cube: return [box(SIMD3(-h, -h, -h), SIMD3(h, h, h))]
        case .slab: return [box(SIMD3(-h, -h, -h), SIMD3(h, 0, h))]
        case .coin: return [prism(sides: 10, radius: 0.42, y0: -h, y1: -0.32)]
        case .pillar: return [prism(sides: 8, radius: 0.26, y0: -h, y1: h)]
        case .stair: return [box(SIMD3(-h, -h, -h), SIMD3(h, 0, h)), box(SIMD3(-h, 0, 0), SIMD3(h, h, h))]
        case .slope:
            // Rises from the front (−z) to the back (+z).
            let a = SIMD3(-h, -h, -h), b = SIMD3(h, -h, -h), c = SIMD3(h, -h, h), d = SIMD3(-h, -h, h)
            let e = SIMD3(-h, h, h), f = SIMD3(h, h, h)
            return [[[a, b, c, d], [d, c, f, e], [a, b, f, e], [a, d, e], [b, c, f]]]
        case .pyramid:
            let a = SIMD3(-h, -h, -h), b = SIMD3(h, -h, -h), c = SIMD3(h, -h, h), d = SIMD3(-h, -h, h), top = SIMD3<Float>(0, h, 0)
            return [[[a, b, c, d], [a, b, top], [b, c, top], [c, d, top], [d, a, top]]]
        case .ball:
            var polys: [[SIMD3<Float>]] = []
            let rings = 5, segs = 8, r: Float = 0.5
            func p(_ i: Int, _ j: Int) -> SIMD3<Float> {
                let t = Float(i) / Float(rings) * .pi, u = Float(j) / Float(segs) * 2 * .pi
                return SIMD3(sin(t) * cos(u), cos(t), sin(t) * sin(u)) * r
            }
            for i in 0..<rings {
                for j in 0..<segs {
                    if i == 0 { polys.append([p(0, 0), p(1, j), p(1, j + 1)]) }
                    else if i == rings - 1 { polys.append([p(i, j), p(i, j + 1), p(rings, 0)]) }
                    else { polys.append([p(i, j), p(i, j + 1), p(i + 1, j + 1), p(i + 1, j)]) }
                }
            }
            return [polys]
        }
    }

    private static func box(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> [[SIMD3<Float>]] {
        func v(_ x: Bool, _ y: Bool, _ z: Bool) -> SIMD3<Float> { SIMD3(x ? hi.x : lo.x, y ? hi.y : lo.y, z ? hi.z : lo.z) }
        return [
            [v(false, false, false), v(true, false, false), v(true, false, true), v(false, false, true)],
            [v(false, true, false), v(true, true, false), v(true, true, true), v(false, true, true)],
            [v(false, false, false), v(true, false, false), v(true, true, false), v(false, true, false)],
            [v(false, false, true), v(true, false, true), v(true, true, true), v(false, true, true)],
            [v(false, false, false), v(false, false, true), v(false, true, true), v(false, true, false)],
            [v(true, false, false), v(true, false, true), v(true, true, true), v(true, true, false)],
        ]
    }

    private static func prism(sides: Int, radius: Float, y0: Float, y1: Float) -> [[SIMD3<Float>]] {
        let ring = (0..<sides).map { i -> SIMD2<Float> in
            let a = Float(i) / Float(sides) * 2 * .pi
            return SIMD2(cos(a), sin(a)) * radius
        }
        var polys = [ring.map { SIMD3($0.x, y0, $0.y) }, ring.map { SIMD3($0.x, y1, $0.y) }]
        for i in 0..<sides {
            let a = ring[i], b = ring[(i + 1) % sides]
            polys.append([SIMD3(a.x, y0, a.y), SIMD3(b.x, y0, b.y), SIMD3(b.x, y1, b.y), SIMD3(a.x, y1, a.y)])
        }
        return polys
    }
}
