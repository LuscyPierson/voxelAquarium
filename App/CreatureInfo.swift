import SwiftUI

/// A creature's name, pinned over it on screen.
struct NameTag: Equatable {
    var text: String
    var point: CGPoint
    var id: UUID
}

/// What the close-up card says about a creature.
struct CreatureInfo: Equatable {
    struct Fact: Equatable, Hashable {
        var symbol: String
        var text: String
    }

    var name: String
    var world: String
    var blurb: String
    var accent: UInt32
    var rare: Bool
    var facts: [Fact]

    @MainActor
    init(_ c: Creature, biome: Biome) {
        let s = c.species
        name = s.name
        world = biome.title
        blurb = s.blurb
        accent = s.accent
        rare = Roster.isFun(s.key)
        let entry = Roster.entry(for: s.key)

        var facts: [Fact] = []
        let moves: (String, String) =
            s.hangs ? ("tree.fill", "Hangs from the branches") :
            s.floats ? ("water.waves", "Floats on the water") :
            s.flies || (biome == .rainforest && s.motion == .swim && !s.aquatic) ? ("bird.fill", "Flies") :
            s.motion == .walk ? (s.hops ? "hare.fill" : "pawprint.fill", s.hops ? "Hops along the ground" : "Walks along the floor") :
            s.motion == .drift ? ("wind", "Drifts with the current") :
            s.motion == .kraken ? ("tornado", "Lurks in the deep") : ("fish.fill", "Swims")
        facts.append(Fact(symbol: moves.0, text: moves.1))

        let length = s.body.bounds.map { Float($0.max.z - $0.min.z + 1) * s.voxelSize } ?? 0.5
        let size = length < 0.45 ? "Small" : length < 1.1 ? "Medium-sized" : length < 2.2 ? "Large" : "Huge"
        let pace = s.speed < 0.7 ? "slow" : s.speed < 1.3 ? "steady" : "quick"
        facts.append(Fact(symbol: "ruler", text: "\(size), and \(pace)"))

        if let g = entry?.group {
            facts.append(Fact(symbol: "person.3.fill", text: g.upperBound <= 1 ? "Usually on its own" :
                g.lowerBound == g.upperBound ? "Comes in groups of \(g.lowerBound)" : "Comes in groups of \(g.lowerBound)–\(g.upperBound)"))
        } else if s.schooling {
            facts.append(Fact(symbol: "person.3.fill", text: "Travels in a school"))
        }
        if entry?.shark == true {
            facts.append(Fact(symbol: "exclamationmark.triangle.fill", text: "A predator: everyone else gets out of its way"))
        }
        if s.puffs { facts.append(Fact(symbol: "circle.dotted", text: "Puffs up when you poke it")) }
        if rare { facts.append(Fact(symbol: "sparkles", text: "Rare look! About 1 visit in 20")) }
        if s.key.hasPrefix("workshop-") { facts.append(Fact(symbol: "hammer.fill", text: "Made in the Workshop")) }
        if s.isCustom { facts.append(Fact(symbol: "paintbrush.pointed.fill", text: "Designed in the Fish Editor")) }
        self.facts = facts
    }
}

struct NameTagView: View {
    let tag: NameTag

    var body: some View {
        Text(tag.text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().stroke(Theme.line))
            .fixedSize()
    }
}

/// The card beside a close-up: what the creature is and a few things about it.
struct CreatureCard: View {
    let info: CreatureInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Eyebrow(text: info.world)
                if info.rare {
                    Text("RARE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.5)
                        .foregroundStyle(Color(red: 0.2, green: 0.12, blue: 0))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(red: 1, green: 0.82, blue: 0.25), in: Capsule())
                }
            }
            HStack(spacing: 10) {
                Circle().fill(Color(nsColor: NSColor(rgb: info.accent))).frame(width: 14, height: 14)
                Text(info.name).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            }
            Text(info.blurb).font(.system(size: 14)).foregroundStyle(Theme.ink.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(info.facts, id: \.self) { fact in
                    Label {
                        Text(fact.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                    } icon: {
                        Image(systemName: fact.symbol).foregroundStyle(Theme.cyan).frame(width: 20)
                    }
                }
            }
            Text("Click anywhere to go back")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        .allowsHitTesting(false)
    }
}
