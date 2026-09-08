import SwiftUI
import UIKit
import XCTest
@testable import CameraAccess

@MainActor
final class RecordsVisualTests: XCTestCase {
    func testRecordsAppearances() async throws {
        try await capture(name: "records-light", style: .light)
        try await capture(name: "records-dark", style: .dark)
        try await capture(name: "records-large-text", style: .dark, large: true)
        try await capture(name: "records-english", style: .light, english: true)
        try await capture(name: "records-selection", style: .light, selecting: true)
        try await capture(name: "records-empty", style: .light, empty: true)
    }

    private func capture(name: String, style: UIUserInterfaceStyle, large: Bool = false,
                         english: Bool = false, selecting: Bool = false, empty: Bool = false) async throws {
        let language = LanguageManager.shared.currentLanguage
        LanguageManager.shared.currentLanguage = english ? .english : .chinese
        defer { LanguageManager.shared.currentLanguage = language }
        let now = Date()
        let rows: [RecordEntry] = [
            .liveAI(ConversationRecord(timestamp: now, messages: [
                ConversationMessage(role: .user, content: "周末去哪里走走？"),
                ConversationMessage(role: .assistant, content: "沿着湖边散步，发现城市里的小惊喜。")
            ])),
            .translation(TranslationSession(id: UUID(), records: [TranslateRecord(timestamp: now.addingTimeInterval(-600), sourceLanguage: .zh, targetLanguage: .en, originalText: "请问附近有咖啡店吗？", translatedText: "Is there a coffee shop nearby?")])),
            .audioNote(AudioNote(id: UUID(), title: "周末旅行的灵感", createdAt: now.addingTimeInterval(-1200), updatedAt: now, duration: 138, audioRelativePath: "fixture.m4a", input: .glasses, languageHints: [], diarizationEnabled: false, status: .completed, segments: [AudioTranscriptSegment(beginTimeMs: 0, endTimeMs: 1000, originalText: "去看看山间的日落，记得带上相机。", speakerID: nil)], speakerNames: [:])),
            .quickVision(QuickVisionRecord(timestamp: Calendar.current.date(byAdding: .day, value: -1, to: now)!, mode: .standard, prompt: "", result: "窗边的绿植\n这是一株龟背竹，喜欢明亮的散射光。", thumbnail: UIImage(named: "plant", in: Bundle(for: Self.self), compatibleWith: nil))),
            .liveAI(ConversationRecord(timestamp: Calendar.current.date(byAdding: .day, value: -1, to: now)!, messages: [ConversationMessage(role: .user, content: "帮我规划一次轻松的周末旅行")]))
        ]
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { empty ? [] : rows }, delete: { _ in }))
        model.reload()
        model.isSelecting = selecting
        if selecting { model.selectAll() }
        let root = TabView(selection: .constant(1)) {
            Text("Home").tabItem { Label("tab.home".localized, systemImage: "house.fill") }.tag(0)
            RecordsView(model: model).tabItem { Label("tab.records".localized, systemImage: "list.bullet.rectangle") }.tag(1)
            Text("Gallery").tabItem { Label("tab.gallery".localized, systemImage: "photo.on.rectangle") }.tag(2)
            Text("Settings").tabItem { Label("tab.settings".localized, systemImage: "gearshape") }.tag(3)
        }.tint(HomeStyle.coral)
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
        if let scroll = verticalScrollView(in: controller.view) {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(scroll.contentOffset.y, bottom, accuracy: 1)
            let bottomImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let bottomAttachment = XCTAttachment(image: bottomImage)
            bottomAttachment.name = name + "-scrolled"
            bottomAttachment.lifetime = .keepAlways
            add(bottomAttachment)
        }
    }
    private func verticalScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { self.verticalScrollView(in: $0) }.first
    }
}
