import SwiftUI

/// Session ownership and lifecycle remain in LiveAIManager; the dashboard only renders state.
struct LiveAIView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject private var liveAIManager = LiveAIManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LiveAIDashboard(
            device: streamViewModel.connectedDevice,
            hasActiveDevice: streamViewModel.hasActiveDevice,
            inputMode: liveAIManager.inputMode,
            isSwitchingMode: liveAIManager.isSwitchingInputMode,
            isConnected: liveAIManager.isConnected,
            isRecording: liveAIManager.isRecording,
            isSpeaking: liveAIManager.isSpeaking,
            responseState: liveAIManager.responseState,
            sentImageCount: liveAIManager.sentImageCount,
            videoFrame: streamViewModel.currentVideoFrame,
            messages: liveAIManager.conversationHistory,
            transcript: liveAIManager.currentTranscript,
            onSwitchMode: { mode in Task { await liveAIManager.switchInputMode(to: mode) } },
            onStop: { Task { await liveAIManager.stopSession() } },
            onBack: { dismiss() }
        )
        .task {
            // 会话唯一启动点。设备校验由 LiveAIManager 统一负责：
            // 未连接眼镜时经 failFatal 走错误弹窗 + TTS，而不是静默返回。
            if !liveAIManager.isRunning {
                // A previous feature may have left a DAT camera session active.
                // Live AI always enters voice-only, so release that session
                // before connecting the realtime audio service.
                if streamViewModel.streamingStatus != .stopped {
                    await streamViewModel.stopSession()
                }
                guard !Task.isCancelled else { return }
                await liveAIManager.startLiveAISession()
            }
        }
        .onDisappear {
            // 关闭界面即结束会话
            print("🎥 LiveAIView: 停止 AI 对话和视频流")
            Task { @MainActor in
                await liveAIManager.stopSession()
            }
        }
        .onChange(of: liveAIManager.isRunning) { _, isRunning in
            // 仅"正常停止"（StopLiveAIIntent 或用户操作）自动关闭页面；
            // 失败时保留页面等待用户确认错误弹窗
            if !isRunning && liveAIManager.stopReason == .stopped {
                dismiss()
            }
        }
        .alert("error".localized, isPresented: $liveAIManager.showError) {
            Button("ok".localized) {
                liveAIManager.dismissError()
                // 会话已因失败终止时，确认错误后关闭页面
                if !liveAIManager.isRunning {
                    dismiss()
                }
            }
        } message: {
            if let error = liveAIManager.errorMessage {
                Text(error)
            }
        }
    }

}

/// Value inputs let appearance tests render every state without starting audio or camera sessions.
struct LiveAIDashboard: View {
    let device: GlassesDeviceStatus
    let hasActiveDevice: Bool
    let inputMode: LiveAIInputMode
    let isSwitchingMode: Bool
    let isConnected: Bool
    let isRecording: Bool
    let isSpeaking: Bool
    let responseState: LiveAIResponseState
    let sentImageCount: Int
    let videoFrame: UIImage?
    let messages: [ConversationMessage]
    let transcript: String
    let onSwitchMode: (LiveAIInputMode) -> Void
    let onStop: () -> Void
    let onBack: () -> Void

    @State private var showConversation = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var language = LanguageManager.shared

    private var isVision: Bool { inputMode == .vision }
    private var activity: String {
        if responseState == .failed { return responseState.displayName }
        if !isConnected { return "liveai.connecting".localized }
        if isSpeaking || responseState == .playing { return "liveai.speaking".localized }
        if responseState == .waiting { return responseState.displayName }
        if isRecording { return "liveai.dashboard.listening".localized }
        return "liveai.status.ready".localized
    }

    var body: some View {
        ZStack {
            background
            if hasActiveDevice {
                VStack(spacing: 12) {
                    VStack(spacing: 18) {
                        header
                        modeControl
                    }
                    // Keep session controls usable at accessibility sizes; transcripts still scale fully.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    conversation
                        // Do not draw scrolling messages over the title or privacy disclosure.
                        // The lower edge still extends beneath the floating glass dock.
                        .mask { Rectangle().ignoresSafeArea(edges: .bottom) }
                        .safeAreaInset(edge: .bottom, spacing: 12) {
                            controls.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        }
                }
            } else {
                disconnected
            }
        }
        .tint(HomeStyle.coral)
        // Camera content needs consistent contrast, independent of the system theme.
        .environment(\.colorScheme, isVision ? .dark : colorScheme)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                HomeStyle.background
                if isVision, let videoFrame {
                    Image(uiImage: videoFrame)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    Color.black.opacity(0.28)
                    LinearGradient(colors: [.black.opacity(0.45), .clear, .black.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live AI").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { deviceLabel; Spacer(minLength: 8); deviceStatus }
                VStack(alignment: .leading, spacing: 6) { deviceLabel; deviceStatus }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isVision ? 14 : 0)
        .background(isVision ? Color.clear : HomeStyle.background)
        .modifier(LiveAISurface(glass: isVision))
    }

    private var deviceLabel: some View {
        Label(device.displayName, systemImage: "eyeglasses")
            .font(.subheadline).foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel(device.displayName)
    }

    private var deviceStatus: some View {
        HStack(spacing: 5) {
            Circle().fill(device.linkState == .connected ? Color.green : Color.orange)
                .frame(width: 6, height: 6).accessibilityHidden(true)
            Text(device.statusText).font(.caption)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var modeControl: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(LiveAIInputMode.allCases) { mode in
                    Button { onSwitchMode(mode) } label: {
                        Label(mode == .voice ? "liveai.dashboard.voice".localized : "liveai.dashboard.vision".localized,
                              systemImage: mode == .voice ? "waveform" : "video")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
                            .foregroundStyle(inputMode == mode ? Color.white : Color.primary)
                            .background(inputMode == mode ? HomeStyle.coral : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSwitchingMode)
                    .accessibilityLabel(mode.displayName)
                    .accessibilityAddTraits(inputMode == mode ? .isSelected : [])
                    .accessibilityIdentifier("liveai.mode.\(mode.rawValue)")
                }
            }
            .padding(4)
            .modifier(LiveAIGlassCapsule())
            HStack(alignment: .top, spacing: 5) {
                if isSwitchingMode { ProgressView().controlSize(.mini) }
                Text(privacyText)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var privacyText: String {
        if isSwitchingMode { return "liveai.dashboard.switching".localized }
        if isVision && videoFrame == nil { return "liveai.dashboard.waitingCamera".localized }
        let base = inputMode.privacyDescription
        return isVision ? base + " · " + String(format: "liveai.input.vision.count".localized, sentImageCount) : base
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if showConversation {
                        ForEach(messages) { message in
                            LiveAIMessageCard(message: message, isVision: isVision).id(message.id)
                        }
                        if !transcript.isEmpty {
                            LiveAIMessageCard(message: ConversationMessage(role: .assistant, content: transcript), isVision: isVision)
                                .id("current")
                        }
                    }
                    VStack(spacing: 12) {
                        waveform
                        Text(activity).font(.subheadline).foregroundStyle(isVision ? .primary : .secondary)
                        if messages.isEmpty && transcript.isEmpty {
                            Text("liveai.dashboard.hint".localized)
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        if !showConversation {
                            Text("liveai.dashboard.hidden".localized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, messages.isEmpty || !showConversation ? 60 : 24)
                    .id("activity")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: messages.count) { _, _ in scrollToLatest(proxy) }
            .onChange(of: transcript) { _, _ in scrollToLatest(proxy) }
            .onChange(of: showConversation) { _, visible in
                if visible { scrollToLatest(proxy) }
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard showConversation else { return }
        let action = {
            if !transcript.isEmpty { proxy.scrollTo("current", anchor: .bottom) }
            else if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
        if reduceMotion { action() } else { withAnimation(.easeOut(duration: 0.2), action) }
    }

    private var waveform: some View {
        Image(systemName: "waveform")
            .font(.system(size: 32, weight: .medium))
            .foregroundStyle(LinearGradient(colors: [HomeStyle.coral, HomeStyle.violet], startPoint: .leading, endPoint: .trailing))
            .symbolEffect(.variableColor.iterative, options: .repeating,
                          isActive: !reduceMotion && (isRecording || isSpeaking))
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if reduceMotion { showConversation.toggle() }
                else { withAnimation(.easeInOut(duration: 0.2)) { showConversation.toggle() } }
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: showConversation ? "eye" : "eye.slash").font(.title3)
                        .frame(width: 48, height: 48)
                        .modifier(LiveAIGlassCapsule())
                    Text(showConversation ? "liveai.dashboard.hide".localized : "liveai.dashboard.show".localized)
                        .font(.caption2).multilineTextAlignment(.center)
                }
                .frame(minWidth: 64, minHeight: 64)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("liveai.toggleConversation")
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize { waveform.scaleEffect(0.8) }
            Spacer(minLength: 0)
            Button(action: onStop) {
                VStack(spacing: 5) {
                    Image(systemName: "stop.fill").font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(HomeStyle.coral, in: Circle())
                    Text("liveai.dashboard.end".localized).font(.caption2)
                }
                .frame(minWidth: 64, minHeight: 64)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("liveai.end")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .modifier(LiveAIGlassCapsule())
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    private var disconnected: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "eyeglasses").font(.system(size: 64)).foregroundStyle(HomeStyle.violet)
            Text("liveai.device.notconnected.title".localized).font(.title2.bold())
            Text("liveai.device.notconnected.message".localized)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button(action: onBack) {
                Label("liveai.device.backtohome".localized, systemImage: "chevron.left")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain).modifier(LiveAIGlassCapsule())
        }
        .padding(24)
    }
}

private struct LiveAIGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(HomeStyle.card, in: Capsule()) }
        else { content.glassEffect(.regular, in: Capsule()) }
    }
}

private struct LiveAISurface: ViewModifier {
    var glass: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if glass {
            if reduceTransparency { content.background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 22)) }
            else { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22)) }
        } else { content }
    }
}

private struct LiveAIMessageCard: View {
    let message: ConversationMessage
    let isVision: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser && !typeSize.isAccessibilitySize { Spacer(minLength: 40) }
            if !isUser && !typeSize.isAccessibilitySize {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(HomeStyle.violet)
                    .frame(width: 36, height: 36).modifier(LiveAIGlassCapsule())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !isUser { Text("Live AI").font(.caption).foregroundStyle(HomeStyle.violet) }
                Text(message.content)
                    .font(.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .background(isVision ? Color.clear : (isUser ? HomeStyle.coral.opacity(0.12) : HomeStyle.card),
                                in: RoundedRectangle(cornerRadius: 20))
                    .modifier(LiveAISurface(glass: isVision))
            }
            if !isUser && !typeSize.isAccessibilitySize { Spacer(minLength: 24) }
        }
        .accessibilityElement(children: .combine)
    }
}
