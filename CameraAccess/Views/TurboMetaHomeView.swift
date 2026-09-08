import SwiftUI

struct TurboMetaHomeView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var wearablesViewModel: WearablesViewModel
    @StateObject private var quickVisionManager = QuickVisionManager.shared
    @ObservedObject private var openClawService = OpenClawNodeService.shared
    let apiKey: String
    let onOpenSettings: () -> Void

    @State private var presentedFeature: HomeFeature?

    var body: some View {
        NavigationStack {
            HomeDashboardView(
                device: streamViewModel.connectedDevice,
                openClawConnected: openClawService.connectionState == .connected,
                onOpenSettings: onOpenSettings
            ) { feature in
                if feature == .liveAI {
                    AppRouteManager.shared.pendingRoute = .liveAI
                } else {
                    presentedFeature = feature
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $presentedFeature) { feature in
                switch feature {
                case .liveAI:
                    // Live AI is presented centrally by MainTabView, including Siri routes.
                    EmptyView()
                case .quickVision:
                    QuickVisionView(streamViewModel: streamViewModel, apiKey: apiKey)
                case .translate:
                    LiveTranslateView(streamViewModel: streamViewModel)
                case .audioNote:
                    AudioNoteView()
                case .openClaw:
                    OpenClawChatView(streamViewModel: streamViewModel)
                case .liveStream:
                    SimpleLiveStreamView(streamViewModel: streamViewModel)
                case .rtmp:
                    RTMPStreamingView(streamViewModel: streamViewModel)
                case .leanEat:
                    StreamView(viewModel: streamViewModel, wearablesVM: wearablesViewModel)
                }
            }
        }
        .onAppear {
            quickVisionManager.setStreamViewModel(streamViewModel)
            streamViewModel.refreshConnectedDevice()
            if openClawService.connectionState == .disconnected,
               openClawService.loadGatewayToken() != nil {
                openClawService.connect()
            }
        }
    }
}
