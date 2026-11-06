import AppKit
import SceneKit
import WidgetKit

/// The app's state: the live ocean, its settings, developer spawning, and the files the widget reads.
/// Nobody picks what swims by; the ocean decides.
@MainActor
final class AquariumModel: ObservableObject {
    let library: Library
    @Published private(set) var tank: TankController
    let keepAwake = KeepAwake()

    /// Which world is on screen: the ocean, the swamp or the rainforest. Changing it builds the new one.
    @Published var biome: Biome {
        didSet {
            guard biome != oldValue else { return }
            Shared.defaults.set(biome.rawValue, forKey: Shared.biome)
            tank = makeTank(biome)
            show(biome.title)
            exportForWidget()
        }
    }

    /// No sharks, here or in the widget.
    @Published var noSharks: Bool {
        didSet {
            Shared.defaults.set(noSharks, forKey: Shared.noSharks)
            tank.noSharks = noSharks
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    @Published private(set) var toast: String?
    /// The name floating over a creature you just clicked.
    @Published private(set) var nameTag: NameTag?
    /// The card shown while the camera is in close on a creature.
    @Published private(set) var info: CreatureInfo?
    private weak var tagged: Creature?
    private var tagUntil: Float = 0, lastClick: Float = -10
    /// A still of the 3D view, swapped in while capturing screenshots.
    @Published var frozen: NSImage?

    /// Set by the views: opens the Fish Editor, optionally on a design.
    var openEditor: ((FishDesign?) -> Void)?

    private var toastTask: Task<Void, Never>?

    init(library: Library) {
        self.library = library
        Workshop.load()
        let biome = Shared.defaults.string(forKey: Shared.biome).flatMap(Biome.init(rawValue:)) ?? .ocean
        self.biome = biome
        tank = TankController(biome: biome)
        noSharks = Shared.defaults.bool(forKey: Shared.noSharks)
        tank.noSharks = noSharks
        tank.onChest = { [weak self] in self?.show("Treasure!") }
        // Give the window a moment to appear before rendering widget images.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            exportForWidget()
        }
        watchWorkshop()
        // While the app is open the widget may refresh as often as it likes, so hand it a new stretch of
        // swimming before the last one runs out.
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7 * 60))
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// Picks up saves from the Unity Workshop: when its folder changes, rebuild the world with the new things in it.
    private func watchWorkshop() {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                guard Workshop.currentSignature() != Workshop.signature else { continue }
                Workshop.load()
                Roster.forgetWorkshop()
                tank = makeTank(biome)
                show("Workshop updated")
            }
        }
    }

    private func makeTank(_ biome: Biome) -> TankController {
        let t = TankController(biome: biome)
        t.noSharks = noSharks
        t.onChest = { [weak self] in self?.show("Treasure!") }
        return t
    }

    func frame(dt: Float) {
        tank.step(dt: dt)
        if let c = tagged, tank.time < tagUntil, !tank.inCloseUp, let p = tank.screenPoint(of: c, above: 0.45) {
            let tag = NameTag(text: c.species.name, point: p, id: c.id)
            if nameTag != tag { nameTag = tag }
        } else if nameTag != nil {
            nameTag = nil
            tagged = nil
        }
        if info != nil && !tank.inCloseUp { info = nil }
    }

    // MARK: - Clicks

    /// One click names the creature you hit; a double click moves in close with its card; any click in close-up goes back.
    func click(at point: CGPoint, count: Int) {
        if count == 2 {
            guard !tank.inCloseUp else { return }
            let recent = tank.time - lastClick < 0.8 ? tagged : nil
            guard let c = tank.creature(at: point) ?? recent else { return }
            tank.closeUp(on: c)
            info = CreatureInfo(c, biome: biome)
            tagged = nil
            nameTag = nil
            return
        }
        guard count == 1 else { return }
        if tank.inCloseUp {
            tank.endCloseUp()
            info = nil
            return
        }
        lastClick = tank.time
        if let c = tank.tap(at: point) {
            tagged = c
            tagUntil = tank.time + 2.5
        }
    }

    // MARK: - Developer spawning

    /// Everything that can be summoned by name: this world's creatures (fun looks included) and editor designs.
    var spawnable: [Species] { Roster.all + library.customSpecies }

    /// Finds a creature by (part of) its name or key. `fun` picks its rare look when it has one.
    func find(_ name: String, fun: Bool) -> Species? {
        let q = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let matches = spawnable.filter { $0.name.lowercased().contains(q) || $0.key.contains(q) }
        let exact = matches.first { $0.name.lowercased() == q || $0.key == q }
        guard let base = exact ?? matches.first(where: { !Roster.isFun($0.key) }) ?? matches.first else { return nil }
        if fun, !Roster.isFun(base.key), let entry = Roster.entry(for: base.key), entry.fun != nil { return Roster.species(entry.funKey) }
        return base
    }

    @discardableResult
    func spawn(named name: String, fun: Bool, count: Int) -> Bool {
        guard let s = find(name, fun: fun) else {
            show("Nothing called “\(name)” lives here")
            return false
        }
        spawn(s, count: count)
        return true
    }

    func spawn(_ s: Species, count: Int = 1) {
        tank.spawn(s, count: max(1, count))
        show(count > 1 ? "Here come \(count) × \(s.name)" : "Here comes the \(s.name)")
    }

    func clearOcean() { tank.clear() }

    func peek(_ kind: TankController.Peek, through: Bool) { tank.peek(kind, through: through) }

    // MARK: - Designs from the editor

    func designSaved(_ s: Species) { tank.refresh(s) }

    func designDeleted(key: String) {
        for c in tank.creatures where c.species.key == key { c.leave() }
    }

    // MARK: - Widget

    /// Sprites, the creature catalog and the empty-ocean backdrop, for the widget.
    func exportForWidget() {
        var infos: [SpeciesInfo] = []
        for entry in Roster.entries {
            for fun in entry.fun == nil ? [false] : [false, true] {
                guard let s = Roster.species(fun ? entry.funKey : entry.key) else { continue }
                let (image, half) = Snapshots.sprite(s, size: CGSize(width: 288, height: 216))
                Store.writePNG(image, "fish/\(s.key).png")
                let share = entry.fun == nil ? 1 : fun ? Roster.funChance : 1 - Roster.funChance
                // The widget places everyone across the ocean's heights; in the swamp, fish stay under the water
                // line and ducks on it, so convert.
                let band = TankController.band(s)
                func widgetDepth(_ d: Float) -> Double {
                    if s.floats { return Double((TankController.waterLevel - 0.1 - TankController.swimBottom) / 4.3) }
                    return Double((band.lo + (band.hi - band.lo) * d - TankController.swimBottom) / 4.3)
                }
                infos.append(SpeciesInfo(key: s.key, name: s.name, accent: String(format: "#%06X", s.accent),
                                         depthMin: widgetDepth(s.depth.min), depthMax: widgetDepth(s.depth.max), speed: Double(s.speed),
                                         weight: entry.key == "kraken" ? 0 : entry.weight * share, shark: entry.shark,
                                         groupMin: entry.group.lowerBound, groupMax: entry.group.upperBound,
                                         halfHeight: Double(half), drift: s.motion == .drift && s.wings == nil))
            }
        }
        Store.write(Catalog(species: infos), "catalog.json")
        Store.writePNG(Snapshots.backdrop(tank, size: CGSize(width: 1200, height: 600)), "backdrop.png")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Messages

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { toast = nil }
        }
    }

    // MARK: - Automation (for checking builds from the command line)

    /// `--spawn a,b!,c` brings in creatures by name (`!` for the fun look); `--poke` pokes them all and ripples the
    /// sand just before the shot; `--shot NAME` saves a screenshot
    /// of the ocean into the shared container; `--editor-shot NAME` then one of the editor; then the app quits.
    func startAutomation(editor: EditorModel) {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let spawns = value("--spawn")
        let shot = value("--shot")
        guard spawns != nil || shot != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if let spawns {
                for raw in spawns.split(separator: ",") {
                    let fun = raw.hasSuffix("!")
                    if let s = find(raw.replacingOccurrences(of: "!", with: ""), fun: fun) { tank.spawn(s, count: 1, onScreen: true) }
                }
            }
            guard let shot else { return }
            try? await Task.sleep(for: .seconds(Double(value("--wait") ?? "3") ?? 3))
            if args.contains("--poke") {
                for c in tank.creatures { c.poke(from: c.position - SIMD3(0.5, 0, 0), ocean: tank) }
                tank.rippleSand(at: SIMD3(0, 0.4, 0.5))
                try? await Task.sleep(for: .seconds(0.5))
            }
            frozen = tank.view?.snapshot()
            try? await Task.sleep(for: .seconds(0.5))
            Self.capture(window: "Voxel Aquarium", to: shot)
            frozen = nil
            if let editorShot = value("--editor-shot") {
                openEditor?(Builtins.clownfish().design(named: "Clownfish Remix"))
                try? await Task.sleep(for: .seconds(3))
                editor.frozen = editor.view?.snapshot()
                try? await Task.sleep(for: .seconds(0.5))
                Self.capture(window: "Fish Editor", to: editorShot)
            }
            NSApp.terminate(nil)
        }
    }

    static func capture(window title: String, to name: String) {
        guard let view = NSApp.windows.first(where: { $0.title == title })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: Store.dir.appending(path: name))
    }
}

/// Keeps the Mac (and its display) awake for a while, never for good: up to an hour at a time.
@MainActor
final class KeepAwake: ObservableObject {
    static let choices = [15, 30, 45, 60]

    @Published private(set) var until: Date?
    @Published var minutes: Int = UserDefaults.standard.object(forKey: "keepAwakeMinutes") as? Int ?? 30 {
        didSet {
            UserDefaults.standard.set(minutes, forKey: "keepAwakeMinutes")
            if isOn { start(minutes) }
        }
    }
    private var activity: NSObjectProtocol?
    private var timer: Timer?

    var isOn: Bool {
        get { until != nil }
        set { newValue ? start(minutes) : stop() }
    }

    func start(_ m: Int) {
        endActivity()
        let m = min(60, max(1, m))
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
                                                        reason: "Keeping the ocean on screen")
        until = Date.now.addingTimeInterval(Double(m * 60))
        timer = Timer.scheduledTimer(withTimeInterval: Double(m * 60), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        endActivity()
        until = nil
    }

    private func endActivity() {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    static func label(_ m: Int) -> String { m == 60 ? "1 hour" : "\(m) minutes" }
}
