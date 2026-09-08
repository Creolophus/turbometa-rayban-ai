import Foundation
import MWDATCore
import XCTest
@testable import CameraAccess

@MainActor
final class HomeDeviceStatusTests: XCTestCase {
    override func setUp() async throws {
        try? Wearables.configure()
    }

    func testConnectedDeviceUsesSDKNameAndLinkState() async throws {
        let selector = HomeTestSelector("one")
        let device = HomeTestDevice(name: "旅行眼镜", state: .connecting)
        let model = makeModel(selector, devices: ["one": device])
        XCTAssertTrue(model.hasActiveDevice)
        XCTAssertEqual(model.connectedDevice.name, "旅行眼镜")
        XCTAssertEqual(model.connectedDevice.linkState, .connecting)
        device.send(.connected)
        try await eventually { model.connectedDevice.linkState == .connected }
        XCTAssertEqual(model.connectedDevice.identifier, "one")
        await model.cleanup()
    }

    func testBlankNameUsesLocalizedFallbackWithoutLeakingIdentifier() async {
        let model = makeModel(HomeTestSelector("private-device-id"), devices: [
            "private-device-id": HomeTestDevice(name: " \n ", state: .connected)
        ])
        XCTAssertEqual(model.connectedDevice.displayName, "home.device.unnamed".localized)
        XCTAssertFalse(model.connectedDevice.displayName.contains("private-device-id"))
        await model.cleanup()
    }

    func testSelectionClearedRemovesOldNameAndStatus() async throws {
        let selector = HomeTestSelector("one")
        let device = HomeTestDevice(name: "我的眼镜", state: .connected)
        let model = makeModel(selector, devices: ["one": device])
        selector.select(nil)
        try await eventually { model.connectedDevice.identifier == nil }
        XCTAssertEqual(model.connectedDevice, .disconnected)
        XCTAssertEqual(model.connectedDevice.displayName, "home.device.none".localized)
        XCTAssertFalse(model.hasActiveDevice)
        device.send(.connected, includingCancelled: true)
        await drainCallbacks()
        XCTAssertEqual(model.connectedDevice, .disconnected)
        await model.cleanup()
    }

    func testDeviceSwitchRejectsLateCallbacksFromOldDevice() async throws {
        let selector = HomeTestSelector("one")
        let first = HomeTestDevice(name: "第一副", state: .connected)
        let second = HomeTestDevice(name: "第二副", state: .connecting)
        let model = makeModel(selector, devices: ["one": first, "two": second])
        selector.select("two")
        try await eventually { model.connectedDevice.identifier == "two" }
        first.send(.disconnected, includingCancelled: true)
        await drainCallbacks()
        XCTAssertEqual(model.connectedDevice.name, "第二副")
        XCTAssertEqual(model.connectedDevice.linkState, .connecting)
        second.send(.connected)
        try await eventually { model.connectedDevice.linkState == .connected }
        try await eventually { first.allListenersCancelled }
        await model.cleanup()
    }

    func testForegroundRefreshReadsRenamedDevice() async {
        let selector = HomeTestSelector("one")
        let device = HomeTestDevice(name: "原名称", state: .connected)
        let model = makeModel(selector, devices: ["one": device])
        device.rename("新的 Ray-Ban 名称")
        model.refreshConnectedDevice()
        XCTAssertEqual(model.connectedDevice.displayName, "新的 Ray-Ban 名称")
        await model.cleanup()
    }

    func testRefreshOfSameDeviceRejectsPreviousListenerGeneration() async {
        let selector = HomeTestSelector("one")
        let device = HomeTestDevice(name: "我的眼镜", state: .connected)
        let model = makeModel(selector, devices: ["one": device])
        await drainCallbacks()
        let oldCallback = device.latestCallback
        model.refreshConnectedDevice()
        oldCallback?(.disconnected)
        await drainCallbacks()
        XCTAssertEqual(model.connectedDevice.linkState, .connected)
        await model.cleanup()
    }

    func testStoppingFeatureSessionKeepsHomeDeviceUpdatesAlive() async throws {
        let selector = HomeTestSelector("one")
        let device = HomeTestDevice(name: "我的眼镜", state: .connected)
        let model = makeModel(selector, devices: ["one": device])
        await model.stopSession()
        device.send(.disconnected)
        try await eventually { model.connectedDevice.linkState == .disconnected }
        // An available SDK selection is distinct from the actual Bluetooth link state.
        XCTAssertTrue(model.hasActiveDevice)
        device.send(.connected)
        try await eventually { model.connectedDevice.linkState == .connected }
        await model.cleanup()
    }

    func testCleanupCancelsListenersAndRejectsQueuedEvents() async {
        let selector = HomeTestSelector("one")
        let device = HomeTestDevice(name: "我的眼镜", state: .connected)
        let model = makeModel(selector, devices: ["one": device])
        await drainCallbacks()
        await model.cleanup()
        device.send(.connected, includingCancelled: true)
        await drainCallbacks()
        XCTAssertEqual(model.connectedDevice, .disconnected)
        XCTAssertTrue(device.allListenersCancelled)
    }

    private func makeModel(_ selector: HomeTestSelector, devices: [String: HomeTestDevice]) -> StreamSessionViewModel {
        StreamSessionViewModel(wearables: Wearables.shared, deviceSelector: selector, deviceLookup: { devices[$0] })
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for device status", file: file, line: line)
    }

    private func drainCallbacks() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

final class HomeTestSelector: DeviceSelector, @unchecked Sendable {
    private let lock = NSLock()
    private var selected: DeviceIdentifier?
    private let stream: AsyncStream<DeviceIdentifier?>
    private let continuation: AsyncStream<DeviceIdentifier?>.Continuation

    init(_ identifier: DeviceIdentifier?) {
        selected = identifier
        let pair = AsyncStream<DeviceIdentifier?>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
        continuation.yield(identifier)
    }

    var activeDevice: DeviceIdentifier? { lock.withLock { selected } }
    func activeDeviceStream() -> AnyAsyncSequence<DeviceIdentifier?> { AnyAsyncSequence(stream) }
    func select(_ identifier: DeviceIdentifier?) {
        lock.withLock { selected = identifier }
        continuation.yield(identifier)
    }
    deinit { continuation.finish() }
}

final class HomeTestDevice: GlassesDevice, @unchecked Sendable {
    private let lock = NSLock()
    private var storedName: String
    private var state: LinkState
    private var listeners: [(HomeTestListener, @Sendable (LinkState) -> Void)] = []

    init(name: String, state: LinkState) {
        storedName = name
        self.state = state
    }
    var name: String { lock.withLock { storedName } }
    var linkState: LinkState { lock.withLock { state } }
    var allListenersCancelled: Bool { lock.withLock { listeners.allSatisfy { $0.0.cancelled } } }
    var latestCallback: (@Sendable (LinkState) -> Void)? { lock.withLock { listeners.last?.1 } }
    func rename(_ name: String) { lock.withLock { storedName = name } }
    func addLinkStateListener(_ listener: @escaping @Sendable (LinkState) -> Void) -> any AnyListenerToken {
        let token = HomeTestListener()
        lock.withLock { listeners.append((token, listener)) }
        return token
    }
    func send(_ newState: LinkState, includingCancelled: Bool = false) {
        let callbacks = lock.withLock {
            state = newState
            return listeners
        }
        for (token, callback) in callbacks where includingCancelled || !token.cancelled {
            callback(newState)
        }
    }
}

private final class HomeTestListener: AnyListenerToken, @unchecked Sendable {
    private let lock = NSLock()
    private var didCancel = false
    var cancelled: Bool { lock.withLock { didCancel } }
    func cancel() async { lock.withLock { didCancel = true } }
}
