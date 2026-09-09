import SwiftUI
import RealityKit
import Combine

struct WayfarerPose: Equatable {
    var yaw: Float = -.pi / 6
    var pitch: Float = .pi / 10
    var scale: Float = 1

    mutating func constrain() {
        yaw = yaw.truncatingRemainder(dividingBy: 2 * .pi)
        pitch = pitch.truncatingRemainder(dividingBy: 2 * .pi)
        scale = min(2.5, max(0.7, scale))
    }
}

/// A cached, immutable prototype; every visible renderer owns its own clone.
@MainActor
private enum WayfarerResource {
    static var prototypes: [String: Entity] = [:]
    static let studio: EnvironmentResource? = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { context in
            UIColor(white: 0.35, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 60, y: 35, width: 110, height: 100), cornerRadius: 24).fill()
            UIColor(red: 0.8, green: 0.77, blue: 0.9, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 310, y: 50, width: 140, height: 80), cornerRadius: 24).fill()
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? EnvironmentResource(equirectangular: cgImage)
    }()

}

struct WayfarerSurface: View {
    @Binding var pose: WayfarerPose
    @Binding var ready: Bool
    var drawsBackground = true
    var fullscreen = false
    var active = true
    var onOpen: () -> Void = {}
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if drawsBackground {
                    Image(ready ? "HomeGlassesBackdrop" : "HomeGlassesHero")
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped().accessibilityHidden(true)
                }
                WayfarerRenderer(pose: $pose, ready: $ready, fullscreen: fullscreen,
                                 active: active && phase == .active, onOpen: onOpen)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(ready ? 1 : 0)
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("glasses.model.description".localized)
        .accessibilityHint((fullscreen ? "glasses.fullscreen.hint" : "glasses.model.hint").localized)
        .accessibilityAction(named: Text("glasses.rotate.left".localized)) { pose.yaw -= .pi / 8 }
        .accessibilityAction(named: Text("glasses.rotate.right".localized)) { pose.yaw += .pi / 8 }
        .accessibilityAction(named: Text("glasses.reset".localized)) { pose = WayfarerPose() }
        .accessibilityAction(named: Text("glasses.expand".localized), onOpen)
        .accessibilityAction(named: Text("glasses.zoom.in".localized)) { if fullscreen { pose.scale += 0.2; pose.constrain() } }
        .accessibilityAction(named: Text("glasses.zoom.out".localized)) { if fullscreen { pose.scale -= 0.2; pose.constrain() } }
        .onChange(of: reduceMotion) { _, _ in pose = WayfarerPose() }
    }
}

struct WayfarerViewer: View {
    @State var pose: WayfarerPose
    @State private var ready = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var opaque

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            WayfarerSurface(pose: $pose, ready: $ready, fullscreen: true)
                .frame(maxWidth: .infinity).frame(height: 440)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .padding(.horizontal, 16).frame(maxHeight: .infinity)
            HStack {
                control("xmark", label: "glasses.close") { dismiss() }
                Spacer()
                control("arrow.counterclockwise", label: "glasses.reset") { pose = WayfarerPose() }
            }.padding(20)
            VStack {
                Spacer()
                Text("Ray-Ban Meta Wayfarer").font(.title2.bold())
                Text("glasses.fullscreen.hint".localized).font(.subheadline).foregroundStyle(.secondary)
            }.padding(28)
        }
    }

    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if opaque {
                    Image(systemName: icon).frame(width: 48, height: 48)
                        .background(Color(.secondarySystemBackground), in: Circle())
                } else {
                    Image(systemName: icon).frame(width: 48, height: 48)
                        .glassEffect(.regular, in: Circle())
                }
            }
        }
            .buttonStyle(.plain)
            .accessibilityLabel(label.localized)
    }
}

private struct WayfarerRenderer: UIViewRepresentable {
    @Binding var pose: WayfarerPose
    @Binding var ready: Bool
    let fullscreen: Bool
    let active: Bool
    let onOpen: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WayfarerRenderHost {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.isOpaque = false
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableCameraGrain, .disableGroundingShadows])
        view.environment.lighting.resource = WayfarerResource.studio
        let host = WayfarerRenderHost(renderer: view)
        context.coordinator.host = host
        context.coordinator.attach(to: host)
        return host
    }
    func updateUIView(_ view: WayfarerRenderHost, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyPose()
        context.coordinator.updateActivity()
    }
    static func dismantleUIView(_ view: WayfarerRenderHost, coordinator: Coordinator) {
        coordinator.attached = false
        coordinator.load?.cancel()
        coordinator.snapshotWork?.cancel()
        view.renderer.scene.anchors.removeAll()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: WayfarerRenderer
        let pivot = Entity()
        var load: AnyCancellable?
        var attached = true
        weak var host: WayfarerRenderHost?
        var snapshotWork: DispatchWorkItem?
        var lastPose: WayfarerPose?
        var snapshotPose: WayfarerPose?
        var scheduledPose: WayfarerPose?
        var modelInstalled = false
        var isInteracting = false
        var start = WayfarerPose()
        init(_ parent: WayfarerRenderer) { self.parent = parent }

        func attach(to host: WayfarerRenderHost) {
            let view = host.renderer
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(pivot)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 38
            camera.position = [0, 0, 0.34]
            anchor.addChild(camera)
            for (position, intensity): (SIMD3<Float>, Float) in [([0.2, 0.3, 0.3], 2400), ([-0.3, 0.1, 0.2], 1400), ([0, 0.2, -0.3], 1800)] {
                let light = DirectionalLight()
                light.light.intensity = intensity
                light.look(at: .zero, from: position, relativeTo: nil)
                anchor.addChild(light)
            }
            // A soft grounding patch remains on the studio floor while the model turns.
            let shadowImage = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { context in
                let colors = [UIColor.black.withAlphaComponent(0.22).cgColor, UIColor.clear.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                                        endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
                }
            }
            if let cgImage = shadowImage.cgImage,
               let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) {
                var material = UnlitMaterial()
                material.color = .init(tint: .white, texture: .init(texture))
                material.blending = .transparent(opacity: .init(floatLiteral: 1))
                let shadow = ModelEntity(mesh: .generatePlane(width: 0.18, height: 0.035), materials: [material])
                shadow.position = [0, -0.045, -0.065]
                anchor.addChild(shadow)
            }
            view.scene.addAnchor(anchor)
            let resourceName = parent.fullscreen ? "Wayfarer.usdz" : "WayfarerHome.usdz"
            if let model = WayfarerResource.prototypes[resourceName] { install(model) }
            else {
                load = Entity.loadAsync(named: resourceName).sink(receiveCompletion: { _ in }, receiveValue: { [weak self] entity in
                    WayfarerResource.prototypes[resourceName] = entity
                    self?.install(entity)
                })
            }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
            pan.maximumNumberOfTouches = 1
            host.addGestureRecognizer(pan)
            if !parent.fullscreen {
                host.rotationPan = pan
                host.coordinateScrolling()
            }
            if !parent.fullscreen {
                let tap = UITapGestureRecognizer(target: self, action: #selector(open))
                tap.numberOfTapsRequired = 2
                tap.require(toFail: pan)
                host.addGestureRecognizer(tap)
            }
            if parent.fullscreen {
                host.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
            }
        }
        func install(_ prototype: Entity) {
            let model = prototype.clone(recursive: true)
            let bounds = model.visualBounds(relativeTo: nil)
            model.position -= bounds.center
            pivot.addChild(model)
            modelInstalled = true
            applyPose()
            updateActivity()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.attached else { return }
                self.parent.ready = true
            }
        }
        func applyPose() {
            guard lastPose != parent.pose else { return }
            lastPose = parent.pose
            pivot.orientation = simd_quatf(angle: parent.pose.pitch, axis: [1,0,0]) * simd_quatf(angle: parent.pose.yaw, axis: [0,1,0])
            pivot.scale = SIMD3(repeating: parent.pose.scale)
        }
        func updateActivity() {
            guard let host else { return }
            guard parent.active else {
                isInteracting = false
                snapshotWork?.cancel()
                scheduledPose = nil
                host.hideContent()
                return
            }
            let frozen = !isInteracting && snapshotPose == parent.pose && host.still.image != nil
            if frozen {
                host.displaySnapshot()
            } else {
                host.displayRenderer()
                if !isInteracting { scheduleSnapshot() }
            }
        }
        func scheduleSnapshot() {
            guard modelInstalled, parent.active, !isInteracting,
                  snapshotPose != parent.pose, scheduledPose != parent.pose else { return }
            snapshotWork?.cancel()
            let requestedPose = parent.pose
            scheduledPose = requestedPose
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.scheduledPose = nil
                guard self.attached, self.parent.active, !self.isInteracting,
                      self.parent.pose == requestedPose, let host = self.host else { return }
                host.displayRenderer()
                host.renderer.snapshot(saveToHDR: false) { [weak self] image in
                    guard let self, self.attached, self.parent.active, !self.isInteracting,
                          self.parent.pose == requestedPose else { return }
                    self.host?.still.image = image
                    if image != nil { self.snapshotPose = requestedPose }
                    self.updateActivity()
                }
            }
            snapshotWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        func beginInteraction() {
            isInteracting = true
            snapshotWork?.cancel()
            scheduledPose = nil
            host?.displayRenderer()
        }
        func endInteraction() {
            isInteracting = false
            updateActivity()
        }
        @objc func drag(_ pan: UIPanGestureRecognizer) {
            if pan.state == .began {
                start = parent.pose
                beginInteraction()
            }
            let delta = pan.translation(in: pan.view)
            parent.pose.yaw = start.yaw + Float(delta.x) * 0.012
            parent.pose.pitch = start.pitch + Float(delta.y) * 0.008
            parent.pose.constrain()
            applyPose()
            if pan.state == .ended || pan.state == .cancelled || pan.state == .failed {
                endInteraction()
            }
        }
        @objc func pinch(_ pinch: UIPinchGestureRecognizer) {
            if pinch.state == .began {
                start = parent.pose
                beginInteraction()
            }
            parent.pose.scale = start.scale * Float(pinch.scale)
            parent.pose.constrain()
            applyPose()
            if pinch.state == .ended || pinch.state == .cancelled || pinch.state == .failed {
                endInteraction()
            }
        }
        @objc func open() { parent.onOpen() }
    }
}

/// Owns interaction even while the renderer is detached and a still frame is visible.
/// Drags beginning elsewhere continue to be handled normally by the scroll view.
final class WayfarerRenderHost: UIView {
    let renderer: ARView
    let still = UIImageView()
    weak var rotationPan: UIPanGestureRecognizer?
    private weak var coordinatedScroll: UIScrollView?

    init(renderer: ARView) {
        self.renderer = renderer
        super.init(frame: .zero)
        isOpaque = false
        still.contentMode = .scaleToFill
        still.isUserInteractionEnabled = false
        still.isHidden = true
        addSubview(renderer)
        addSubview(still)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        coordinateScrolling()
    }

    func coordinateScrolling() {
        guard let rotationPan else { return }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                if coordinatedScroll !== scroll {
                    scroll.panGestureRecognizer.require(toFail: rotationPan)
                    coordinatedScroll = scroll
                }
                return
            }
            ancestor = view.superview
        }
    }

    func displayRenderer() {
        if renderer.superview !== self {
            insertSubview(renderer, belowSubview: still)
            renderer.frame = bounds
        }
        renderer.isHidden = false
        still.isHidden = true
    }

    func displaySnapshot() {
        renderer.isHidden = true
        renderer.removeFromSuperview()
        still.isHidden = false
    }

    func hideContent() {
        renderer.isHidden = true
        renderer.removeFromSuperview()
        still.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if renderer.superview === self { renderer.frame = bounds }
        still.frame = bounds
    }
}
