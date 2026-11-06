import SwiftUI

@main
struct VoxelAquariumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var library: Library
    @StateObject private var model: AquariumModel
    @StateObject private var editor: EditorModel

    init() {
        let library = Library()
        let model = AquariumModel(library: library)
        _library = StateObject(wrappedValue: library)
        _model = StateObject(wrappedValue: model)
        _editor = StateObject(wrappedValue: EditorModel(library: library, aquarium: model))
    }

    var body: some Scene {
        Window("Voxel Aquarium", id: "tank") {
            AquariumView()
                .environmentObject(library)
                .environmentObject(model)
                .environmentObject(editor)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 760)
        .handlesExternalEvents(matching: ["*"])
        .commands { OceanCommands(model: model, keepAwake: model.keepAwake) }

        // Developer tool: reached from Settings → Developer.
        Window("Fish Editor", id: "editor") {
            EditorView()
                .environmentObject(library)
                .environmentObject(model)
                .environmentObject(editor)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1180, height: 720)
        .handlesExternalEvents(matching: [])

        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
