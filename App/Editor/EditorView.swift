import SceneKit
import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var editor: EditorModel
    @EnvironmentObject private var library: Library
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider().overlay(Theme.line)
            ZStack(alignment: .top) {
                Group {
                    if let still = editor.frozen { Image(nsImage: still).resizable() } else { EditorSceneView(editor: editor) }
                }
                toolbar.padding(12)
                VStack {
                    Spacer()
                    Text(hint).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.panel, in: Capsule())
                        .padding(12)
                }
                .allowsHitTesting(false)
            }
            Divider().overlay(Theme.line)
            inspector.frame(width: 270)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .background(Color(red: 0.02, green: 0.08, blue: 0.13))
        .foregroundStyle(Theme.ink)
        .confirmationDialog("Delete “\(editor.design.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { editor.delete() }
        } message: {
            Text("Any of these swimming around now will head off.")
        }
    }

    private var hint: String {
        switch editor.tool {
        case .add: "Click a block face to add to the \(editor.part.rawValue.lowercased()) · drag to orbit · scroll to zoom"
        case .erase: "Click a block to remove it"
        case .paint: "Click a block to paint it"
        case .pick: "Click a block to pick up its colour"
        }
    }

    // MARK: Left: designs

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Your designs")
            ScrollView {
                VStack(spacing: 4) {
                    if !editor.isSaved { row(name: editor.design.name + " (unsaved)", selected: true) {} }
                    ForEach(library.designs) { d in
                        row(name: d.name, selected: d.id == editor.design.id) { editor.open(d) }
                    }
                }
            }
            Menu {
                Button("Blank starter fish") { editor.newBlank() }
                Divider()
                ForEach(library.builtins) { s in Button("Remix \(s.name)") { editor.newFrom(s) } }
            } label: {
                Label("New design", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
    }

    private func row(name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "fish").foregroundStyle(Theme.cyan)
                Text(name).lineLimit(1)
                Spacer()
            }
            .font(.system(size: 13, weight: selected ? .bold : .regular))
            .padding(.horizontal, 10).frame(height: 30)
            .background(selected ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Centre: tools

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(EditorModel.Tool.allCases) { t in
                Button { editor.tool = t } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .background(editor.tool == t ? Theme.cyan : Theme.card, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(editor.tool == t ? Color.black : Theme.ink)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(t.key, modifiers: [])
                .help("\(t.rawValue) (\(String(t.key.character)))")
            }
            Divider().frame(height: 22).padding(.horizontal, 4)
            Picker("", selection: $editor.part) {
                ForEach(EditorModel.Part.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize().labelsHidden()
            .help("Which part new blocks join. Tail blocks wag when the fish swims.")
            Toggle("Mirror", isOn: $editor.mirror).toggleStyle(.button).fixedSize()
                .help("Copy edits to the other side of the fish")
            Toggle("Wag", isOn: $editor.wagPreview).toggleStyle(.button).fixedSize()
                .help("Preview the tail wag")
            Divider().frame(height: 22).padding(.horizontal, 4)
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
            Button { editor.frameCamera() } label: { Image(systemName: "scope") }.help("Reset view")
        }
        .padding(8)
        .panel()
    }

    // MARK: Right: inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Fish")
                    TextField("Name", text: editor.binding(\.name)).textFieldStyle(.roundedBorder)
                    TextField("Description", text: editor.binding(\.blurb), axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...3)
                    Text("\(editor.voxelCount) blocks").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Colour")
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 8), spacing: 6) {
                        ForEach(EditorModel.palette, id: \.self) { c in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: NSColor(rgb: c)))
                                .frame(width: 24, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(editor.rgb == c ? Theme.cyan : .white.opacity(0.15),
                                                                                  lineWidth: editor.rgb == c ? 2 : 1))
                                .onTapGesture {
                                    editor.rgb = c
                                    if editor.tool == .erase || editor.tool == .pick { editor.tool = .paint }
                                }
                        }
                    }
                    HStack {
                        ColorPicker("Custom", selection: editor.color, supportsOpacity: false)
                        Spacer()
                        Toggle("Glow", isOn: $editor.glow).help("Glowing blocks shine without light, like a neon tetra")
                    }
                    .font(.system(size: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Swimming")
                    slider("Speed", editor.binding(\.speed), 0.3...2, "%.1f×")
                    slider("Size in tank", editor.binding(\.voxelSize), 0.04...0.1, "%.3f")
                    slider("Tail wag", editor.binding(\.wag), 2...14, "%.0f")
                    slider("Wag angle", editor.binding(\.wagAngle), 5...40, "%.0f°")
                    slider("Swims from", editor.binding(\.depthMin), 0...1, "%.2f", note: "0 = floor, 1 = surface")
                    slider("Swims up to", editor.binding(\.depthMax), 0...1, "%.2f")
                    Toggle("Swims in a school", isOn: editor.binding(\.schooling)).font(.system(size: 12))
                    Toggle("Puffs up when poked", isOn: editor.binding(\.puffs)).font(.system(size: 12))
                }

                VStack(spacing: 8) {
                    Button(editor.isSaved && !editor.dirty ? "Saved" : "Save") { editor.save() }
                        .buttonStyle(PillButtonStyle(primary: true))
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(editor.voxelCount == 0)
                        .frame(maxWidth: .infinity)
                    Button("Spawn in ocean") { editor.addToTank() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(editor.voxelCount == 0)
                    if editor.isSaved {
                        Button("Delete design", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.plain).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    private func slider(_ title: String, _ value: Binding<Float>, _ range: ClosedRange<Float>, _ format: String,
                        note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .font(.system(size: 12))
            Slider(value: value, in: range).controlSize(.small)
            if let note { Text(note).font(.system(size: 10)).foregroundStyle(Theme.muted) }
        }
    }
}

// MARK: - SceneKit view

struct EditorSceneView: NSViewRepresentable {
    let editor: EditorModel

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeNSView(context: Context) -> TrackingSCNView {
        let view = TrackingSCNView(frame: .zero, options: nil)
        view.scene = editor.scene
        view.pointOfView = editor.cameraNode
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.isPlaying = true
        view.backgroundColor = NSColor(rgb: 0x0B1A26)
        editor.view = view
        editor.frameCamera()
        view.onPointerPixel = { [weak editor] p in editor?.hover(at: p) }
        view.addGestureRecognizer(NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.click(_:))))
        let link = view.displayLink(target: context.coordinator, selector: #selector(Coordinator.tick(_:)))
        link.add(to: .main, forMode: .common)
        context.coordinator.link = link
        return view
    }

    func updateNSView(_ view: TrackingSCNView, context: Context) {}

    static func dismantleNSView(_ view: TrackingSCNView, coordinator: Coordinator) { coordinator.link?.invalidate() }

    final class Coordinator: NSObject {
        let editor: EditorModel
        var link: CADisplayLink?
        private var last: CFTimeInterval = 0

        init(editor: EditorModel) { self.editor = editor }

        @objc func tick(_ link: CADisplayLink) {
            let dt = last == 0 ? 1.0 / 60 : link.timestamp - last
            last = link.timestamp
            MainActor.assumeIsolated { editor.frame(dt: dt) }
        }

        @objc func click(_ g: NSClickGestureRecognizer) {
            guard let view = g.view else { return }
            MainActor.assumeIsolated { editor.click(at: g.location(in: view)) }
        }
    }
}
