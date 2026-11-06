import SceneKit
import simd

/// The ocean: a seafloor diorama under open water. Creatures drift in from off screen, hang around,
/// play, and leave again. Now and then a shark cruises through and everyone scatters (nobody gets eaten).
@MainActor
final class TankController {
    static let front: Float = -2.7
    static let swimBottom: Float = 1.0, swimTop: Float = 5.3
    /// The swamp is half above water, half below: this is the water line.
    static let waterLevel: Float = 3.0
    /// Where bubbles pop.
    static var surface: Float { Biome.current == .swamp ? waterLevel : 5.9 }

    /// The heights a creature keeps between: the whole view in the sea and the forest; in the swamp, fish
    /// stay under the water line and fliers above it.
    static func band(_ s: Species) -> (lo: Float, hi: Float) {
        switch Biome.current {
        case .ocean: return (swimBottom, swimTop)
        case .swamp: return s.flies ? (waterLevel + 0.6, 5.7) : (swimBottom, waterLevel - 0.3)
        case .rainforest:
            // River fish keep under the surface; birds keep above the bank and the water.
            return s.aquatic ? (0.45, Rainforest.riverLevel - 0.25) : (Rainforest.riverLevel + 1.1, 5.4)
        }
    }

    /// How far back a creature swims: the river is only the front of the forest floor.
    static func lane(_ s: Species) -> ClosedRange<Float> {
        Biome.current == .rainforest && s.aquatic ? -1.9...(Rainforest.bankEdge - 0.4) : swimZ
    }
    static let swimZ: ClosedRange<Float> = -1.9...2.7
    /// How full the ocean gets (sardines count a little, a kraken a lot).
    static let crowdTarget: Float = 7, crowdLimit: Float = 10

    enum Mask {
        static let decor = 1, actor = 2, wall = 4, chest = 8, effect = 16
        static let scenery = decor | wall | chest
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private(set) var creatures: [Creature] = []
    private var bubbles: [Bubble] = []
    private var ripples: [SandRipple] = []
    private var hearts: [Heart] = []
    private let chests: [Chest]
    private let seaweed: [Seaweed]
    private let ocean: OceanLife
    private let vent: SIMD3<Float>?
    private let water: (level: Float, back: Float)?
    private var splashes: [Splash] = []
    let biome: Biome
    private(set) var time: Float = 0
    private var parallax = SIMD2<Float>(0, 0)
    /// Half the width of the view at the middle of the water, so visitors can start and finish off screen.
    private(set) var viewHalfWidth: Float = 9

    weak var view: SCNView?
    var parallaxTarget = SIMD2<Float>(0, 0)
    var onPoke: ((Creature) -> Void)?

    /// The creature the camera has moved in on, if any. `closeness` eases between the normal view (0) and the close-up (1).
    private(set) var focus: Creature?
    private var closeness: Float = 0
    private var focusPoint = SIMD3<Float>(repeating: 0), focusDistance: Float = 2, focusYaw: Float = 0
    /// Turns the close-up's aim angles into an orientation.
    private let aimer = SCNNode()
    var inCloseUp: Bool { focus != nil }
    var onChest: (() -> Void)?

    /// No sharks: none arrive, and any already here swim off.
    var noSharks = false {
        didSet { if noSharks { for c in creatures where c.isShark { c.leave() } } }
    }

    private var nextSpawn: Float = 2, nextPlay: Float = 12, nextVent: Float = 0, nextPeek: Float = .random(in: 20...45)
    private var tentacles: [ReefTentacle] = []
    /// A kraken that peeked and decided to come on through: when, and where.
    private var krakenComing: (at: Float, x: Float)?
    private var sharkReadyAt: Float = .random(in: 50...150), krakenReadyAt: Float = .random(in: 300...700)

    init(biome: Biome = .ocean) {
        self.biome = biome
        Biome.current = biome
        scene.background.contents = NSColor(rgb: biome.background)
        scene.fogColor = NSColor(rgb: biome.fog.color)
        scene.fogStartDistance = biome.fog.start
        scene.fogEndDistance = biome.fog.end
        scene.fogDensityExponent = 1.2

        let camera = SCNCamera()
        camera.fieldOfView = 36
        camera.zNear = 0.1
        camera.zFar = 120
        camera.wantsHDR = false
        // Soft focus: the creatures are sharp, the far ocean melts into a blur.
        camera.wantsDepthOfField = true
        camera.fStop = 0.8
        camera.focalBlurSampleCount = 16
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        Self.fit(cameraNode, aspect: 16 / 10, parallax: .zero)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = biome.ambient.color
        ambient.light!.intensity = biome.ambient.intensity
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.9, alpha: 1)
        light.intensity = 930
        light.castsShadow = true
        light.shadowMode = .forward
        light.shadowColor = NSColor(white: 0, alpha: 0.32)
        light.shadowMapSize = CGSize(width: 4096, height: 4096)
        light.shadowSampleCount = 8
        light.shadowRadius = 3
        light.orthographicScale = 16
        light.zNear = 1
        light.zFar = 50
        sun.light = light
        sun.simdPosition = SIMD3(4, 16, -7)
        sun.look(at: SCNVector3(0, 1, 0.5))
        scene.rootNode.addChildNode(sun)

        let built = TankDecor.build(into: scene.rootNode, biome: biome)
        chests = built.chests
        seaweed = built.seaweed
        vent = built.vent
        water = built.water
        ocean = OceanLife(root: scene.rootNode, biome: biome)
        populate()
    }

    /// Places a camera on the middle of the water; wider windows see more ocean to the sides.
    static func fit(_ node: SCNNode, aspect: Float, parallax: SIMD2<Float>) {
        let centerY: Float = 3.5, halfHeight: Float = 2.7, minHalfWidth: Float = 5
        let fov = Float(node.camera?.fieldOfView ?? 36)
        let t = tan(fov * 0.5 * .pi / 180)
        let d = max(halfHeight / t, minHalfWidth / (t * max(0.1, aspect)))
        // Raised a little and looking down about 10°, so the floor and everything on it shows more.
        let tilt: Float = 10 * .pi / 180
        let position = SIMD3<Float>(parallax.x, centerY + d * tan(tilt) + parallax.y, front - d)
        node.simdPosition = position
        // Aim with explicit angles: look(at:) can't turn a node a full 180° to face +z.
        let to = SIMD3<Float>(0, centerY, 0) - position
        node.simdEulerAngles = SIMD3(asin(to.y / simd_length(to)), atan2(-to.x, -to.z), 0)
        node.camera?.focusDistance = CGFloat(simd_length(to) + 0.5)
    }

    // MARK: - Frame

    func step(dt rawDt: Float) {
        let dt = min(rawDt, 0.1)
        time += dt

        parallax += (parallaxTarget - parallax) * min(1, dt * 2.5)
        var aspect: Float = 16 / 10
        if let view, view.bounds.height > 0 { aspect = Float(view.bounds.width / view.bounds.height) }
        Self.fit(cameraNode, aspect: aspect, parallax: parallax)
        let fov = Float(cameraNode.camera?.fieldOfView ?? 36)
        viewHalfWidth = -cameraNode.simdPosition.z * tan(fov * 0.5 * .pi / 180) * aspect
        updateCloseUp(dt: dt)

        if time > nextVent {
            nextVent = time + Float.random(in: 0.2...0.5)
            if let vent { spawnBubble(vent + jitter(0.05)) }
            for chest in chests where chest.isOpen(at: time) {
                spawnBubble(chest.node.simdPosition + SIMD3(0, 0.6, 0) + jitter(0.3))
            }
        }

        direct()
        for c in creatures { c.update(dt: dt, ocean: self) }
        creatures.removeAll { c in
            guard c.done else { return false }
            c.node.removeFromParentNode()
            return true
        }
        for b in bubbles { b.update(dt: dt, time: time) }
        bubbles.removeAll { b in
            if b.node.simdPosition.y > Self.surface { b.node.removeFromParentNode(); return true }
            return false
        }
        for h in hearts { h.update(dt: dt, camera: cameraNode) }
        hearts.removeAll { h in
            if h.age > 1.2 { h.node.removeFromParentNode(); return true }
            return false
        }
        for t in tentacles { t.update(time: time) }
        tentacles.removeAll { t in
            if t.finished { t.node.removeFromParentNode(); return true }
            return false
        }
        for s in splashes { s.update(dt: dt) }
        splashes.removeAll { s in
            if s.finished { s.node.removeFromParentNode(); return true }
            return false
        }
        for r in ripples { r.update(dt: dt) }
        ripples.removeAll { r in
            if r.finished { r.node.removeFromParentNode(); return true }
            return false
        }
        for w in seaweed { w.update(time: time) }
        for chest in chests { chest.update(time: time, dt: dt) }
        ocean.update(time: time, dt: dt)
    }

    // MARK: - Director

    var crowd: Float { creatures.filter { !$0.leaving }.reduce(0) { $0 + $1.species.crowd } }
    private var threatened: Bool { creatures.contains { $0.species.scary && !$0.done } || !tentacles.isEmpty }

    private func direct() {
        // Anything scary on screen sends the fish nearby swimming off.
        for t in creatures where t.species.scary && !t.peeking && abs(t.position.x) < viewHalfWidth + 1 {
            let reach: Float = t.species.motion == .kraken ? 7 : 4.5
            for c in creatures where !c.species.scary && !c.fleeing && !c.peeking && simd_distance(c.position, t.position) < reach {
                c.flee(from: t.position, ocean: self)
            }
        }

        if time > nextPlay {
            nextPlay = time + Float.random(in: 10...22)
            startPlay()
        }

        if time > nextPeek {
            nextPeek = time + Float.random(in: 40...100)
            peek()
        }

        if let k = krakenComing, time > k.at {
            krakenComing = nil
            if let s = Roster.species("kraken") {
                spawn(s, count: 1, atX: k.x)
                krakenReadyAt = time + Float.random(in: 600...1500)
            }
        }

        if time > nextSpawn {
            nextSpawn = time + Float.random(in: 3...8)
            if crowd < Self.crowdTarget { spawnVisitors() }
        }
    }

    /// Picks the next visitor: mostly fish, rarely a shark, very rarely the kraken.
    private func spawnVisitors() {
        let scaryOK = !threatened
        let choices = Roster.entries.filter { e in
            if e.shark { return scaryOK && !noSharks && time > sharkReadyAt }
            if e.key == "kraken" { return scaryOK && time > krakenReadyAt }
            return true
        }
        let total = choices.reduce(0) { $0 + $1.weight }
        var pick = Double.random(in: 0..<total)
        guard let entry = choices.first(where: { pick -= $0.weight; return pick < 0 }) else { return }
        let fun = entry.fun != nil && Double.random(in: 0..<1) < Roster.funChance
        guard let species = Roster.species(fun ? entry.funKey : entry.key) else { return }
        let room = Self.crowdLimit - crowd
        let count = min(Int.random(in: entry.group), Int(room / species.crowd))
        guard count > 0 else { return }
        spawn(species, count: count)
        if entry.shark { sharkReadyAt = time + Float.random(in: 150...360) }
        if entry.key == "kraken" { krakenReadyAt = time + Float.random(in: 600...1500) }
    }

    // MARK: - Peeking over the reef

    enum Peek: CaseIterable { case fish, krakenEye, tentacles }

    /// Something looks over the back reef: a fish, the kraken's eye, or a few of its tentacles.
    /// Now and then whatever it is comes on through. Pass a kind (and `through`) to make it happen.
    func peek(_ kind: Peek? = nil, through forced: Bool? = nil) {
        if biome != .ocean { return peekElsewhere(big: kind.map { $0 != .fish }, through: forced) }
        let krakenOK = kind != nil || (!threatened && krakenComing == nil)
        // Peek where the reef is tall, so whatever's behind it stays hidden until it rises.
        let w = max(2, viewHalfWidth - 1.5)
        let x = (0..<12).map { _ in Float.random(in: -w...w) }.max { OceanLife.reefTop($0) < OceanLife.reefTop($1) } ?? 0
        let top = OceanLife.reefTop(x)
        let z = OceanLife.reefBase.z + 0.9
        let roll = Float.random(in: 0..<1)
        let chosen = kind ?? (krakenOK && roll > 0.72 ? .krakenEye : krakenOK && roll > 0.45 ? .tentacles : .fish)
        let through = forced ?? (Float.random(in: 0..<1) < 0.35)
        let krakenMayCome = forced ?? (through && time > krakenReadyAt - 300)

        if chosen == .krakenEye, let k = Roster.species("kraken") {
            // Its eyes come up over the reef and look around.
            let c = Creature(species: k, at: SIMD3(x, top - 3.2, z + 0.5), heading: 1, leader: nil, offset: .zero, ocean: self)
            c.startPeek(top: top - 0.85, until: time + Float.random(in: 7...10), through: krakenMayCome)
            scene.rootNode.addChildNode(c.node)
            creatures.append(c)
        } else if chosen == .tentacles {
            // A few tentacles curl up over the reef and wave about.
            let n = Int.random(in: 1...3)
            for i in 0..<n {
                let tx = x + (Float(i) - Float(n - 1) / 2) * Float.random(in: 0.8...1.3)
                tentacles.append(ReefTentacle(root: scene.rootNode, at: SIMD3(tx, OceanLife.reefTop(tx), z + 0.2),
                                              time: time + Float(i) * 0.6, stay: Float.random(in: 6...9)))
            }
            if krakenMayCome { krakenComing = (time + 16, x) }
        } else {
            // A fish pops its head over the top.
            let fish = Roster.entries.filter { !$0.shark && $0.key != "kraken" }.compactMap { e -> (RosterEntry, Species)? in
                guard let s = Roster.species(e.key), s.motion == .swim, s.length * Int(s.voxelSize * 100) < 200 else { return nil }
                return (e, s)
            }
            let total = fish.reduce(0) { $0 + $1.0.weight }
            var pick = Double.random(in: 0..<max(0.001, total))
            guard let (_, s) = fish.first(where: { pick -= $0.0.weight; return pick < 0 }) else { return }
            let c = Creature(species: s, at: SIMD3(x, top - 1.2, z), heading: Bool.random() ? 1 : -1, leader: nil, offset: .zero, ocean: self)
            c.startPeek(top: top + 0.15, until: time + Float.random(in: 4...7), through: through)
            scene.rootNode.addChildNode(c.node)
            creatures.append(c)
        }
    }

    func krakenComesThrough(x: Float) { krakenComing = (time + 4, x) }

    /// In the swamp and the forest: one of the locals looks over the bank (or the log). The "big" peek is the
    /// alligator's eyes or a jaguar's ears, which is rare and never happens with "no sharks" on.
    private func peekElsewhere(big forcedBig: Bool?, through forced: Bool?) {
        let w = max(2, viewHalfWidth - 1.5)
        let x = (0..<12).map { _ in Float.random(in: -w...w) }.max { OceanLife.reefTop($0) < OceanLife.reefTop($1) } ?? 0
        let top = OceanLife.reefTop(x)
        let z = OceanLife.reefBase.z + 0.9
        let peekers = Roster.entries.filter(\.peeks)
        let big = forcedBig ?? (!threatened && !noSharks && time > sharkReadyAt && Float.random(in: 0..<1) < 0.25)
        let pool = peekers.filter { $0.shark == big }
        let total = pool.reduce(0) { $0 + $1.weight }
        var pick = Double.random(in: 0..<max(0.001, total))
        guard let e = pool.first(where: { pick -= $0.weight; return pick < 0 }) ?? pool.first,
              let s = Roster.species(e.key) else { return }
        let through = forced ?? (Float.random(in: 0..<1) < (big ? 0.5 : 0.35))
        // Walkers stand behind it with just their heads showing; swimmers and fliers look over the top.
        let height = Float((s.body.bounds?.max.y ?? 0) - (s.body.bounds?.min.y ?? 0) + 1) * s.voxelSize
        let rest = s.motion == .walk && !s.hangs ? top - height * 0.6 : big ? top + 0.02 : top + 0.15
        let c = Creature(species: s, at: SIMD3(x, rest - 1.4, z), heading: Bool.random() ? 1 : -1, leader: nil, offset: .zero, ocean: self)
        c.startPeek(top: rest, until: time + Float.random(in: 4...8), through: through)
        scene.rootNode.addChildNode(c.node)
        creatures.append(c)
        if big { sharkReadyAt = time + Float.random(in: 150...360) }
    }

    /// A few visitors already here when the app opens.
    private func populate() {
        let calm = Roster.entries.filter { !$0.shark && $0.key != "kraken" }
        let total = calm.reduce(0) { $0 + $1.weight }
        var placed: Float = 0
        while placed < 6 {
            var pick = Double.random(in: 0..<total)
            guard let e = calm.first(where: { pick -= $0.weight; return pick < 0 }), let s = Roster.species(e.key) else { break }
            let n = Int.random(in: e.group)
            spawn(s, count: n, onScreen: true)
            placed += Float(n) * s.crowd
        }
    }

    /// Brings in a group, from off one side of the screen (or already in view).
    @discardableResult
    func spawn(_ species: Species, count: Int = 1, onScreen: Bool = false, atX: Float? = nil) -> [Creature] {
        let side: Float = Bool.random() ? 1 : -1
        let margin = 2 + Float(species.length) * species.voxelSize
        var start: SIMD3<Float>
        if species.motion == .kraken {
            let range = max(0.5, min(4, viewHalfWidth - 3))
            start = SIMD3(atX.map { max(-range, min(range, $0)) } ?? Float.random(in: -range...range), -6.5, 2.6)
        } else if species.motion == .walk {
            let x = onScreen ? Float.random(in: -(viewHalfWidth - 2)...(viewHalfWidth - 2)) : side * (viewHalfWidth + margin)
            let z = Creature.walkZ(species)
            start = SIMD3(x, Creature.restY(species, x: x, z: z), z)
        } else {
            let depth = Float.random(in: species.depth.min...max(species.depth.min, species.depth.max))
            let band = Self.band(species)
            let y = band.lo + (band.hi - band.lo) * depth
            let x = onScreen ? Float.random(in: -(viewHalfWidth - 2)...(viewHalfWidth - 2)) : side * (viewHalfWidth + margin)
            start = SIMD3(x, y, Float.random(in: Self.lane(species)))
        }
        var group: [Creature] = []
        for i in 0..<max(1, count) {
            let spread = SIMD3<Float>(0.9, 0.45, 0.6) * (species.schooling ? 1 : 1.6)
            let offset = i == 0 ? SIMD3<Float>(repeating: 0)
                : SIMD3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * spread
            let o = species.motion == .walk ? SIMD3(offset.x * 1.4, 0, 0) : offset
            let c = Creature(species: species, at: start + o, heading: -side, leader: group.first, offset: o, ocean: self)
            if onScreen { c.heading = Bool.random() ? 1 : -1 }
            scene.rootNode.addChildNode(c.node)
            creatures.append(c)
            group.append(c)
        }
        return group
    }

    /// Something playful: a little group swirls, a fish loops, or one chases another.
    private func startPlay() {
        let players = creatures.filter {
            $0.species.motion == .swim && !$0.species.scary && !$0.leaving && !$0.species.cruiser && abs($0.position.x) < viewHalfWidth - 1
        }
        guard let first = players.randomElement() else { return }
        let until = time + Float.random(in: 7...13)
        let leader = first.leader ?? first
        let group = players.filter { $0 === leader || $0.leader === leader }
        switch Int.random(in: 0..<3) {
        case 0:
            for (i, c) in group.enumerated() { c.play(.swirl, around: first.position, partner: nil, until: until, phase: Float(i) * 0.9) }
        case 1:
            first.play(.loop, around: first.position, partner: nil, until: time + Float.random(in: 4...6), phase: 0)
        default:
            if let other = players.filter({ $0 !== first && simd_distance($0.position, first.position) < 5 }).randomElement() {
                first.play(.chase, around: first.position, partner: other, until: until, phase: 0)
                other.play(.swirl, around: other.position, partner: nil, until: until, phase: 0)
            } else {
                for (i, c) in group.enumerated() { c.play(.swirl, around: first.position, partner: nil, until: until, phase: Float(i) * 0.9) }
            }
        }
    }

    /// Visitors of a species swim off (after an edit in the Fish Editor, say).
    func refresh(_ species: Species) {
        for c in creatures where c.species.key == species.key { c.leave() }
    }

    func clear() { for c in creatures { c.leave() } }

    // MARK: - Taps

    /// A click: say hi to a creature, open a chest, ripple the sand, or just make a few bubbles.
    @discardableResult
    func tap(at point: CGPoint) -> Creature? {
        guard let view else { return nil }
        let hits = view.hitTest(point, options: [
            .categoryBitMask: Mask.actor | Mask.chest | Mask.decor,
            .searchMode: SCNHitTestSearchMode.all.rawValue,
        ])
        let near = SIMD3<Float>(view.unprojectPoint(SCNVector3(point.x, point.y, 0)))
        let far = SIMD3<Float>(view.unprojectPoint(SCNVector3(point.x, point.y, 1)))
        // Where the click meets the water's surface, if it does before anything solid (creatures always win).
        var onWater: SIMD3<Float>?
        if let water, abs(far.y - near.y) > 0.0001 {
            let t = (water.level - near.y) / (far.y - near.y)
            let p = near + (far - near) * t
            if t > 0, t < 1, p.z > Self.front, p.z < water.back { onWater = p }
        }
        let first = hits.first.map { SIMD3<Float>($0.worldCoordinates) }
        let hitsCreature = hits.first.map { h in creatures.contains { c in
            var n: SCNNode? = h.node
            while let x = n { if x === c.node { return true }; n = x.parent }
            return false
        } } ?? false
        if let p = onWater, !hitsCreature, first.map({ simd_distance($0, near) > simd_distance(p, near) }) ?? true {
            splash(at: p)
            return nil
        }
        if let hit = hits.first {
            if hit.node.name == "Sand" {
                rippleSand(at: SIMD3<Float>(hit.worldCoordinates))
                return nil
            }
            var node: SCNNode? = hit.node
            while let n = node {
                if let c = creatures.first(where: { $0.node === n }) {
                    c.poke(from: SIMD3<Float>(hit.worldCoordinates) + jitter(0.4), ocean: self)
                    spawnHeart(c.position + SIMD3(0, 0.5, 0))
                    burst(at: c.position, count: 4, spread: 0.2)
                    onPoke?(c)
                    return c
                }
                if let chest = chests.first(where: { $0.node === n }) {
                    chest.open(at: time)
                    burst(at: chest.node.simdPosition + SIMD3(0, 0.6, 0), count: 24, spread: 0.35)
                    onChest?()
                    return nil
                }
                node = n.parent
            }
        }
        let dir = far - near
        guard abs(dir.z) > 0.0001 else { return nil }
        let t = -near.z / dir.z
        if t > 0 { burst(at: near + dir * t, count: 5, spread: 0.15) }
        return nil
    }

    /// The creature under a point in the view, if any.
    func creature(at point: CGPoint) -> Creature? {
        guard let view else { return nil }
        for hit in view.hitTest(point, options: [.categoryBitMask: Mask.actor, .searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let n = node {
                if let c = creatures.first(where: { $0.node === n }) { return c }
                node = n.parent
            }
        }
        return nil
    }

    // MARK: - Close-up

    /// Glide the camera in on one creature and follow it; it stays around while you look.
    func closeUp(on c: Creature) {
        focus = c
        if closeness == 0 {
            focusPoint = c.position
            focusYaw = 0
        }
        let size = c.species.body.bounds.map { b in Float(max(b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z) + 1) } ?? 10
        focusDistance = min(c.species.motion == .kraken ? 9 : 6, max(1.6, size * c.species.voxelSize * 3.2 + 0.9))
    }

    func endCloseUp() { focus = nil }

    private func updateCloseUp(dt: Float) {
        if let f = focus, f.done || !creatures.contains(where: { $0 === f }) { focus = nil }
        closeness = focus == nil ? max(0, closeness - dt * 1.2) : min(1, closeness + dt * 1.2)
        if let f = focus {
            focusPoint += (f.position - focusPoint) * min(1, dt * 4)
            f.linger(now: time)
            // Swing about 15° round towards the way it's facing, so you see its face as well as its side.
            let target: Float = (f.heading >= 0 ? -15 : 15) * .pi / 180
            focusYaw += (target - focusYaw) * min(1, dt * 1.5)
        }
        guard closeness > 0 else { return }
        let e = closeness * closeness * (3 - 2 * closeness)
        // The creature sits left of centre, leaving room for its card on the right (+x is screen left).
        let d = focusDistance
        let turn = simd_quatf(angle: focusYaw, axis: SIMD3(0, 1, 0))
        let aim = focusPoint + turn.act(SIMD3(-d * 0.2, 0, 0))
        let eye = aim + turn.act(SIMD3(0, d * 0.18, -d))
        let to = aim - eye
        aimer.simdEulerAngles = SIMD3(asin(to.y / simd_length(to)), atan2(-to.x, -to.z), 0)
        let near = aimer.simdOrientation
        let normal = cameraNode.simdOrientation
        cameraNode.simdPosition = simd_mix(cameraNode.simdPosition, eye, SIMD3(repeating: e))
        cameraNode.simdOrientation = simd_slerp(normal, near, e)
        let far = Float(cameraNode.camera?.focusDistance ?? 10)
        cameraNode.camera?.focusDistance = CGFloat(far + (simd_length(to) - far) * e)
    }

    /// A tap on the water: drops jump up, a ring of surface blocks bobs outwards, and anything close by startles.
    func splash(at p: SIMD3<Float>) {
        let s = Splash(at: p)
        scene.rootNode.addChildNode(s.node)
        splashes.append(s)
        for c in creatures where !c.peeking && simd_distance(c.position, p) < 1.6 {
            c.poke(from: p, ocean: self)
        }
    }

    func rippleSand(at p: SIMD3<Float>) {
        let r = SandRipple(at: p)
        scene.rootNode.addChildNode(r.node)
        ripples.append(r)
    }

    /// Where a creature appears in the view, in SwiftUI coordinates (top-left origin).
    func screenPoint(of c: Creature, above: Float = 0.55) -> CGPoint? {
        guard let view else { return nil }
        let p = view.projectPoint(SCNVector3(c.position + SIMD3(0, above, 0)))
        guard p.z > 0, p.z < 1 else { return nil }
        return CGPoint(x: p.x, y: view.bounds.height - p.y)
    }

    // MARK: - Effects

    func burst(at p: SIMD3<Float>, count: Int, spread: Float) {
        for _ in 0..<count { spawnBubble(p + jitter(spread)) }
    }

    private func spawnBubble(_ p: SIMD3<Float>) {
        let b = Bubble(at: p)
        scene.rootNode.addChildNode(b.node)
        bubbles.append(b)
    }

    private func spawnHeart(_ p: SIMD3<Float>) {
        let h = Heart(at: p)
        scene.rootNode.addChildNode(h.node)
        hearts.append(h)
    }

    func jitter(_ r: Float) -> SIMD3<Float> {
        SIMD3(Float.random(in: -r...r), Float.random(in: -r...r), Float.random(in: -r...r))
    }
}

// MARK: - Creatures

/// One visitor. Wanders while it's here, joins in when there's play, follows its group,
/// scatters from sharks, and swims off the edge of the world when it's had enough.
@MainActor
final class Creature {
    enum Play { case swirl, loop, chase }

    let id = UUID()
    let species: Species
    let node = SCNNode()
    private let rig: CreatureRig
    private let litMaterial: SCNMaterial
    private(set) weak var leader: Creature?
    private let offset: SIMD3<Float>

    var heading: Float
    private(set) var leaving = false, fleeing = false, done = false
    private(set) var dir: SIMD3<Float>
    private var speed: Float
    private var target = SIMD3<Float>(repeating: 0)
    private var retargetAt: Float = 0, stayUntil: Float, startleUntil: Float = 0, puffUntil: Float = 0
    private var play: Play?, playUntil: Float = 0, playCenter = SIMD3<Float>(repeating: 0), playPhase: Float = 0
    private weak var partner: Creature?
    private var phase: Float = 0, flash: Float = 0
    private let seed = Float.random(in: 0..<100)
    private let born: Float
    private var sinkAt: Float?
    /// Peeking over the back reef: rise until just showing, look around, then duck back down or come through.
    private var peek: (top: Float, until: Float, through: Bool)?
    /// How fast it's currently turning (eases in and out, so turns are curves), its lean into the turn,
    /// and how hard its tail is working.
    private var turnSpeed: Float = 0, roll: Float = 0, effort: Float = 1
    /// Walkers: how far along the current hop, when it stops for a rest, where it walks (depth), and a jump from a poke.
    private var hop: Float = 0, restUntil: Float = 0, lane: Float = 0, jump: Float = 0

    var position: SIMD3<Float> { node.simdPosition }
    var peeking: Bool { peek != nil }

    func startPeek(top: Float, until: Float, through: Bool) { peek = (top, until, through) }
    var isShark: Bool { Roster.entry(for: species.key)?.shark ?? false }

    init(species: Species, at position: SIMD3<Float>, heading: Float, leader: Creature?, offset: SIMD3<Float>, ocean: TankController) {
        self.species = species
        self.heading = heading
        self.leader = leader
        self.offset = offset
        born = ocean.time
        speed = species.speed
        dir = SIMD3(heading, 0, 0)
        // Cruisers pass straight through; others hang around a while first.
        stayUntil = species.cruiser ? ocean.time : ocean.time + Float.random(in: 18...55)
        let lit = Materials.lit.copy() as! SCNMaterial
        litMaterial = lit
        rig = CreatureRig(species) { $0 === Materials.lit ? lit : $0 }
        rig.set(mask: TankController.Mask.actor)
        node.name = species.name
        node.categoryBitMask = TankController.Mask.actor
        node.simdPosition = position
        node.addChildNode(rig.model)
        node.simdOrientation = species.motion == .swim ? Self.look(dir) : Self.facing
        if species.motion == .walk {
            lane = Self.walkZ(species)
            node.simdOrientation = Self.look(SIMD3(heading, 0, -0.3))
        }
    }

    /// Where a walker walks: anywhere across the front of the floor, or along the branch if it hangs.
    static func walkZ(_ s: Species) -> Float {
        if s.hangs { return Rainforest.branchZ }
        // In the forest the ground is the bank behind the river.
        if Biome.current == .rainforest { return Float.random(in: (Rainforest.bankEdge + 0.4)...(OceanLife.reefBase.z - 0.7)) }
        return Float.random(in: -1.0...1.6)
    }

    /// Height of a walker's origin when it's standing on the floor (or hanging from the branch) at x, z.
    static func restY(_ s: Species, x: Float, z: Float) -> Float {
        guard let b = s.body.bounds else { return TankDecor.floor(x, z) }
        if s.hangs { return Rainforest.branchY(x) - 0.12 - (Float(b.max.y) + 0.5) * s.voxelSize }
        // Floaters ride low in the water, a quarter of their height under the surface.
        if s.floats { return TankController.waterLevel - (Float(b.min.y) - 0.5 + Float(b.max.y - b.min.y + 1) * 0.25) * s.voxelSize }
        return TankDecor.floor(x, z) - (Float(b.min.y) - 0.5) * s.voxelSize
    }

    /// Facing the viewer (models point along +z; the camera looks along +z).
    private static let facing = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))

    /// Keeps it from wandering off while the camera is on it.
    func linger(now: Float) { stayUntil = max(stayUntil, now + 6) }

    func leave() {
        guard !leaving else { return }
        leaving = true
        if species.motion == .swim, abs(dir.x) > 0.2 { heading = dir.x > 0 ? 1 : -1 }
    }

    func flee(from threat: SIMD3<Float>, ocean: TankController) {
        fleeing = true
        leaving = true
        play = nil
        heading = position.x >= threat.x ? 1 : -1
        startleUntil = ocean.time + 1.5
    }

    func play(_ kind: Play, around center: SIMD3<Float>, partner: Creature?, until: Float, phase: Float) {
        play = kind
        playCenter = center
        self.partner = partner
        playUntil = until
        playPhase = phase
    }

    func update(dt: Float, ocean: TankController) {
        if peek != nil {
            updatePeek(dt: dt, ocean: ocean)
            return
        }
        switch species.motion {
        case .kraken: updateKraken(dt: dt, ocean: ocean)
        case .drift: updateDrift(dt: dt, ocean: ocean)
        case .swim: updateSwim(dt: dt, ocean: ocean)
        case .walk: updateWalk(dt: dt, ocean: ocean)
        }
        if flash > 0 {
            flash = max(0, flash - dt * 2.5)
            litMaterial.emission.contents = NSColor(white: CGFloat(flash * 0.6), alpha: 1)
        }
        // Gone once it's well off the side of the screen.
        let margin = 3 + Float(species.length) * species.voxelSize
        let off = abs(position.x) - ocean.viewHalfWidth
        if species.motion != .kraken && (off > margin + 8 || (leaving && off > margin)) { done = true }
    }

    private func updateSwim(dt: Float, ocean: TankController) {
        let now = ocean.time
        let startled = now < startleUntil, puffed = now < puffUntil
        var pos = position
        if play != nil && now > playUntil { play = nil }
        if let leader, leader.leaving, !leaving {
            leaving = true
            heading = leader.heading
            fleeing = leader.fleeing
        }
        if !leaving && leader == nil && now > stayUntil { leave() }

        var goal: SIMD3<Float>
        var pace: Float = 1
        let w = ocean.viewHalfWidth
        if leaving {
            goal = SIMD3(heading * (w + 20), pos.y + sin(now * 0.4 + seed) * 0.6, pos.z)
            pace = fleeing ? 2.6 : species.cruiser ? 1 : 1.2
        } else if let play {
            let t = (now + playPhase) * 2.2
            switch play {
            case .swirl: goal = playCenter + SIMD3(cos(t) * 1.1, sin(t * 0.5) * 0.3, sin(t) * 0.7)
            case .loop: goal = playCenter + SIMD3(cos(t * 1.3) * 0.9, sin(t * 1.3) * 0.9, 0)
            case .chase: goal = partner?.position ?? playCenter
            }
            pace = 1.6
        } else if let leader {
            // Trail a little behind and beside the leader, matching its direction.
            goal = leader.position - leader.dir * (0.35 + abs(offset.x) * 0.8) + SIMD3(0, offset.y, offset.z)
            let gap = simd_distance(pos, goal)
            pace = gap > 1 ? 1.5 : 0.85 + gap * 0.5
        } else {
            if now > retargetAt || simd_distance_squared(target, pos) < 0.3 {
                let depth = Float.random(in: species.depth.min...max(species.depth.min, species.depth.max))
                let band = TankController.band(species)
                target = SIMD3(Float.random(in: -(w - 1.5)...(w - 1.5)),
                               band.lo + (band.hi - band.lo) * depth,
                               Float.random(in: TankController.lane(species)))
                retargetAt = now + Float.random(in: 5...12)
            }
            goal = target
        }

        var wanted = goal - pos + SIMD3(0.0001, 0, 0)
        // Keep to the water: above the sand, below the surface, between the reef and the front.
        let band = TankController.band(species)
        if pos.y < band.lo + 0.3 { wanted.y += 2 }
        if pos.y > band.hi { wanted.y -= 2 }
        let lane = TankController.lane(species)
        if pos.z < lane.lowerBound { wanted.z += 2 }
        if pos.z > lane.upperBound { wanted.z -= 2 }
        wanted.y *= 0.5
        if let leader { wanted = wanted * 0.7 + leader.dir * 0.3 }
        // A gentle meander, so nobody swims in a dead straight line.
        wanted += SIMD3(0, sin(now * 0.5 + seed) * 0.08, cos(now * 0.37 + seed) * 0.12)
        wanted = simd_normalize(wanted)

        // Turning speed eases up and back down, so turns are smooth arcs rather than snaps.
        let off = acos(max(-1, min(1, simd_dot(dir, wanted))))
        let maxTurn = species.turn * (startled ? 2.5 : play != nil ? 1.6 : 1)
        turnSpeed += (min(maxTurn, off * 2) - turnSpeed) * min(1, dt * (startled ? 8 : 3))
        let before = dir
        dir = Self.rotate(dir, toward: wanted, by: turnSpeed * dt)
        dir.y = max(-0.45, min(0.45, dir.y))
        dir = simd_normalize(dir)
        // Lean into the turn.
        let yawRate = simd_cross(before, dir).y / max(dt, 0.0001)
        roll += (max(-0.4, min(0.4, -yawRate * 0.3)) - roll) * min(1, dt * 3)

        // Small reef fish swim in little bursts and glides; big cruisers keep a steady pace.
        let cruise = species.speed * (0.85 + 0.3 * vnoise(seed, now * 0.2, 0))
        let kicks = species.cruiser || species.schooling || leader != nil ? 1
            : 0.7 + 0.6 * pow(max(0, sin(now * (1.2 + seed.truncatingRemainder(dividingBy: 0.5)) + seed)), 2)
        let desired = cruise * pace * kicks * (startled ? 1.8 : 1) * (puffed ? 0.25 : 1)
        let accel = dt * (startled ? 6 : 1.2) * max(0.5, species.speed)
        speed += max(-accel, min(accel, desired - speed))

        var move = dir * speed * dt
        if species.porpoise { move.y += cos(now * 1.4 + seed) * 0.5 * dt }
        pos += move
        pos.y = max(band.lo - 0.2, min(band.hi + 0.3, pos.y))
        if species.aquatic { pos.z = min(pos.z, lane.upperBound + 0.2) }
        node.simdPosition = pos
        let lean = simd_quatf(angle: roll, axis: SIMD3(0, 0, 1))
        node.simdOrientation = simd_slerp(node.simdOrientation, Self.look(dir) * lean, min(1, dt * 4))

        // The tail beats faster and harder when it's speeding up or turning, softer when gliding.
        let work = max(0.35, min(1.6, desired / max(0.1, cruise) + turnSpeed * 0.3 + (desired > speed ? 0.3 : 0)))
        effort += (work - effort) * min(1, dt * 2.5)
        phase += dt * species.wag * (0.35 + 0.65 * speed / max(0.1, species.speed)) * (0.7 + 0.3 * effort)
        let wag = sin(phase) * effort
        rig.pose(time: now, wag: wag)
        // The head sways a beat behind the tail, so the whole body ripples.
        // Rays roll their backs towards the viewer (the camera looks along +z, from -z).
        let side = simd_act(node.simdOrientation, SIMD3<Float>(1, 0, 0))
        rig.model.simdEulerAngles = SIMD3(0, -sin(phase - 1.2) * effort * 4 * .pi / 180, species.bank * side.z)

        let puff: SIMD3<Float> = puffed ? SIMD3(1.9, 1.85, 1.35) : SIMD3(repeating: 1)
        rig.model.simdScale += (puff - rig.model.simdScale) * min(1, dt * (puffed ? 10 : 2))
        if let spikes = rig.spikes {
            spikes.opacity += ((puffed ? 1 : 0) - spikes.opacity) * CGFloat(min(1, dt * (puffed ? 8 : 3)))
        }
    }

    private func updatePeek(dt: Float, ocean: TankController) {
        guard let p = peek else { return }
        let now = ocean.time
        var pos = position
        let look = sin(now * 0.7 + seed)
        if now < p.until {
            // Up to just above the reef, bobbing, glancing one way and the other.
            pos.y += (p.top + sin(now * 1.3 + seed) * 0.05 - pos.y) * min(1, dt * 1.2)
        } else if p.through && species.motion == .walk {
            // Over the top and down to the floor (or up to the branch).
            peek = nil
            dir = SIMD3(heading, 0, 0)
            restUntil = 0
            stayUntil = now + Float.random(in: 15...40)
            return
        } else if p.through && species.motion == .swim {
            // Over the top and into the open water.
            peek = nil
            dir = simd_normalize(SIMD3(heading, 0.45, -0.6))
            target = SIMD3(pos.x + heading * 2, max(pos.y + 0.8, TankController.swimBottom + 1), 1.2)
            retargetAt = now + 4
            stayUntil = now + Float.random(in: 15...40)
            return
        } else {
            // Duck back down behind the reef.
            pos.y -= dt * (species.motion == .kraken ? 0.8 : 1.2)
            if pos.y < p.top - (species.motion == .kraken ? 3.4 : 1.6) {
                done = true
                if p.through && species.motion == .kraken { ocean.krakenComesThrough(x: pos.x) }
            }
        }
        node.simdPosition = pos
        if species.motion == .kraken {
            node.simdOrientation = Self.facing * simd_quatf(angle: look * 0.45, axis: SIMD3(0, 1, 0))
            rig.pose(time: now, wag: 0)
        } else {
            // Side-on, turning its head towards the viewer now and then.
            dir = simd_normalize(SIMD3(heading, 0, -0.35 - 0.35 * max(0, look)))
            node.simdOrientation = simd_slerp(node.simdOrientation, Self.look(dir), min(1, dt * 3))
            phase += dt * species.wag * 0.4
            rig.pose(time: now, wag: sin(phase) * 0.5)
        }
    }

    /// Walking along the floor, hopping, or hanging from the branch: wanders back and forth, stops for a rest now
    /// and then, and walks off the side when it's done.
    private func updateWalk(dt: Float, ocean: TankController) {
        let now = ocean.time
        let w = ocean.viewHalfWidth
        var pos = position
        if !leaving && now > stayUntil { leave() }
        if !leaving {
            // Turn back at the edges; now and then stop for a breather, or change its mind.
            if abs(pos.x) > w - 1.2 && pos.x * heading > 0 { heading = -heading }
            if now > retargetAt {
                retargetAt = now + Float.random(in: 4...10)
                if Float.random(in: 0..<1) < 0.45 { restUntil = now + Float.random(in: 1.5...4) }
                else if Float.random(in: 0..<1) < 0.3 { heading = -heading }
            }
        }
        let resting = !leaving && now < restUntil
        let pace: Float = fleeing ? 2.4 : leaving ? 1.2 : 1
        var stride = resting ? 0 : species.speed * pace
        var lift: Float = 0
        if species.hops {
            // Hop, land, sit, hop again: it only moves while it's in the air.
            if !resting || hop.truncatingRemainder(dividingBy: 1) > 0.02 { hop += dt * (fleeing ? 2 : 1.25) }
            let f = hop.truncatingRemainder(dividingBy: 1)
            let air = f < 0.42
            lift = air ? sin(f / 0.42 * .pi) * 0.22 : 0
            stride = air ? species.speed * pace * 2.6 : 0
        }
        jump = max(0, jump - dt * 2.2)
        lift += sin(min(1, jump) * .pi) * 0.3

        pos.x += heading * stride * dt
        pos.z += (lane - pos.z) * min(1, dt * 1.2)
        var ground = Self.restY(species, x: pos.x, z: pos.z)
        // Coming over the wall from behind: stay up on top of it until well clear, then drop down.
        if pos.z > OceanLife.reefBase.z - 0.6 && !species.hangs && !species.floats { ground = max(ground, OceanLife.reefTop(pos.x) + 0.05) }
        pos.y += (ground + lift - pos.y) * min(1, dt * (species.hops ? 14 : 6))
        node.simdPosition = pos
        dir = SIMD3(heading, 0, 0)
        node.simdOrientation = simd_slerp(node.simdOrientation, Self.look(SIMD3(heading, 0, -0.3)), min(1, dt * 3))

        // A gait: legs (or tail) swing with the stride, and the body bobs; hangers sway from their arms.
        phase += dt * species.wag * (resting ? 0.25 : 0.6 + 0.6 * stride / max(0.05, species.speed))
        rig.pose(time: now, wag: sin(phase))
        if species.hangs {
            rig.model.simdEulerAngles = SIMD3(0, 0, sin(phase * 0.5) * (resting ? 0.04 : 0.12))
        } else if species.floats {
            // Bobbing on the ripples.
            rig.model.simdPosition.y = sin(now * 1.6 + seed) * 0.018
            rig.model.simdEulerAngles = SIMD3(sin(now * 1.1 + seed) * 0.05, 0, 0)
        } else if !species.hops {
            rig.model.simdPosition.y = abs(sin(phase)) * (resting ? 0 : 0.025)
        }
    }

    /// Jellies: pulse, rise a little with each pulse, sink slowly, and drift with the current.
    private func updateDrift(dt: Float, ocean: TankController) {
        let now = ocean.time
        if !leaving && now > stayUntil + 40 { leave() }
        let pulse = max(0, sin(now * 1.5 + seed))
        var pos = position
        pos.x += heading * species.speed * (leaving ? 1.6 : 1) * (fleeing ? 2.5 : 1) * dt
        pos.y += (pulse * 0.32 - 0.1) * dt
        let band = TankController.band(species)
        pos.y = max(band.lo + 0.6, min(band.hi - 0.2, pos.y))
        pos.z += sin(now * 0.2 + seed) * 0.05 * dt
        node.simdPosition = pos
        node.simdOrientation = Self.facing * simd_quatf(angle: sin(now * 0.3 + seed) * 0.4, axis: SIMD3(0, 1, 0))
        if species.jelly || !species.tentacles.isEmpty {
            rig.model.simdScale = SIMD3(1 + pulse * 0.08, 1 - pulse * 0.1, 1 + pulse * 0.08)
        }
        rig.pose(time: now, wag: 0, pulse: pulse)
    }

    /// The kraken rises from behind the sea floor, has a look around, and sinks back down.
    private func updateKraken(dt: Float, ocean: TankController) {
        let age = ocean.time - born
        let rise: Float = 7, stay: Float = 30, sink: Float = 8
        let top: Float = 0.6, bottom: Float = -6.5
        let y: Float
        if age < rise {
            y = bottom + (top - bottom) * smooth(age / rise)
        } else if age < rise + stay && !leaving {
            y = top + sin(age * 0.6) * 0.15
        } else {
            if sinkAt == nil { sinkAt = ocean.time }
            leaving = true
            let s = ocean.time - sinkAt!
            y = top + (bottom - 0.5 - top) * smooth(min(1, s / sink))
            if s > sink { done = true }
        }
        node.simdPosition.y = y
        node.simdOrientation = Self.facing * simd_quatf(angle: sin(age * 0.25) * 0.35, axis: SIMD3(0, 1, 0))
        rig.pose(time: ocean.time, wag: 0)
    }

    private func smooth(_ t: Float) -> Float {
        let c = max(0, min(1, t))
        return c * c * (3 - 2 * c)
    }

    /// Tapped: a flash and a dart away, a pufferfish puffs, everyone else just glows a moment.
    func poke(from: SIMD3<Float>, ocean: TankController) {
        flash = 1
        if species.puffs {
            puffUntil = ocean.time + 3.5
            speed = 0
            return
        }
        if species.motion == .walk {
            jump = 1
            return
        }
        guard species.motion == .swim else { return }
        var away = position - from
        away.z *= 0.3
        if simd_length_squared(away) < 0.01 { away = -dir }
        away = simd_normalize(away)
        target = position + away * 3
        retargetAt = ocean.time + 2
        dir = simd_normalize(dir + away)
        startleUntil = ocean.time + 1
    }

    static func rotate(_ from: SIMD3<Float>, toward to: SIMD3<Float>, by maxAngle: Float) -> SIMD3<Float> {
        let angle = acos(max(-1, min(1, simd_dot(from, to))))
        if angle <= maxAngle || angle < 0.0001 { return to }
        var axis = simd_cross(from, to)
        if simd_length_squared(axis) < 1e-8 { axis = SIMD3(0, 1, 0) }
        return simd_act(simd_quatf(angle: maxAngle, axis: simd_normalize(axis)), from)
    }

    /// Rotation that points the model's +z along `dir`, staying upright.
    static func look(_ dir: SIMD3<Float>) -> simd_quatf {
        let f = simd_normalize(dir)
        var r = simd_cross(SIMD3<Float>(0, 1, 0), f)
        if simd_length_squared(r) < 1e-6 { r = SIMD3(1, 0, 0) }
        r = simd_normalize(r)
        let u = simd_cross(f, r)
        return simd_quatf(simd_float3x3(columns: (r, u, f)))
    }
}

// MARK: - Little things

/// One of the kraken's arms, curling up over the back reef for a feel around before slipping away again.
@MainActor
final class ReefTentacle {
    let node = SCNNode()
    private var segments: [SCNNode] = []
    private let start: Float, stay: Float, base: SIMD3<Float>, phase = Float.random(in: 0..<6.28), curl: Float
    private(set) var finished = false
    private static let size: Float = 0.13, count = 10, len = 3
    private static var length: Float { Float(count * len) * size }

    init(root: SCNNode, at top: SIMD3<Float>, time: Float, stay: Float) {
        start = time
        self.stay = stay
        curl = (Bool.random() ? 1 : -1) * Float.random(in: 0.7...1.2)
        let red = C(0xA3203A), spot = C(0x7A1528), sucker = C(0xF1C9B0)
        let arm = Builtins.tentacle(at: .zero, count: Self.count, len: Self.len, width: { $0 < 4 ? 3 : $0 < 8 ? 2 : 1 }) { i, y, side in
            side == 0 && y == 1 ? sucker : (i + y) % 4 == 0 ? spot : red
        }
        // Starts fully hidden behind the reef, tip just under the top.
        base = SIMD3(top.x, top.y - Self.length - 0.2, top.z)
        node.simdPosition = base
        // Arms hang downwards; flip it so it reaches up.
        node.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3(0, 0, 1))
        node.isHidden = true
        var parent = node
        for (k, seg) in arm.segments.enumerated() {
            let sw = Float(seg.bounds.map { $0.max.x - $0.min.x + 1 } ?? 1)
            let n = SCNNode(geometry: seg.geometry(size: Self.size, pivot: SIMD3((sw - 1) / 2, 0.5, (sw - 1) / 2)))
            n.simdPosition = k == 0 ? .zero : SIMD3(0, -Float(Self.len) * Self.size, 0)
            n.categoryBitMask = TankController.Mask.actor
            parent.addChildNode(n)
            segments.append(n)
            parent = n
        }
        root.addChildNode(node)
    }

    func update(time: Float) {
        let age = time - start
        guard age >= 0 else { return }
        node.isHidden = false
        let rise: Float = 2.5, sink: Float = 2.5
        func smooth(_ t: Float) -> Float { let c = max(0, min(1, t)); return c * c * (3 - 2 * c) }
        let reach = age < rise ? smooth(age / rise) : age < rise + stay ? 1 : 1 - smooth((age - rise - stay) / sink)
        if age > rise + stay + sink { finished = true }
        node.simdPosition = base + SIMD3(0, reach * Self.length * 0.7, 0)
        // Curls more towards the tip, and feels about.
        for (k, n) in segments.enumerated() {
            let f = Float(k) / Float(segments.count)
            let sway = sin(time * 1.5 - Float(k) * 0.55 + phase) * (0.1 + f * 0.25)
            n.simdOrientation = simd_quatf(angle: curl * f * 0.32 * reach + sway, axis: SIMD3(0, 0, 1))
        }
    }
}

/// A click on the sand: the grains around it hop up in a ring that spreads out, then settle back where they were.
@MainActor
final class SandRipple {
    let node = SCNNode()
    private var grains: [(node: SCNNode, rest: Float, distance: Float)] = []
    private var age: Float = 0
    private static var radius: Int { Int((1 / TankDecor.sandSize).rounded()) }

    var finished: Bool { age > 2.4 }

    init(at p: SIMD3<Float>) {
        let cx = Int((p.x / TankDecor.sandSize).rounded()), cz = Int((p.z / TankDecor.sandSize).rounded())
        for dx in -Self.radius...Self.radius {
            for dz in -Self.radius...Self.radius {
                let dist = Float(dx * dx + dz * dz).squareRoot()
                guard dist <= Float(Self.radius) + 0.3 else { continue }
                let x = cx + dx, z = cz + dz
                let h = TankDecor.sandHeight(x, z)
                let m = VoxelModel()
                m.set(0, 0, 0, TankDecor.sandColor(x, h - 1, z, top: true))
                let g = SCNNode(geometry: m.geometry(size: TankDecor.sandSize, pivot: .zero))
                let rest = TankDecor.sandWorld(x, h - 1, z)
                g.simdPosition = rest
                g.categoryBitMask = TankController.Mask.effect
                node.addChildNode(g)
                grains.append((g, rest.y, dist))
            }
        }
    }

    func update(dt: Float) {
        age += dt
        for g in grains {
            let wave = age * 7 - g.distance * 1.5
            guard wave > 0 else { continue }
            let fade = exp(-age * 1.8) * (1 - g.distance / Float(Self.radius + 1))
            let lift = max(0, sin(min(wave, .pi))) * 0.4 * fade
            g.node.simdPosition.y = g.rest + lift
        }
    }
}

/// A splash on the water: a ring of surface blocks bobbing outwards and a few drops thrown up that fall back in.
@MainActor
final class Splash {
    let node = SCNNode()
    private var drops: [(node: SCNNode, velocity: SIMD3<Float>)] = []
    private var ring: [(node: SCNNode, distance: Float)] = []
    private let level: Float
    private var age: Float = 0
    var finished: Bool { age > 2 }

    private static func geometry(_ size: Float, _ color: UInt32) -> SCNGeometry {
        let m = VoxelModel()
        m.set(0, 0, 0, C(color, 60))
        let g = m.geometry(size: size, pivot: .zero, bevel: 0.15)
        g.materials = g.materials.map { let c = $0.copy() as! SCNMaterial; c.transparency = 0.8; return c }
        return g
    }

    init(at p: SIMD3<Float>) {
        level = p.y
        let tile = Self.geometry(TankDecor.surfaceSize, 0xD8ECE0), drop = Self.geometry(0.07, 0xE8F6F0)
        let s = TankDecor.surfaceSize
        let cx = (p.x / s).rounded(), cz = (p.z / s).rounded()
        for dx in -4...4 {
            for dz in -4...4 {
                let d = Float(dx * dx + dz * dz).squareRoot()
                guard d <= 4.3 else { continue }
                let n = SCNNode(geometry: tile)
                n.simdPosition = SIMD3((cx + Float(dx)) * s, level - s / 2, (cz + Float(dz)) * s)
                n.opacity = 0
                node.addChildNode(n)
                ring.append((n, d))
            }
        }
        for _ in 0..<12 {
            let a = Float.random(in: 0..<(2 * .pi)), out = Float.random(in: 0.3...0.9)
            let n = SCNNode(geometry: drop)
            n.simdPosition = p
            node.addChildNode(n)
            drops.append((n, SIMD3(cos(a) * out, Float.random(in: 1.4...2.4), sin(a) * out)))
        }
        node.enumerateHierarchy { n, _ in n.categoryBitMask = TankController.Mask.effect; n.castsShadow = false }
    }

    func update(dt: Float) {
        age += dt
        for (i, d) in drops.enumerated() {
            var v = d.velocity
            v.y -= 6 * dt
            drops[i].velocity = v
            d.node.simdPosition += v * dt
            d.node.isHidden = d.node.simdPosition.y < level - 0.05
        }
        let s = TankDecor.surfaceSize
        for r in ring {
            let wave = age * 6 - r.distance * 1.1
            let lift = wave > 0 && wave < .pi ? sin(wave) * 0.16 * exp(-age * 1.4) : 0
            r.node.simdPosition.y = level - s / 2 + lift
            r.node.opacity = CGFloat(lift > 0.005 ? 1 : 0)
        }
    }
}

final class Bubble {
    private static var geometries: [Biome: SCNGeometry] = [:]
    static var geometry: SCNGeometry {
        if let g = geometries[Biome.current] { return g }
        let m = VoxelModel()
        m.set(0, 0, 0, Biome.current.bubble)
        let g = m.geometry(size: 0.07, pivot: .zero, bevel: 0.3)
        geometries[Biome.current] = g
        return g
    }

    let node = SCNNode(geometry: Bubble.geometry)
    private let speed = Float.random(in: 0.7...1.3), seed = Float.random(in: 0..<10)

    init(at p: SIMD3<Float>) {
        node.simdPosition = p
        node.simdScale = SIMD3(repeating: Float.random(in: 0.6...1.4))
        node.categoryBitMask = TankController.Mask.effect
        node.castsShadow = false
    }

    func update(dt: Float, time: Float) {
        var p = node.simdPosition
        p.y += speed * dt
        p.x += sin(time * 5 + seed) * 0.2 * dt
        node.simdPosition = p
    }
}

final class Heart {
    static let geometry: SCNGeometry = {
        let rows = [".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."]
        let m = VoxelModel()
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() where ch == "X" { m.set(c, rows.count - 1 - r, 0, C(0xFF5C93, 220)) }
        }
        return m.geometry(size: 0.05, pivot: SIMD3(2, 2, 0), bevel: 0.22)
    }()

    let node = SCNNode(geometry: Heart.geometry)
    private(set) var age: Float = 0

    init(at p: SIMD3<Float>) {
        node.simdPosition = p
        node.categoryBitMask = TankController.Mask.effect
        node.castsShadow = false
    }

    func update(dt: Float, camera: SCNNode) {
        age += dt
        node.simdPosition.y += 0.6 * dt
        node.simdOrientation = camera.simdOrientation
        let s = 1.2 * (1 - max(0, age - 0.6) / 0.6)
        node.simdScale = SIMD3(repeating: max(0.001, s))
    }
}
