import SceneKit
import SwiftUI

// MARK: - Look

enum Theme {
    static let ink = Color(red: 0.92, green: 0.97, blue: 1)
    static let muted = Color(red: 0.62, green: 0.76, blue: 0.86)
    static let cyan = Color(red: 0.38, green: 0.9, blue: 1)
    static let panel = Color(red: 0.03, green: 0.1, blue: 0.16).opacity(0.88)
    static let card = Color(red: 0.07, green: 0.18, blue: 0.26)
    static let line = Color(red: 0.45, green: 0.8, blue: 0.95).opacity(0.25)
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(2).foregroundStyle(Theme.cyan)
    }
}

struct PillButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(primary ? Color(red: 0.02, green: 0.12, blue: 0.18) : Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 34)
            .background(primary ? Theme.cyan : Theme.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Ocean window

/// The ocean, edge to edge. Nothing to manage: it's a background.
struct AquariumView: View {
    @EnvironmentObject private var model: AquariumModel
    @EnvironmentObject private var editor: EditorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let still = model.frozen { Image(nsImage: still).resizable() } else { TankSceneView(model: model, tank: model.tank) }
        }
        .ignoresSafeArea()
        .overlay {
            if let tag = model.nameTag {
                GeometryReader { _ in
                    NameTagView(tag: tag).position(tag.point).allowsHitTesting(false)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.nameTag?.id)
        .overlay(alignment: .trailing) {
            if let info = model.info {
                CreatureCard(info: info)
                    .padding(.trailing, 28)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45), value: model.info)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Theme.panel, in: Capsule())
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .frame(minWidth: 640, minHeight: 400)
        .background(Color(red: 0.02, green: 0.08, blue: 0.13))
        .onAppear {
            model.openEditor = { design in
                if let design { editor.open(design) }
                openWindow(id: "editor")
            }
            model.startAutomation(editor: editor)
        }
    }
}

// MARK: - SceneKit view

struct TankSceneView: NSViewRepresentable {
    let model: AquariumModel
    /// The world being shown; when it changes SwiftUI calls `updateNSView`, which swaps in the new scene.
    let tank: TankController

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> TrackingSCNView {
        let view = TrackingSCNView(frame: .zero, options: nil)
        view.scene = model.tank.scene
        view.pointOfView = model.tank.cameraNode
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        view.backgroundColor = NSColor(rgb: 0x061420)
        model.tank.view = view
        view.onPointer = { [weak model] p in
            model?.tank.parallaxTarget = p.map { SIMD2(Float($0.x - 0.5) * 0.9, Float($0.y - 0.5) * 0.5) } ?? .zero
        }
        view.onClick = { [weak model] p, count in model?.click(at: p, count: count) }
        let link = view.displayLink(target: context.coordinator, selector: #selector(Coordinator.tick(_:)))
        link.add(to: .main, forMode: .common)
        context.coordinator.link = link
        return view
    }

    /// A new world: point the view at its scene and camera.
    func updateNSView(_ view: TrackingSCNView, context: Context) {
        guard view.scene !== model.tank.scene else { return }
        view.scene = model.tank.scene
        view.pointOfView = model.tank.cameraNode
        model.tank.view = view
    }

    static func dismantleNSView(_ view: TrackingSCNView, coordinator: Coordinator) { coordinator.link?.invalidate() }

    final class Coordinator: NSObject {
        let model: AquariumModel
        var link: CADisplayLink?
        private var last: CFTimeInterval = 0

        init(model: AquariumModel) { self.model = model }

        @objc func tick(_ link: CADisplayLink) {
            let dt = last == 0 ? 1.0 / 60 : link.timestamp - last
            last = link.timestamp
            MainActor.assumeIsolated { model.frame(dt: Float(dt)) }
        }
    }
}

/// An SCNView that reports where the pointer is: as a fraction of the view (0...1, bottom-left origin)
/// for parallax, and in view points for hover effects.
final class TrackingSCNView: SCNView {
    var onPointer: ((CGPoint?) -> Void)?
    var onPointerPixel: ((CGPoint?) -> Void)?
    /// A click in the view, in view points, with how many clicks in a row it was (2 for a double click).
    var onClick: ((CGPoint, Int) -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onClick?(convert(event.locationInWindow, from: nil), event.clickCount)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onPointer?(CGPoint(x: p.x / max(1, bounds.width), y: p.y / max(1, bounds.height)))
        onPointerPixel?(p)
    }

    override func mouseExited(with event: NSEvent) {
        onPointer?(nil)
        onPointerPixel?(nil)
    }
}
