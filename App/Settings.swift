import SwiftUI

/// The Settings window (⌘,): ocean options, and developer tools for summoning creatures by name.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "water.waves") }
            DeveloperSettings().tabItem { Label("Developer", systemImage: "hammer") }
        }
        .frame(width: 520)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject private var model: AquariumModel

    var body: some View {
        Form {
            Section {
                Picker("World", selection: $model.biome) {
                    ForEach(Biome.allCases) { Text($0.title).tag($0) }
                }
                Text("The open ocean, a Louisiana swamp, or a rainforest in the rain. The widget shows the same one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("No sharks", isOn: $model.noSharks)
                Text("Sharks (and the swamp's alligators, and the forest's jaguars) are rare, and they only ever scare everyone off. "
                     + "Turn this on and they never visit, here or in the widget.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keep this Mac awake") {
                KeepAwakeControls(keepAwake: model.keepAwake)
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }
}

struct KeepAwakeControls: View {
    @ObservedObject var keepAwake: KeepAwake

    var body: some View {
        Toggle("Don't sleep", isOn: Binding(get: { keepAwake.isOn }, set: { keepAwake.isOn = $0 }))
        Picker("For", selection: $keepAwake.minutes) {
            ForEach(KeepAwake.choices, id: \.self) { Text(KeepAwake.label($0)).tag($0) }
        }
        if let until = keepAwake.until {
            Text("Staying awake until \(until.formatted(date: .omitted, time: .shortened)), then it switches itself off.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Keeps the screen on and the Mac from sleeping for up to an hour at a time. It never stays on for good.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DeveloperSettings: View {
    @EnvironmentObject private var model: AquariumModel
    @EnvironmentObject private var library: Library
    @State private var name = ""
    @State private var fun = false
    @State private var count = 1
    @State private var through = false

    private var matches: [Species] {
        let q = name.lowercased().trimmingCharacters(in: .whitespaces)
        return model.spawnable.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.key.contains(q) }
    }

    var body: some View {
        Form {
            Section("Summon by name") {
                HStack {
                    TextField("Name", text: $name, prompt: Text("hammerhead, narwhal, kraken…"))
                        .onSubmit { model.spawn(named: name, fun: fun, count: count) }
                    Button("Spawn") { model.spawn(named: name, fun: fun, count: count) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                Toggle("Rare fun version, if it has one", isOn: $fun)
                Stepper("How many: \(count)", value: $count, in: 1...12)
                List(matches, id: \.key) { s in
                    HStack {
                        Text(s.name)
                        if Roster.isFun(s.key) { Text("rare").font(.caption2.bold()).foregroundStyle(.orange) }
                        if s.isCustom { Text("yours").font(.caption2.bold()).foregroundStyle(.teal) }
                        Spacer()
                        Button("Spawn") { model.spawn(s, count: count) }.buttonStyle(.borderless)
                    }
                }
                .frame(height: 220)
            }
            Section(model.biome == .ocean ? "Over the back reef" : model.biome == .swamp ? "Over the bank" : "Over the log") {
                Toggle("Comes on through", isOn: $through)
                HStack {
                    switch model.biome {
                    case .ocean:
                        Button("Fish peeks") { model.peek(.fish, through: through) }
                        Button("Kraken's eye") { model.peek(.krakenEye, through: through) }
                        Button("Tentacles") { model.peek(.tentacles, through: through) }
                    case .swamp:
                        Button("Someone peeks") { model.peek(.fish, through: through) }
                        Button("Gator's eyes") { model.peek(.krakenEye, through: through) }
                    case .rainforest:
                        Button("Someone peeks") { model.peek(.fish, through: through) }
                        Button("Jaguar") { model.peek(.krakenEye, through: through) }
                    }
                }
            }
            Section {
                HStack {
                    Button("Clear everyone out") { model.clearOcean() }
                    Button("Open Fish Editor") { model.openEditor?(nil) }
                    Button("Refresh widget") { model.exportForWidget() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 600)
    }
}

/// The app's "Ocean" menu: no sharks, and keeping the Mac awake for a while.
struct OceanCommands: Commands {
    @ObservedObject var model: AquariumModel
    @ObservedObject var keepAwake: KeepAwake

    var body: some Commands {
        CommandMenu("World") {
            ForEach(Array(Biome.allCases.enumerated()), id: \.element) { i, b in
                Toggle(b.title, isOn: Binding(get: { model.biome == b }, set: { if $0 { model.biome = b } }))
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
            Toggle("No Sharks, Gators or Jaguars", isOn: $model.noSharks)
            Divider()
            Menu("Keep Mac Awake") {
                Toggle("Off", isOn: Binding(get: { !keepAwake.isOn }, set: { if $0 { keepAwake.stop() } }))
                Divider()
                ForEach(KeepAwake.choices, id: \.self) { m in
                    Toggle("For \(KeepAwake.label(m))", isOn: Binding(
                        get: { keepAwake.isOn && keepAwake.minutes == m },
                        set: { on in
                            if on {
                                keepAwake.minutes = m
                                keepAwake.start(m)
                            } else {
                                keepAwake.stop()
                            }
                        }))
                }
            }
            Divider()
            SettingsLink { Text("Developer Settings…") }
        }
    }
}
