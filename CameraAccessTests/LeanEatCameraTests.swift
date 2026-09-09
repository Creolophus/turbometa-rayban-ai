import XCTest
import MWDATCore
import MWDATMockDevice
@testable import CameraAccess

@MainActor
final class LeanEatCameraTests: XCTestCase {
    func testIsolatedCaptureDoesNotPresentLegacySheetAndStopsCleanly() async throws {
        try? Wearables.configure()
        MockDeviceKit.shared.enable()
        let device = MockDeviceKit.shared.pairRaybanMeta()
        defer {
            MockDeviceKit.shared.unpairDevice(device)
            MockDeviceKit.shared.disable()
        }
        device.powerOn()
        device.unfold()
        let bundle = Bundle(for: Self.self)
        let video = try XCTUnwrap(bundle.url(forResource: "plant", withExtension: "mp4"))
        let photo = try XCTUnwrap(bundle.url(forResource: "plant", withExtension: "png"))
        device.services.camera.setCameraFeed(fileURL: video)
        device.services.camera.setCapturedImage(fileURL: photo)
        let parent = StreamSessionViewModel(wearables: Wearables.shared)
        let camera = parent.makePhotoSession()
        try await Task.sleep(for: .seconds(1))
        let start = Task { await camera.startSession() }
        for _ in 0..<150 {
            if camera.hasReceivedFirstFrame && camera.streamingStatus == .streaming { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard camera.hasReceivedFirstFrame else {
            start.cancel()
            await camera.cleanup()
            await parent.cleanup()
            return XCTFail("Mock camera did not start")
        }
        let capture = Task { try await camera.capturePhotoData() }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { capture.cancel() }
        }
        do {
            let data = try await capture.value
            XCTAssertFalse(data.isEmpty)
            XCTAssertFalse(camera.showPhotoPreview)
            XCTAssertNil(camera.capturedPhoto)
            XCTAssertFalse(parent.showPhotoPreview)
        } catch { XCTFail("Isolated capture failed: \(error)") }
        timeout.cancel()
        start.cancel()
        await camera.cleanup()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(camera.streamingStatus, .stopped)
        XCTAssertNil(camera.currentVideoFrame)
        XCTAssertFalse(camera.showPhotoPreview)
        await parent.cleanup()
    }
}
