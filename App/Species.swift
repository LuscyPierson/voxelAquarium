import SceneKit

/// A fish someone designed in the editor (or a copy of a built-in), as saved to disk.
struct FishDesign: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "New Fish"
    var blurb = "Designed by you."
    var voxelSize: Float = 0.07
    var speed: Float = 1
    var wag: Float = 7
    var wagAngle: Float = 22
    var depthMin: Float = 0.2
    var depthMax: Float = 0.8
    var schooling = false
    var puffs = false
    var body: [VoxelEntry] = []
    var tail: [VoxelEntry] = []
}

/// One kind of creature: how it looks (body and tail voxel models) and how it swims.
/// Models face +z, with y up and x across the body; the tail hangs off the back (z ≤ 0 in its own space).
final class Species: Identifiable {
    var key: String
    var id: String { key }
    var name: String
    var blurb: String
    var accent: UInt32
    var voxelSize: Float = 0.07
    var speed: Float = 1, turn: Float = 2.2, wag: Float = 7, wagAngle: Float = 22
    var depth: (min: Float, max: Float) = (0.15, 0.85)
    var schooling = false, puffs = false, flukes = false
    var designID: UUID?
    var length = 0

    /// How it moves through the ocean.
    enum Motion { case swim, drift, kraken, walk }
    var motion = Motion.swim
    /// Made of jelly: drawn glossy and see-through.
    var jelly = false
    /// Fish get out of the way of sharks (and krakens).
    var scary = false
    /// Arcs up and down as it swims, like a dolphin.
    var porpoise = false
    /// Visitors that pass straight through rather than hanging around.
    var cruiser = false
    /// Room it takes up on screen, so the ocean never gets crowded.
    var crowd: Float = 1
    /// Hanging chains (jelly tentacles, kraken arms): where they attach, in body voxels, and their segments.
    var tentacles: [Tentacle] = []
    /// How far tentacles fan out from the body at rest (radians).
    var splay: Float = 0.25
    /// Rolls onto its side towards the viewer while swimming (rays, so you see their backs).
    var bank: Float = 0
    /// Spines that stand up when it puffs (pufferfish).
    var spikes: VoxelModel?
    /// Wings (the right one; the left is its mirror image), hinged at `wingJoint` in body voxels, flapping
    /// `flap` times a second through `flapAngle` degrees.
    var wings: VoxelModel?
    var wingJoint = SIMD3<Float>(0, 0, 0)
    var flap: Float = 8, flapAngle: Float = 35
    /// Walkers: hop along (frogs) rather than trot, or hang from the branch along the top (sloths, monkeys).
    var hops = false, hangs = false
    /// Swamp creatures that live above the water line: floating on top of it (ducks) or flying over it.
    var floats = false, flies = false
    /// Forest fish, which keep to the river along the front.
    var aquatic = false

    struct Tentacle {
        var anchor: SIMD3<Float>
        var segments: [VoxelModel]
        var segmentLength: Float
        var curl: Float = 1
    }

    let body = VoxelModel()
    let tail = VoxelModel()

    init(key: String, name: String, blurb: String, accent: UInt32) {
        self.key = key
        self.name = name
        self.blurb = blurb
        self.accent = accent
    }

    convenience init(design d: FishDesign) {
        self.init(key: "custom-\(d.id.uuidString.lowercased())", name: d.name, blurb: d.blurb, accent: 0)
        designID = d.id
        voxelSize = d.voxelSize
        speed = d.speed
        wag = d.wag
        wagAngle = d.wagAngle
        depth = (d.depthMin, d.depthMax)
        schooling = d.schooling
        puffs = d.puffs
        for e in d.body { body.set(e.x, e.y, e.z, e.color) }
        for e in d.tail { tail.set(e.x, e.y, e.z, e.color) }
        accent = body.dominantColor
    }

    var isCustom: Bool { designID != nil }

    /// An editable copy of this species.
    func design(named newName: String? = nil) -> FishDesign {
        FishDesign(id: designID ?? UUID(), name: newName ?? name, blurb: blurb, voxelSize: voxelSize, speed: speed,
                   wag: wag, wagAngle: wagAngle, depthMin: depth.min, depthMax: depth.max, schooling: schooling,
                   puffs: puffs, body: body.entries, tail: tail.entries)
    }

    var zCenter: Float {
        guard let b = body.bounds else { return 0 }
        return Float(b.min.z + b.max.z) / 2
    }

    /// Local z of the back of the body, where the tail hinges.
    var tailJointZ: Float {
        guard let b = body.bounds else { return 0 }
        return (Float(b.min.z) - 0.5 - zCenter) * voxelSize
    }

    /// Where a body voxel position ends up in the model's local space.
    func local(_ p: SIMD3<Float>) -> SIMD3<Float> { (p - SIMD3(0, 0, zCenter)) * voxelSize }

    private(set) lazy var bodyGeometry = body.geometry(size: voxelSize, pivot: SIMD3(0, 0, zCenter))
    private(set) lazy var tailGeometry = tail.geometry(size: voxelSize, pivot: SIMD3(0, 0, 0.5))

    var accentColor: NSColor { NSColor(rgb: accent) }
}

// MARK: - Built-in species

enum Builtins {
    static func clownfish() -> Species {
        let d = Species(key: "clownfish", name: "Clownfish", blurb: "Bold, bouncy, loves to show off its stripes.", accent: 0xFF7A1A)
        d.speed = 1.1; d.wag = 9; d.depth = (0.2, 0.75)
        let orange = C(0xFF7A1A), white = C(0xF8F8F2), black = C(0x15151B), belly = C(0xFFA352)
        let bands: [(Float, Float)] = [(0.78, 0.06), (0.48, 0.065), (0.16, 0.05)]
        loft(d, 13, 3.3, 1.9) { t, _, y, h, _ in
            for (center, half) in bands {
                let dist = abs(t - center)
                if dist < half { return white }
                if dist < half + 0.045 { return black }
            }
            return Float(y) < -h * 0.45 ? belly : orange
        }
        fin(d, 0.25, 0.85, up: true, height: { 1.4 + sin($0 * .pi) }) { _, k, n in k == n ? black : orange }
        fin(d, 0.3, 0.55, up: false, height: { _ in 1.2 }) { _, k, n in k == n ? black : orange }
        pectoral(d, 9, -1, orange)
        tailFan(d, 4, span: { (-1 - $0 * 2.2, 1 + $0 * 2.2) }) { u, _ in u > 0.8 ? black : orange }
        eye(d, 11, 1)
        return d
    }

    static func blueTang() -> Species {
        let d = Species(key: "bluetang", name: "Blue Tang", blurb: "Bright blue, a little forgetful, always swimming.", accent: 0x2F6BFF)
        d.speed = 1.3; d.wag = 8; d.depth = (0.25, 0.9)
        let blue = C(0x2457E8), light = C(0x5C93FF), black = C(0x10131C), yellow = C(0xFFD23A)
        loft(d, 15, 4.2, 1.4, b: 0.95, p: 0.55) { t, _, yi, h, _ in
            let y = Float(yi)
            if t < 0.08 { return yellow }
            if y >= h * 0.82 { return black }
            let inSpot = sq((t - 0.55) / 0.12) + sq((y - h * 0.22) / (h * 0.16)) < 1
            if t > 0.22 && t < 0.86 && y >= h * 0.02 && y <= h * 0.55 && !inSpot { return black }
            return y < -h * 0.5 ? light : blue
        }
        fin(d, 0.2, 0.92, up: true, height: { _ in 1.4 }) { _, k, n in k == n ? light : black }
        fin(d, 0.25, 0.75, up: false, height: { _ in 1.2 }) { _, k, n in k == n ? light : black }
        tailFan(d, 4, span: { (-1 - $0 * 3, 1 + $0 * 3) }) { u, y in u > 0.6 && abs(Float(y)) < (u - 0.6) * 6 ? nil : yellow }
        eye(d, 13, 1, big: true)
        return d
    }

    static func angelfish() -> Species {
        let d = Species(key: "angelfish", name: "Angelfish", blurb: "Tall, striped and terribly graceful.", accent: 0xD5D9E0)
        d.speed = 0.6; d.turn = 1.5; d.wag = 4; d.wagAngle = 16; d.depth = (0.3, 0.85)
        let silver = C(0xD5D9E0), finColor = C(0xBFC6D2), black = C(0x1E1E24), gold = C(0xE8DDA8)
        let stripes: [Float] = [0.3, 0.6, 0.86]
        func stripe(_ t: Float) -> Bool { stripes.contains { abs(t - $0) < 0.06 } }
        loft(d, 9, 3.2, 1, a: 0.15, b: 0.9, p: 0.7) { t, _, y, h, _ in
            stripe(t) ? black : t > 0.7 && Float(y) > h * 0.55 ? gold : silver
        }
        fin(d, 0.12, 0.75, up: true, height: { 1.5 + 4.5 * (1 - $0) }) { t, _, _ in stripe(t) ? black : finColor }
        fin(d, 0.12, 0.7, up: false, height: { 1.5 + 5 * (1 - $0) }) { t, _, _ in stripe(t) ? black : finColor }
        tailFan(d, 3, span: { (-1.5 - $0 * 1.5, 1.5 + $0 * 1.5) }) { u, _ in u < 0.3 ? black : finColor }
        eye(d, 7, 1)
        return d
    }

    static func pufferfish() -> Species {
        let d = Species(key: "pufferfish", name: "Pufferfish", blurb: "Shy and spotty. Poke it and watch it puff up!", accent: 0xC9A15E)
        d.speed = 0.55; d.wag = 9; d.wagAngle = 15; d.depth = (0.1, 0.7); d.puffs = true
        let tan = C(0xC9A15E), spot = C(0x6B4A22), belly = C(0xF4EEDC)
        loft(d, 10, 3.2, 2.9, a: 0.12, b: 0.92, p: 0.4, wp: 0.45) { t, x, y, h, _ in
            if Float(y) < -h * 0.3 { return belly }
            return vhash(x, y, Int((t * 100).rounded()), 7) < 0.2 ? spot : tan
        }
        fin(d, 0.2, 0.32, up: true, height: { _ in 1 }) { _, _, _ in tan }
        pectoral(d, 7, 0, tan)
        tailFan(d, 2, span: { (-1 - $0, 1 + $0) }) { _, _ in tan }
        eye(d, 8, 1, big: true)
        // Spines all over, standing out from the body; they only show when it puffs.
        let spikes = VoxelModel(), spine = C(0xEFE3BF)
        let center = SIMD3<Float>(0, 0, Float(d.length) / 2)
        for (p, _) in d.body.voxels where vhash(p.x, p.y, p.z, 19) < 0.16 {
            let out = SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)) - center
            let step = SIMD3<Int>(Int(out.x.sign == .minus ? -1 : 1) * (abs(out.x) > 0.5 ? 1 : 0),
                                  Int(out.y.sign == .minus ? -1 : 1) * (abs(out.y) > 0.5 ? 1 : 0),
                                  abs(out.z) > 3 ? Int(out.z.sign == .minus ? -1 : 1) : 0)
            let q = SIMD3(p.x, p.y, p.z) &+ step
            if !d.body.has(q.x, q.y, q.z) { spikes.set(q.x, q.y, q.z, spine) }
        }
        d.spikes = spikes
        return d
    }

    // MARK: - Builders

    static func sq(_ v: Float) -> Float { v * v }

    /// Lofts an elliptical body along z. t runs from the tail (0) to the nose (1); height and width
    /// follow a sine bulge between a and b, sharpened by p and wp. Paint gets (t, x, y, halfHeight, halfWidth).
    static func loft(_ d: Species, _ len: Int, _ height: Float, _ width: Float,
                             a: Float = 0.08, b: Float = 0.93, p: Float = 0.6, wp: Float = 0.6,
                             paint: (Float, Int, Int, Float, Float) -> VoxelColor) {
        d.length = len
        for l in 0..<len {
            let t = (Float(l) + 0.5) / Float(len)
            let s = sin(.pi * (a + (b - a) * t))
            let h = max(0.7, height * pow(s, p))
            let w = max(0.6, width * pow(s, wp))
            let hy = Int(h.rounded(.up)), wx = Int(w.rounded(.up))
            for y in -hy...hy {
                for x in -wx...wx where sq(Float(y) / h) + sq(Float(x) / w) <= 1.15 {
                    d.body.set(x, y, l, paint(t, x, y, h, w))
                }
            }
        }
    }

    /// A one-voxel-thick fin along the top (or bottom) of the body between t0 and t1.
    static func fin(_ d: Species, _ t0: Float, _ t1: Float, up: Bool, height: (Float) -> Float,
                            color: (Float, Int, Int) -> VoxelColor) {
        let l0 = Int((t0 * Float(d.length)).rounded(.up)), l1 = Int((t1 * Float(d.length)).rounded(.down))
        guard l0 <= l1 else { return }
        for l in l0...l1 {
            let t = (Float(l) + 0.5) / Float(d.length)
            let u = l1 == l0 ? 0.5 : Float(l - l0) / Float(l1 - l0)
            let n = max(1, Int(height(u).rounded()))
            guard let edge = up ? d.body.top(x: 0, z: l) : d.body.bottom(x: 0, z: l) else { continue }
            for k in 1...n { d.body.set(0, up ? edge + k : edge - k, l, color(t, k, n)) }
        }
    }

    /// Small side fins just behind the head.
    static func pectoral(_ d: Species, _ l: Int, _ y: Int, _ c: VoxelColor) {
        for s in [-1, 1] {
            let x = d.body.side(y: y, z: l, sign: s) + s
            d.body.set(x, y, l, c)
            d.body.set(x, y, l - 1, c)
            d.body.set(x, y - 1, l - 1, c)
        }
    }

    /// The tail fan, its own model so it can wag. Row i goes backwards from the hinge; nil skips a voxel.
    static func tailFan(_ d: Species, _ len: Int, span: (Float) -> (Float, Float), color: (Float, Int) -> VoxelColor?) {
        for i in 0..<len {
            let u = (Float(i) + 0.5) / Float(len)
            let (lo, hi) = span(u)
            for y in Int(lo.rounded())...Int(hi.rounded()) {
                if let c = color(u, y) { d.tail.set(0, y, -i, c) }
            }
        }
    }

    static func eye(_ d: Species, _ l: Int, _ y: Int, big: Bool = false) {
        let black = C(0x0A0A0E), glint = C(0xFFFFFF, 255)
        for s in [-1, 1] {
            func put(_ z: Int, _ yy: Int, _ c: VoxelColor) {
                let x = d.body.side(y: yy, z: z, sign: s)
                d.body.set(x == 0 ? s : x, yy, z, c)
            }
            put(l, y, black)
            if big {
                put(l - 1, y, black)
                put(l - 1, y + 1, black)
                put(l, y + 1, glint)
            }
        }
    }
}
