import MWDATCore
import SwiftUI
import UIKit
import XCTest
@testable import CameraAccess

/// Captures the actual SwiftUI homepage and native tab bar in a simulator window.
/// Device data is a deterministic fixture, never represented as a real connection.
@MainActor
final class HomeVisualTests: XCTestCase {
    func testHomeLightAndDark() async throws {
        try await captureHome(name: "home-light", style: .light)
        try await captureHome(name: "home-dark", style: .dark)
    }

    func testHomeEnglishAndAccessibilityLayout() async throws {
        try await captureHome(name: "home-english", style: .light, language: .english)
        try await captureHome(name: "home-accessibility", style: .dark, category: .accessibilityExtraExtraExtraLarge,
                              deviceName: "这是一副名称很长的 Ray-Ban Meta 测试眼镜")
    }

    private func captureHome(
        name: String,
        style: UIUserInterfaceStyle,
        language: AppLanguage = .chinese,
        category: UIContentSizeCategory = .large,
        deviceName: String = "我的 Ray-Ban"
    ) async throws {
        try? Wearables.configure()
        let previousLanguage = LanguageManager.shared.currentLanguage
        LanguageManager.shared.currentLanguage = language
        defer { LanguageManager.shared.currentLanguage = previousLanguage }

        let selector = HomeTestSelector("visual-fixture")
        let fixture = HomeTestDevice(name: deviceName, state: .connected)
        let stream = StreamSessionViewModel(wearables: Wearables.shared, deviceSelector: selector, deviceLookup: { _ in fixture })
        let wearables = WearablesViewModel(wearables: Wearables.shared)
        let root = MainTabView(streamViewModel: stream, wearablesViewModel: wearables)
        let controller = UIHostingController(rootView: root)
        controller.traitOverrides.preferredContentSizeCategory = category
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        print("[HomeVisual] reduceTransparency=\(UIAccessibility.isReduceTransparencyEnabled)")
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        // Wait for the native tab bar's glass and SwiftUI's initial layout to settle.
        try await Task.sleep(for: .seconds(2))
        window.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        XCTAssertGreaterThan(image.size.width, 300)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let scrollView = verticalScrollView(in: controller.view) {
            let bottom = max(-scrollView.adjustedContentInset.top,
                             scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await Task.sleep(for: .milliseconds(300))
            let bottomImage = renderer.image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let bottomAttachment = XCTAttachment(image: bottomImage)
            bottomAttachment.name = name + "-scrolled"
            bottomAttachment.lifetime = .keepAlways
            add(bottomAttachment)
            XCTAssertEqual(scrollView.contentOffset.y, bottom, accuracy: 1)
        }
        await stream.cleanup()
    }

    private func verticalScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
            return scroll
        }
        return view.subviews.lazy.compactMap { self.verticalScrollView(in: $0) }.first
    }
}
