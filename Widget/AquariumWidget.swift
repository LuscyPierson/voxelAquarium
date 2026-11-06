import AppIntents
import SwiftUI
import WidgetKit

// The Voxel Aquarium desktop widget: a window onto the same open ocean as the app. The app writes a
// creature catalog, voxel sprites and an empty-ocean backdrop into the shared App Group container;
// the widget works out who is swimming by from the time alone, so it needs no app running.
// Tapping it nudges the fish a little.

struct OceanData {
    var species: [SpeciesInfo] = []
    var sprites: [String: NSImage] = [:]
    var backdrop: NSImage?
    var noSharks = false
    var nudges = 0

    static func load() -> OceanData {
        var ocean = OceanData()
        ocean.noSharks = Shared.defaults.bool(forKey: Shared.noSharks)
        ocean.nudges = Shared.defaults.integer(forKey: Shared.nudges)
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return ocean }
        if let data = try? Data(contentsOf: dir.appending(path: "catalog.json")),
           let catalog = try? JSONDecoder().decode(Catalog.self, from: data) {
            ocean.species = catalog.species
            for s in catalog.species { ocean.sprites[s.key] = NSImage(contentsOf: dir.appending(path: "fish/\(s.key).png")) }
        }
        ocean.backdrop = NSImage(contentsOf: dir.appending(path: "backdrop.png"))
        return ocean
    }
}

// MARK: - Who's swimming by

struct Swimmer: Identifiable {
    let id: Int
    let sprite: NSImage?
    /// Centre, as fractions of the widget (0...1, top-left origin); can be just off screen.
    let x: Double, y: Double
    /// Sprite height as a fraction of the widget height.
    let height: Double
    let facingRight: Bool
    /// A slight swing back and forth, a different way each step, so it looks like it's swimming.
    let wiggle: Double
}

/// The ocean's view is 5.4 units tall, centred 3.5 up, like the app's camera.
private let viewTop = 6.2, viewHeight = 5.4
private let arrivalEvery = 40.0

/// Visitors arrive on a fixed schedule and take two to five minutes to cross, so any moment (and every reload)
/// agrees on who is where. Mostly fish; sharks are rare, fun looks rarer.
func swimmers(in ocean: OceanData, at date: Date) -> [Swimmer] {
    let pool = ocean.species.filter { ($0.weight ?? 0) > 0 && !(ocean.noSharks && $0.shark == true) }
    let total = pool.reduce(0) { $0 + ($1.weight ?? 0) }
    guard total > 0 else { return [] }
    let t = date.timeIntervalSince1970
    let latest = Int(t / arrivalEvery)
    var out: [Swimmer] = []
    for k in (latest - 14)...latest {
        let arrive = Double(k) * arrivalEvery
        var pick = unitHash("pick\(k)") * total
        guard let s = pool.first(where: { pick -= $0.weight ?? 0; return pick < 0 }) ?? pool.last else { continue }
        let speed = max(0.3, s.speed)
        let lap = min(480, max(110, (150 + unitHash("lap\(k)") * 140) / speed))
        let progress = (t - arrive) / lap
        guard progress >= 0, progress <= 1 else { continue }
        let right = unitHash("dir\(k)") < 0.5
        let lo = min(s.groupMin ?? 1, 4), hi = max(lo, min(s.groupMax ?? 1, 4))
        let count = lo + Int(unitHash("n\(k)") * Double(hi - lo + 1)) % (hi - lo + 1)
        let depth = s.depthMin + (s.depthMax - s.depthMin) * unitHash("d\(k)")
        let worldY = 1.0 + 4.3 * depth
        for m in 0..<count {
            let id = k * 16 + m
            let jitterX = m == 0 ? 0 : (unitHash("x\(id)") - 0.5) * 0.12
            let jitterY = m == 0 ? 0 : (unitHash("y\(id)") - 0.5) * 0.1
            // A tap nudges everyone a little, differently each time.
            let nudgeX = ocean.nudges == 0 ? 0 : (unitHash("nx\(id)|\(ocean.nudges)") - 0.5) * 0.06
            let nudgeY = ocean.nudges == 0 ? 0 : (unitHash("ny\(id)|\(ocean.nudges)") - 0.5) * 0.07
            let travel = -0.25 + 1.5 * progress
            let bob = sin(t / 9 + Double(id)) * 0.02
            out.append(Swimmer(
                id: id,
                sprite: ocean.sprites[s.key],
                x: (right ? travel : 1 - travel) + jitterX + nudgeX,
                y: min(0.93, max(0.07, (viewTop - worldY) / viewHeight + jitterY + nudgeY + bob)),
                height: min(0.7, 2 * (s.halfHeight ?? 0.6) / viewHeight),
                facingRight: s.drift == true ? true : right,
                wiggle: sin(t * 1.3 + Double(id) * 2.1) * 5
            ))
        }
    }
    return out
}

func unitHash(_ s: String) -> Double {
    var h: UInt32 = 2166136261
    for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
    h ^= h >> 13
    h = h &* 0x5BD1E995
    h ^= h >> 15
    return Double(h) / Double(UInt32.max)
}

// MARK: - Tapping

struct NudgeFishIntent: AppIntent {
    static var title: LocalizedStringResource = "Nudge the fish"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        let d = Shared.defaults
        d.set(d.integer(forKey: Shared.nudges) + 1, forKey: Shared.nudges)
        return .result()
    }
}

// MARK: - Timeline

struct OceanEntry: TimelineEntry {
    let date: Date
    let ocean: OceanData
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> OceanEntry { OceanEntry(date: .now, ocean: OceanData()) }

    func getSnapshot(in context: Context, completion: @escaping (OceanEntry) -> Void) {
        completion(OceanEntry(date: .now, ocean: .load()))
    }

    /// A step every few seconds for eight minutes; the view glides the fish between steps. Then fetch again.
    /// Kept short: macOS refuses a timeline whose archive grows past about 10 MB (400 steps came to 12 MB).
    func getTimeline(in context: Context, completion: @escaping (Timeline<OceanEntry>) -> Void) {
        let ocean = OceanData.load()
        let start = Date.now
        let entries = (0..<Int(Self.span / Self.step)).map { OceanEntry(date: start.addingTimeInterval(Double($0) * Self.step), ocean: ocean) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static let step = 4.0, span = 8 * 60.0
}

// MARK: - View

struct TankView: View {
    let entry: OceanEntry
    /// Lets an offscreen preview pick the size (the environment value can't be set).
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        Button(intent: NudgeFishIntent()) {
            GeometryReader { geo in
                ZStack {
                    ForEach(swimmers(in: entry.ocean, at: entry.date)) { s in
                        if let sprite = s.sprite {
                            let h = s.height * geo.size.height
                            Image(nsImage: sprite)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: h * 4 / 3, height: h)
                                .scaleEffect(x: s.facingRight ? 1 : -1, y: 1)
                                .rotationEffect(.degrees(s.wiggle))
                                .position(x: s.x * geo.size.width, y: s.y * geo.size.height)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                // Glide from each step to the next (widgets allow up to two seconds of animation).
                .animation(.linear(duration: 2), value: entry.date)
                .animation(.spring(duration: 1.2), value: entry.ocean.nudges)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            if let backdrop = entry.ocean.backdrop {
                Image(nsImage: backdrop).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.27, green: 0.7, blue: 0.83), Color(red: 0.03, green: 0.15, blue: 0.25)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

// MARK: - Widget

struct AquariumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VoxelAquarium", provider: Provider()) { entry in
            TankView(entry: entry)
        }
        .configurationDisplayName("Voxel Ocean")
        .description("A little window onto the ocean. Tap it to give the fish a nudge.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

#if !PREVIEW_HARNESS
@main
struct AquariumWidgets: WidgetBundle {
    var body: some Widget { AquariumWidget() }
}
#endif
