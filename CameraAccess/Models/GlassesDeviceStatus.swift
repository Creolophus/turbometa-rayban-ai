import Foundation
import MWDATCore

/// A single snapshot keeps the displayed name and link state tied to one device.
struct GlassesDeviceStatus: Equatable {
    let identifier: DeviceIdentifier?
    let name: String
    let linkState: LinkState

    static let disconnected = GlassesDeviceStatus(identifier: nil, name: "", linkState: .disconnected)

    var displayName: String {
        guard identifier != nil else { return "home.device.none".localized }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "home.device.unnamed".localized : trimmed
    }

    var statusText: String {
        switch linkState {
        case .connected: return "home.device.connected".localized
        case .connecting: return "home.device.connecting".localized
        case .disconnected: return "home.device.disconnected".localized
        }
    }
}

/// The SDK device conforms directly; tests can supply deterministic link events.
protocol GlassesDevice: Sendable {
    var name: String { get }
    var linkState: LinkState { get }
    func addLinkStateListener(_ listener: @escaping @Sendable (LinkState) -> Void) -> any AnyListenerToken
}

extension Device: GlassesDevice {}
