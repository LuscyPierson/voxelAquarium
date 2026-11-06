import simd

// More ocean visitors: open-water fish, reef beauties, rays, eels and a few odd ones from the deep.

extension Builtins {
    // MARK: Open water

    static func tuna() -> Species {
        let d = Species(key: "tuna", name: "Tuna", blurb: "Built for speed, and it knows it.", accent: 0x1F3C6E)
        d.voxelSize = 0.065; d.speed = 2.0; d.turn = 1.8; d.wag = 7; d.wagAngle = 14; d.depth = (0.3, 0.85)
        d.cruiser = true; d.crowd = 1.4
        let back = C(0x1F3C6E), side = C(0x9FB3C8), belly = C(0xE8EEF2), yellow = C(0xF2C230), stripe = C(0x4C78B8)
        loft(d, 20, 3.2, 2.2, a: 0.06, b: 0.9, p: 0.55) { t, _, y, h, _ in
            let fy = Float(y)
            if fy > h * 0.35 { return back }
            if abs(fy - h * 0.15) < 0.6 && t > 0.3 && t < 0.85 { return stripe }
            return fy < -h * 0.3 ? belly : side
        }
        fin(d, 0.55, 0.7, up: true, height: { 1 + 2.5 * (1 - $0) }) { _, _, _ in back }
        fin(d, 0.38, 0.48, up: true, height: { _ in 2 }) { _, _, _ in yellow }
        fin(d, 0.38, 0.48, up: false, height: { _ in 2 }) { _, _, _ in yellow }
        // Little yellow finlets towards the tail.
        for l in [1, 3, 5] {
            if let t = d.body.top(x: 0, z: l) { d.body.set(0, t + 1, l, yellow) }
            if let b = d.body.bottom(x: 0, z: l) { d.body.set(0, b - 1, l, yellow) }
        }
        pectoral(d, 14, 0, back)
        tailFan(d, 5, span: { (-1 - $0 * 5, 1 + $0 * 5) }) { u, y in u > 0.3 && abs(Float(y)) < (u - 0.3) * 8 ? nil : back }
        eye(d, 17, 1, big: true)
        return d
    }

    static func mackerel() -> Species {
        let d = Species(key: "mackerel", name: "Mackerel", blurb: "Tiger-striped and always in a hurry.", accent: 0x2E7A6E)
        d.voxelSize = 0.05; d.speed = 1.7; d.turn = 2.6; d.wag = 11; d.depth = (0.3, 0.85)
        d.schooling = true; d.cruiser = true; d.crowd = 0.4
        let back = C(0x2E7A6E), bar = C(0x14302C), silver = C(0xD6E0E4), belly = C(0xF4F7F8)
        loft(d, 15, 1.9, 1.2) { t, _, y, h, _ in
            let fy = Float(y)
            if fy >= 0 { return sin(t * 42 + fy * 1.3) > 0.45 ? bar : back }
            return fy < -h * 0.5 ? belly : silver
        }
        fin(d, 0.55, 0.7, up: true, height: { _ in 1 }) { _, _, _ in back }
        fin(d, 0.3, 0.4, up: true, height: { _ in 1 }) { _, _, _ in back }
        tailFan(d, 3, span: { (-1 - $0 * 2.5, 1 + $0 * 2.5) }) { u, y in u > 0.5 && y == 0 ? nil : back }
        eye(d, 13, 0)
        return d
    }

    static func salmon() -> Species {
        let d = Species(key: "salmon", name: "Salmon", blurb: "Silver and pink, on a long journey somewhere.", accent: 0xF0A0A8)
        d.voxelSize = 0.06; d.speed = 1.4; d.turn = 2; d.wag = 7; d.depth = (0.25, 0.8)
        let back = C(0x4E6E7E), spot = C(0x1E2A30), silver = C(0xD8DEE2), pink = C(0xF0A0A8), belly = C(0xF6F4F2)
        loft(d, 18, 2.8, 1.6, a: 0.06, b: 0.92, p: 0.5) { t, x, y, h, _ in
            let fy = Float(y)
            if fy > h * 0.3 { return vhash(x, y, Int(t * 100), 23) < 0.18 ? spot : back }
            if abs(fy) <= 0.6 { return pink }
            return fy < -h * 0.4 ? belly : silver
        }
        fin(d, 0.45, 0.6, up: true, height: { 1 + 1.5 * sin($0 * .pi) }) { _, _, _ in back }
        fin(d, 0.18, 0.2, up: true, height: { _ in 1 }) { _, _, _ in back }
        fin(d, 0.2, 0.32, up: false, height: { _ in 1 }) { _, _, _ in silver }
        pectoral(d, 13, -1, silver)
        tailFan(d, 4, span: { (-1 - $0 * 2.6, 1 + $0 * 2.6) }) { u, y in u > 0.7 && y == 0 ? nil : back }
        eye(d, 16, 1)
        return d
    }

    static func barracuda() -> Species {
        let d = Species(key: "barracuda", name: "Barracuda", blurb: "All teeth and attitude, but only window-shopping.", accent: 0x8C99A6)
        d.voxelSize = 0.07; d.speed = 1.6; d.turn = 1.6; d.wag = 5; d.wagAngle = 14; d.depth = (0.3, 0.8)
        d.cruiser = true; d.crowd = 1.6
        let back = C(0x5E6E7E), silver = C(0xC4CDD6), chevron = C(0x3D4650), belly = C(0xEEF1F4), spot = C(0x1A1E24)
        loft(d, 26, 1.9, 1.3, a: 0.04, b: 0.92, p: 0.45) { t, x, y, h, _ in
            let fy = Float(y)
            if fy > h * 0.4 { return back }
            if fy >= 0 && sin(t * 52 + fy) > 0.72 && t > 0.2 && t < 0.8 { return chevron }
            if fy < 0 && t < 0.3 && vhash(x, y, Int(t * 100), 29) < 0.2 { return spot }
            return fy < -h * 0.4 ? belly : silver
        }
        fin(d, 0.55, 0.62, up: true, height: { _ in 2 }) { _, _, _ in back }
        fin(d, 0.22, 0.28, up: true, height: { _ in 1 }) { _, _, _ in back }
        fin(d, 0.22, 0.28, up: false, height: { _ in 1 }) { _, _, _ in back }
        pectoral(d, 19, -1, silver)
        tailFan(d, 4, span: { (-1 - $0 * 3, 1 + $0 * 3) }) { u, y in u > 0.4 && abs(Float(y)) < (u - 0.4) * 5 ? nil : back }
        eye(d, 22, 1)
        // Pointed underbite with a few teeth.
        d.body.set(0, -1, 26, silver)
        d.body.set(0, -1, 27, silver)
        for s in [-1, 1] { d.body.set(s, -1, 25, C(0xFFFFFF)) }
        return d
    }

    static func sailfish() -> Species {
        let d = Species(key: "sailfish", name: "Sailfish", blurb: "Raises its sail and zooms off.", accent: 0x253E8C)
        d.voxelSize = 0.07; d.speed = 2.0; d.turn = 1.6; d.wag = 6; d.wagAngle = 14; d.depth = (0.35, 0.85)
        d.cruiser = true; d.crowd = 2.2
        let back = C(0x1E3F7A), bar = C(0x6FA8E0), belly = C(0xD8E0E8), sail = C(0x253E8C), spot = C(0x5A82D6)
        loft(d, 24, 2.6, 1.6, a: 0.04, b: 0.92, p: 0.55) { t, _, y, h, _ in
            let fy = Float(y)
            if fy < -h * 0.2 { return belly }
            return sin(t * 70) > 0.8 && t > 0.2 && t < 0.8 ? bar : back
        }
        fin(d, 0.3, 0.85, up: true, height: { 3 + 5 * sin($0 * .pi * 0.9 + 0.2) }) { t, k, _ in
            vhash(Int(t * 100), k, 0, 31) < 0.22 ? spot : sail
        }
        pectoral(d, 17, -1, sail)
        tailFan(d, 6, span: { (-1 - $0 * 5, 1 + $0 * 5) }) { u, y in u > 0.3 && abs(Float(y)) < (u - 0.3) * 9 ? nil : back }
        eye(d, 21, 1, big: true)
        let bill = C(0x3A4458)
        for z in 24...31 { d.body.set(0, 0, z, bill) }
        return d
    }

    // MARK: Reef beauties

    static func moorishIdol() -> Species {
        let d = Species(key: "moorishidol", name: "Moorish Idol", blurb: "Black, white and yellow, with a streamer on top.", accent: 0xF2D23A)
        d.speed = 0.8; d.turn = 1.8; d.wag = 5; d.wagAngle = 16; d.depth = (0.25, 0.85)
        let white = C(0xF6F4EA), black = C(0x16161C), yellow = C(0xF2D23A), orange = C(0xF29A3A)
        loft(d, 10, 3.6, 0.9, a: 0.15, b: 0.9, p: 0.65) { t, _, y, h, _ in
            if (t > 0.62 && t < 0.78) || (t > 0.18 && t < 0.36) { return black }
            if t < 0.18 { return Float(y) > -h * 0.2 ? yellow : white }
            return t > 0.36 && t < 0.62 && Float(y) > h * 0.5 ? yellow : white
        }
        fin(d, 0.2, 0.65, up: true, height: { 1 + 2 * (1 - $0) }) { t, _, _ in t > 0.36 && t < 0.62 ? white : black }
        fin(d, 0.2, 0.6, up: false, height: { _ in 2 }) { _, _, _ in black }
        // The long white streamer sweeping back from the top.
        if let top = d.body.top(x: 0, z: 6) {
            for k in 1...9 { d.body.set(0, top + 1 + k, 6 - k / 2, white) }
        }
        // A little orange-tipped snout.
        d.body.set(0, -1, 10, white)
        d.body.set(0, -1, 11, orange)
        tailFan(d, 3, span: { (-1 - $0 * 2, 1 + $0 * 2) }) { _, _ in black }
        eye(d, 7, 0)
        return d
    }

    static func butterflyfish() -> Species {
        let d = Species(key: "butterflyfish", name: "Butterflyfish", blurb: "Has a fake eye near its tail, just in case.", accent: 0xFFD23A)
        d.speed = 0.9; d.turn = 2.2; d.wag = 7; d.depth = (0.2, 0.8)
        let yellow = C(0xFFD23A), white = C(0xFAF6EC), black = C(0x16161C), blue = C(0x3A7BD8)
        loft(d, 10, 3.4, 1, a: 0.12, b: 0.92, p: 0.65) { t, _, y, h, _ in
            let fy = Float(y)
            if t > 0.74 && t < 0.84 && fy > -h * 0.6 { return black }
            if t >= 0.84 { return white }
            if t > 0.18 && t < 0.32 && fy > h * 0.25 && fy < h * 0.75 { return black }
            return yellow
        }
        fin(d, 0.15, 0.7, up: true, height: { _ in 1.5 }) { _, k, n in k == n ? blue : yellow }
        fin(d, 0.15, 0.6, up: false, height: { _ in 1.4 }) { _, k, n in k == n ? blue : yellow }
        tailFan(d, 2, span: { (-1 - $0 * 2, 1 + $0 * 2) }) { _, _ in yellow }
        d.body.set(0, 0, 10, yellow)
        eye(d, 8, 1)
        return d
    }

    static func parrotfish() -> Species {
        let d = Species(key: "parrotfish", name: "Parrotfish", blurb: "Paints itself every colour and nibbles coral all day.", accent: 0x2FC9B5)
        d.voxelSize = 0.065; d.speed = 0.9; d.turn = 1.8; d.wag = 6; d.depth = (0.15, 0.7)
        let teal = C(0x2FC9B5), pink = C(0xF27BA8), green = C(0x5ED67A), beak = C(0xD6F5EE)
        loft(d, 16, 3.2, 1.8, a: 0.08, b: 0.9, p: 0.5) { t, x, y, _, _ in
            let l = Int(t * 16)
            if (l + y + 30) % 3 == 0 && abs(x) >= 1 { return pink }
            return vhash(x, y, l, 37) < 0.15 ? green : teal
        }
        fin(d, 0.25, 0.8, up: true, height: { _ in 1.3 }) { _, k, n in k == n ? pink : teal }
        fin(d, 0.25, 0.55, up: false, height: { _ in 1.2 }) { _, k, n in k == n ? pink : teal }
        pectoral(d, 11, -1, pink)
        tailFan(d, 4, span: { (-1 - $0 * 3, 1 + $0 * 3) }) { u, y in u > 0.6 && abs(Float(y)) < (u - 0.6) * 6 ? nil : u > 0.7 ? pink : teal }
        eye(d, 13, 1)
        // The beak.
        fill(d.body, 0...0, -1...0, 16...16, beak)
        return d
    }

    static func mandarinfish() -> Species {
        let d = Species(key: "mandarinfish", name: "Mandarinfish", blurb: "Tiny, shy, and dressed for a party.", accent: 0x2E6BE6)
        d.voxelSize = 0.05; d.speed = 0.6; d.turn = 2.4; d.wag = 9; d.depth = (0.05, 0.45)
        let blue = C(0x2E6BE6), orange = C(0xF2832A), green = C(0x3FCF8E), edge = C(0x1A3A9A)
        loft(d, 12, 2.4, 1.7, a: 0.08, b: 0.95, p: 0.35) { t, x, y, _, _ in
            let v = vnoise(t * 10, Float(y) * 0.8, Float(x) * 0.8, 41)
            if v > 0.62 { return orange }
            return v < 0.22 ? green : blue
        }
        fin(d, 0.2, 0.7, up: true, height: { 1 + 1.5 * sin($0 * .pi) }) { _, k, n in k == n ? edge : orange }
        fin(d, 0.2, 0.6, up: false, height: { _ in 1.5 }) { _, k, n in k == n ? edge : orange }
        pectoral(d, 9, -1, orange)
        tailFan(d, 3, span: { (-1 - $0 * 2.2, 1 + $0 * 2.2) }) { u, _ in u > 0.7 ? edge : orange }
        eye(d, 10, 1, big: true)
        return d
    }

    static func lionfish() -> Species {
        let d = Species(key: "lionfish", name: "Lionfish", blurb: "A flowing mane of stripy spines.", accent: 0xC8352C)
        d.voxelSize = 0.065; d.speed = 0.5; d.turn = 1.4; d.wag = 4; d.wagAngle = 14; d.depth = (0.15, 0.7); d.crowd = 1.2
        let red = C(0xC8352C), cream = C(0xF4E3D0), dark = C(0x6E1E18)
        func band(_ i: Int) -> VoxelColor { i % 2 == 0 ? red : cream }
        loft(d, 12, 2.8, 1.6, a: 0.08, b: 0.92, p: 0.5) { t, _, _, _, _ in band(Int(t * 14)) }
        // Tall separate spines along the back.
        for l in stride(from: 2, through: 10, by: 2) {
            guard let top = d.body.top(x: 0, z: l) else { continue }
            let n = 3 + (l % 4 == 2 ? 3 : 1)
            for k in 1...n { d.body.set(0, top + k, l - k / 3, band(k)) }
        }
        // Big feathery fans either side, sweeping down and back.
        for s in [-1, 1] {
            let x = s * (abs(d.body.side(y: -1, z: 9, sign: s)) + 1)
            for j in 0..<6 { for k in 0..<4 { d.body.set(x, -1 - k, 9 - j - k / 2, (j + k) % 2 == 0 ? red : cream) } }
        }
        tailFan(d, 3, span: { (-1 - $0 * 2, 1 + $0 * 2) }) { u, y in (Int(u * 3) + y + 9) % 2 == 0 ? red : cream }
        eye(d, 10, 1)
        d.body.set(0, 0, 12, dark)
        return d
    }

    // MARK: Bottom dwellers

    static func stingray() -> Species {
        let d = Species(key: "stingray", name: "Stingray", blurb: "Glides over the sand like a magic carpet.", accent: 0x9A8466)
        d.voxelSize = 0.07; d.speed = 0.75; d.turn = 1.2; d.wag = 2.5; d.wagAngle = 10; d.depth = (0, 0.2)
        d.cruiser = true; d.crowd = 1.4; d.bank = 0.75
        let top = C(0x9A8466), spot = C(0x6E5E48), rim = C(0xB8A282), under = C(0xF2ECE2), dark = C(0x2A241C)
        d.length = 14
        for z in 0..<14 {
            let t = (Float(z) + 0.5) / 14
            let w = Int((7.5 * pow(sin(.pi * min(1, t * 1.15)), 0.8)).rounded())
            for x in -w...w {
                let edge = abs(x) == w
                d.body.set(x, 0, z, edge ? rim : vhash(x, 0, z, 47) < 0.2 ? spot : top)
                if abs(x) < w - 1 { d.body.set(x, -1, z, under) }
                if abs(x) <= 2 && z > 2 && z < 11 { d.body.set(x, 1, z, top) }
            }
        }
        for s in [-1, 1] { d.body.set(s * 2, 2, 10, dark) }
        // A long whip of a tail, with a barb.
        for i in 0..<16 { d.tail.set(0, 0, -i, i == 5 ? C(0xD8D2C4) : dark) }
        return d
    }

    static func morayEel() -> Species {
        let d = Species(key: "moray", name: "Moray Eel", blurb: "Looks grumpy. Is actually just breathing.", accent: 0x4E7A3A)
        d.voxelSize = 0.06; d.speed = 0.6; d.turn = 1.4; d.wag = 4; d.wagAngle = 30; d.depth = (0, 0.25); d.crowd = 1.5
        let green = C(0x4E7A3A), spot = C(0xC8C060), finColor = C(0x3E6A2E), mouth = C(0x3A1E1E)
        loft(d, 34, 1.8, 1.4, a: 0.03, b: 0.95, p: 0.3, wp: 0.3) { t, x, y, _, _ in
            vhash(x, y, Int(t * 100), 51) < 0.25 ? spot : green
        }
        fin(d, 0.1, 0.85, up: true, height: { _ in 1 }) { _, _, _ in finColor }
        fin(d, 0.1, 0.45, up: false, height: { _ in 1 }) { _, _, _ in finColor }
        eye(d, 31, 1)
        fill(d.body, -1...1, -1 ... -1, 32...33, mouth)
        for s in [-1, 1] { d.body.set(s, 0, 33, C(0xFFFFFF)) }
        tailFan(d, 5, span: { _ in (-1, 1) }) { u, y in u > 0.6 && y != 0 ? nil : finColor }
        return d
    }

    static func seahorse() -> Species {
        let d = Species(key: "seahorse", name: "Seahorse", blurb: "Bobs along upright, very politely.", accent: 0xF2A93B)
        d.voxelSize = 0.055; d.speed = 0.22; d.depth = (0.2, 0.8); d.motion = .drift; d.crowd = 0.6
        let gold = C(0xF2A93B), ring = C(0xC97E22), light = C(0xFFD98A), finColor = C(0xFFE6B0, 60)
        // Drawn side-on, in the x-y plane (snout pointing +x), two blocks thick.
        for z in 0...1 {
            for y in 1...8 {
                let cx = Int((sin(Float(y) * 0.35) * 1.2).rounded())
                let belly = y >= 3 && y <= 6 ? 1 : 0
                for x in (cx - 1)...(cx + 1 + belly) { d.body.set(x, y, z, y % 2 == 0 ? ring : x > cx ? light : gold) }
            }
            for (x, y) in [(-1, 0), (0, 0), (-1, -1), (0, -2), (1, -3), (2, -3), (3, -2), (3, -1), (2, -1)] {
                d.body.set(x, y, z, (x + y) % 2 == 0 ? ring : gold)
            }
            fill(d.body, -1...2, 9...11, z...z, gold)
            fill(d.body, 0...1, 12...12, z...z, ring)
            for x in 3...5 { d.body.set(x, 10, z, gold) }
            d.body.set(5, 10, z, ring)
        }
        for y in 4...6 { d.body.set(-2, y, 0, finColor); d.body.set(-2, y, 1, finColor) }
        for z in [-1, 2] { d.body.set(1, 10, z, C(0x0A0A0E)); d.body.set(1, 11, z, C(0xFFFFFF)) }
        return d
    }

    static func octopus() -> Species {
        let d = Species(key: "octopus", name: "Octopus", blurb: "Eight arms, three hearts, zero worries.", accent: 0xE0603A)
        d.voxelSize = 0.06; d.speed = 0.3; d.depth = (0, 0.35); d.motion = .drift; d.crowd = 1.4; d.splay = 0.7
        let skin = C(0xE0603A), spot = C(0xB8442A), sucker = C(0xF6C9A8), white = C(0xFFFFFF), black = C(0x0A0A0E)
        ellipsoid(d.body, SIMD3(0, 6, 0), SIMD3(3.5, 4, 3.2)) { x, y, z in vhash(x, y, z, 53) < 0.2 ? spot : skin }
        ellipsoid(d.body, SIMD3(0, 2, 0), SIMD3(3.2, 1.4, 3.2)) { _, _, _ in skin }
        for s in [-1, 1] {
            if let z = front(d.body, s * 2, 4) {
                d.body.set(s * 2, 4, z + 1, white)
                d.body.set(s * 2, 3, z + 1, black)
            }
        }
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + 0.3
            d.tentacles.append(tentacle(at: SIMD3(cos(a) * 2.6, 1.5, sin(a) * 2.6), count: 6, len: 2, width: { $0 < 3 ? 2 : 1 },
                                        curl: 1.3) { _, y, side in side == 0 && y == 1 ? sucker : skin })
        }
        return d
    }

    /// A deep-sea anglerfish, up from the dark with its little light.
    static func anglerfish() -> Species {
        let d = Species(key: "anglerfish", name: "Anglerfish", blurb: "Up from the deep. Brought its own night-light.", accent: 0xFFF2A0)
        d.voxelSize = 0.07; d.speed = 0.5; d.turn = 1.3; d.wag = 5; d.wagAngle = 18; d.depth = (0, 0.35); d.crowd = 1.5
        let skin = C(0x2B2630), mottle = C(0x3D3542), mouth = C(0x5A1A24), tooth = C(0xF4F2E8)
        d.length = 13
        ellipsoid(d.body, SIMD3(0, 0, 6), SIMD3(3.6, 4.4, 6)) { x, y, z in
            // A huge open mouth across the front.
            if z >= 9 && y >= -3 && y <= 0 && abs(x) <= 2 { return z >= 11 ? nil : mouth }
            return vnoise(Float(x) * 0.6, Float(y) * 0.6, Float(z) * 0.6, 55) > 0.6 ? mottle : skin
        }
        // Jagged teeth along the jaws.
        for z in 9...12 {
            for x in -2...2 where (x + z) % 2 == 0 {
                d.body.set(x, 0, z, tooth)
                d.body.set(x, -3, z, tooth)
            }
        }
        // Underbite.
        fill(d.body, -2...2, -4 ... -4, 9...12, skin)
        // Big glassy eyes.
        for s in [-1, 1] {
            d.body.set(s * 3, 2, 9, C(0xE8E8E0))
            d.body.set(s * 3, 2, 10, C(0x0A0A0E))
            d.body.set(s * 3, 3, 10, C(0xFFFFFF))
        }
        // The lure: a stalk arching forward from the forehead, with a glowing bulb.
        let stalk = C(0x4A4252)
        for (y, z) in [(4, 8), (5, 9), (6, 10), (7, 11), (7, 12), (6, 13)] { d.body.set(0, y, z, stalk) }
        let glow = C(0xFFF6A0, 255)
        d.body.set(0, 5, 13, glow)
        d.body.set(0, 4, 13, glow)
        d.body.set(1, 5, 13, glow)
        d.body.set(-1, 5, 13, glow)
        d.body.set(0, 5, 14, glow)
        fin(d, 0.15, 0.4, up: true, height: { _ in 1 }) { _, _, _ in mottle }
        pectoral(d, 6, -2, mottle)
        tailFan(d, 3, span: { (-1 - $0 * 2, 1 + $0 * 2) }) { _, _ in mottle }
        return d
    }
}
