import SwiftUI
import XCTest
@testable import CameraAccess

@MainActor
final class LeanEatVisualTests: XCTestCase {
    func testResultLightAndDark() async throws {
        try await capture(name: "leaneat-result-light", style: .light)
        try await capture(name: "leaneat-result-dark", style: .dark)
        try await capture(name: "leaneat-result-large", style: .light, large: true)
        try await capture(name: "leaneat-result-english", style: .dark, english: true)
        try await capture(name: "leaneat-result-small-window", style: .light, small: true)
    }

    func testReducedTransparency() async throws {
        try XCTSkipUnless(UIAccessibility.isReduceTransparencyEnabled, "Enable Reduce Transparency on the simulator for this check.")
        try await capture(name: "leaneat-result-opaque", style: .light)
    }

    func testFailureAndAnalyzingStates() async throws {
        try await capture(name: "leaneat-analyzing", style: .light, state: "analyzing")
        try await capture(name: "leaneat-failed", style: .dark, state: "failed")
        try await capture(name: "leaneat-save-failed", style: .light, state: "save-failed")
        try await capture(name: "leaneat-library-ready", style: .dark, state: "ready")
    }

    private func capture(name: String, style: UIUserInterfaceStyle, large: Bool = false, english: Bool = false,
                         small: Bool = false, state: String = "result") async throws {
        let language = LanguageManager.shared.currentLanguage
        LanguageManager.shared.currentLanguage = english ? .english : .chinese
        defer { LanguageManager.shared.currentLanguage = language }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LeanEatVisual-" + UUID().uuidString)
        let storage = LeanEatStorage(directory: directory)
        if state == "save-failed" { try Data([0]).write(to: directory) }
        let fixtureJSON = english ? LeanEatTests.response.replacingOccurrences(of: "鸡胸肉", with: "Chicken breast")
            .replacingOccurrences(of: "搭配蔬菜", with: "Serve with vegetables") : LeanEatTests.response
        let nutrition = try LeanEatService.parse(fixtureJSON)
        let model = LeanEatViewModel(storage: storage, analyze: { _ in
            if state == "analyzing" { try await Task.sleep(for: .seconds(60)) }
            if state == "failed" { throw LeanEatError.timeout }
            return nutrition
        })
        // An explicit fixture illustration, not a user's photograph or a model accuracy test.
        let fixture = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 300)).image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 300))
            ("🥗" as NSString).draw(at: CGPoint(x: 245, y: 35), withAttributes: [.font: UIFont.systemFont(ofSize: 150)])
        }
        if state != "ready" { model.selectPhoto { fixture.jpegData(compressionQuality: 0.8)! } }
        for _ in 0..<100 {
            if model.saveState == .saved || model.saveState == .failed || model.phase == .failed ||
                (state == "analyzing" && model.phase == .analyzing) || state == "ready" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        if state == "result" { XCTAssertEqual(model.saveState, .saved) }
        let controller = UIHostingController(rootView: LeanEatView(model: model))
        controller.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = small ? CGRect(x: 0, y: 0, width: 375, height: 667) : scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            model.close()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
            try? FileManager.default.removeItem(at: directory)
        }
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        attach(window, name: name)
        if let scroll = findScroll(controller.view) {
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await Task.sleep(for: .milliseconds(300))
            attach(window, name: name + "-scrolled")
        }
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func findScroll(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView,
           scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll($0) }.first
    }
}
