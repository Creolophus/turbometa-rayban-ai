import SwiftUI
import UIKit
import XCTest
@testable import CameraAccess

/// Presentation-only fixtures: no LiveAIManager, microphones, network or camera sessions.
@MainActor
final class LiveAIVisualTests: XCTestCase {
    func testLiveAIAppearances() async throws {
        try await capture(name: "liveai-voice-light", style: .light)
        try await capture(name: "liveai-voice-dark", style: .dark)
        try await capture(name: "liveai-vision", style: .dark, vision: true)
        try await capture(name: "liveai-large-text", style: .light, large: true)
        try await capture(name: "liveai-english", style: .light, english: true)
        try await capture(name: "liveai-disconnected", style: .light, disconnected: true)
        try await capture(name: "liveai-connecting", style: .dark, connecting: true)
    }

    func testLiveAIReducedTransparency() async throws {
        try XCTSkipUnless(UIAccessibility.isReduceTransparencyEnabled, "Enable Reduce Transparency on the test device.")
        try await capture(name: "liveai-reduced-transparency", style: .dark, vision: true)
    }

    private func capture(name: String, style: UIUserInterfaceStyle, vision: Bool = false,
                         large: Bool = false, english: Bool = false, disconnected: Bool = false,
                         connecting: Bool = false) async throws {
        let oldLanguage = LanguageManager.shared.currentLanguage
        LanguageManager.shared.currentLanguage = english ? .english : .chinese
        defer { LanguageManager.shared.currentLanguage = oldLanguage }
        let messages = [
            ConversationMessage(role: .user, content: "这盆植物应该怎么养？"),
            ConversationMessage(role: .assistant, content: "放在明亮的散射光下，等表层土壤干了再浇水。避免长时间暴晒。"),
            ConversationMessage(role: .user, content: "大概多久浇一次水？")
        ]
        let root = LiveAIDashboard(
            device: disconnected ? .disconnected : GlassesDeviceStatus(identifier: "fixture", name: large ? "我的名称非常长的 Ray-Ban Meta 测试眼镜" : "Ray-Ban Meta", linkState: .connected),
            hasActiveDevice: !disconnected, inputMode: vision ? .vision : .voice,
            isSwitchingMode: false, isConnected: !connecting,
            isRecording: !connecting, isSpeaking: false, responseState: .idle,
            sentImageCount: vision ? 6 : 0,
            videoFrame: UIImage(named: "plant", in: Bundle(for: Self.self), compatibleWith: nil),
            messages: connecting ? [] : messages, transcript: "",
            onSwitchMode: { _ in }, onStop: {}, onBack: {}
        )
        let controller = UIHostingController(rootView: root)
        controller.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .seconds(2))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if large, let scroll = verticalScrollView(in: controller.view) {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await Task.sleep(for: .milliseconds(300))
            // LazyVStack replaces estimated row heights after scrolling into view.
            let settledBottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            XCTAssertEqual(scroll.contentOffset.y, settledBottom, accuracy: 1)
            let scrolled = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: scrolled)
            attachment.name = name + "-scrolled"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    private func verticalScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { self.verticalScrollView(in: $0) }.first
    }

}
