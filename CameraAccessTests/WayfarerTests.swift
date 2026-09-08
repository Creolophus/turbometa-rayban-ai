import XCTest
import SwiftUI
import RealityKit
@testable import CameraAccess

@MainActor
final class WayfarerTests: XCTestCase {
    func testPoseBoundsAndDirection() {
        var pose = WayfarerPose(yaw: 100, pitch: 10, scale: 9)
        pose.constrain()
        XCTAssertLessThan(abs(pose.yaw), 2 * .pi)
        XCTAssertEqual(pose.pitch, .pi * 75 / 180, accuracy: 0.0001)
        XCTAssertEqual(pose.scale, 2.5)
        pose.scale = -1; pose.pitch = -10; pose.constrain()
        XCTAssertEqual(pose.scale, 0.7)
        XCTAssertEqual(pose.pitch, -.pi * 75 / 180, accuracy: 0.0001)
        XCTAssertFalse(WayfarerPose.acceptsHorizontal(CGPoint(x: 7, y: 0)))
        XCTAssertFalse(WayfarerPose.acceptsHorizontal(CGPoint(x: 20, y: 30)))
        XCTAssertFalse(WayfarerPose.acceptsHorizontal(CGPoint(x: 12, y: 10)))
        XCTAssertTrue(WayfarerPose.acceptsHorizontal(CGPoint(x: -30, y: 10)))
    }

    func testModelViews() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (name, yaw): (String, Float) in [("quarter", -.pi / 6), ("front", 0), ("side", .pi / 2), ("rear", .pi)] {
            window.rootViewController = UIHostingController(rootView: WayfarerViewer(pose: WayfarerPose(yaw: yaw)))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(3))
            let ar = try XCTUnwrap(findAR(window))
            XCTAssertFalse(ar.scene.anchors.isEmpty)
            let renderedFrame = ar.convert(ar.bounds, to: window)
            XCTAssertGreaterThanOrEqual(renderedFrame.minX, 0)
            XCTAssertLessThanOrEqual(renderedFrame.maxX, window.bounds.maxX + 1,
                                     "The backdrop must not push full-screen controls beyond the display")
            let image = await withCheckedContinuation { continuation in ar.snapshot(saveToHDR: false) { continuation.resume(returning: $0) } }
            let attachment = XCTAttachment(image: try XCTUnwrap(image))
            attachment.name = "wayfarer-" + name; attachment.lifetime = .keepAlways; add(attachment)
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            window.rootViewController = UIHostingController(rootView: HomeDashboardView(device: .disconnected, openClawConnected: false, onOpenSettings: {}, onFeature: { _ in }))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(3))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = style == .light ? "wayfarer-home-light" : "wayfarer-home-dark"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
    private func findAR(_ view: UIView) -> ARView? {
        if let view = view as? ARView { return view }
        return view.subviews.lazy.compactMap { self.findAR($0) }.first
    }
}
