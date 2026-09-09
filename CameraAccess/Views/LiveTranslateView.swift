/*
 * Live Translate View
 * 实时翻译主界面
 */

import SwiftUI

struct LiveTranslateView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let coral = Color(red: 0.98, green: 0.36, blue: 0.39)
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LiveTranslateViewModel()
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @State private var showSettings = false
    @State private var shouldAutoScroll = true
    @State private var languageBarHeight: CGFloat = 0

    var body: some View {
        ZStack {
            // 背景
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            // 主内容
            VStack(spacing: 0) {
                // Header
                headerView

                // The scroll viewport extends behind the fixed glass language bar.
                translationArea
                    .overlay(alignment: .top) {
                        languageBar
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                languageBarHeight = $0
                            }
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controlBar
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

        }
        .task {
            // Translation is audio-only; release camera capture from a previous feature.
            if streamViewModel.streamingStatus != .stopped {
                await streamViewModel.stopSession()
            }
            guard !Task.isCancelled else { return }
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .sheet(isPresented: $showSettings) {
            LiveTranslateSettingsView(viewModel: viewModel)
        }
        .alert("livetranslate.error.title".localized, isPresented: $viewModel.showError) {
            if viewModel.errorMessage == "livetranslate.saveFailed".localized {
                Button("livetranslate.retrySave".localized) { viewModel.retrySavingRecords() }
            }
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // 标题
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.title2)
                Text("livetranslate.title".localized)
                    .font(AppTypography.title2)
            }
            .foregroundColor(.primary)

            Spacer()

            // 设置按钮
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            .frame(width: 44, height: 44)
            .modifier(TranslationGlass(reduceTransparency: reduceTransparency))
            .accessibilityLabel("settings.title".localized)

            // 关闭按钮
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .frame(width: 44, height: 44)
            .modifier(TranslationGlass(reduceTransparency: reduceTransparency))
            .accessibilityLabel("livetranslate.close".localized)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(viewModel.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(viewModel.isConnected ? "livetranslate.connected".localized : "livetranslate.connecting".localized)
                .font(AppTypography.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Language Bar

    private var languageBar: some View {
        HStack(spacing: 16) {
            // 源语言
            languageButton(
                language: viewModel.sourceLanguage,
                label: "livetranslate.source".localized
            ) {
                // 源语言选择（通过设置页面）
                showSettings = true
            }

            // 交换按钮
            Button {
                viewModel.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(coral)
            }

            .accessibilityLabel("livetranslate.swap".localized)

            // 目标语言
            languageButton(
                language: viewModel.targetLanguage,
                label: "livetranslate.target".localized
            ) {
                showSettings = true
            }
        }
        .padding(8)
        .modifier(TranslationGlass(reduceTransparency: reduceTransparency))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func languageButton(language: TranslateLanguage, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Text(language.flag)
                        .font(.title2)
                    Text(language.displayName)
                        .font(AppTypography.body)
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)

        }
    }

    // MARK: - Translation Area

    private var translationArea: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if viewModel.currentSessionRecords.isEmpty && viewModel.activeTurns.isEmpty {
                            Text("livetranslate.placeholder".localized)
                                .font(AppTypography.body)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 48)
                        }

                        ForEach(viewModel.activeTurns) { turn in
                            translationCard(
                                id: turn.id,
                                original: turn.originalText,
                                translated: turn.translatedText,
                                source: turn.sourceLanguage,
                                target: turn.targetLanguage,
                                timestamp: turn.timestamp,
                                status: turn.status
                            )
                        }

                        Color.clear.frame(height: 16).id("translation-bottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .contentMargins(.top, languageBarHeight, for: .scrollContent)
                .contentMargins(.top, languageBarHeight, for: .scrollIndicators)
                .simultaneousGesture(DragGesture().onChanged { _ in
                    shouldAutoScroll = false
                })
                .onChange(of: viewModel.currentSessionRecords.count) { _, _ in
                    scrollToLatestIfNeeded(proxy)
                }
                .onChange(of: viewModel.activeTurns) { _, _ in
                    scrollToLatestIfNeeded(proxy)
                }

                if !shouldAutoScroll {
                    Button {
                        shouldAutoScroll = true
                        proxy.scrollTo("translation-bottom", anchor: .bottom)
                    } label: {
                        Label("livetranslate.latest".localized, systemImage: "arrow.down")
                            .font(AppTypography.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .modifier(TranslationGlass(reduceTransparency: reduceTransparency))
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                }
            }

            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("translation-bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func translationCard(
        id: UUID,
        original: String,
        translated: String,
        source: TranslateLanguage,
        target: TranslateLanguage,
        timestamp: Date,
        status: TranslationTurnStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(source.flag) → \(target.flag)")
                Spacer()
                Text(status == .completed ? timestamp.formatted(date: .omitted, time: .shortened) : status.label)
            }
            .font(AppTypography.caption)
            .foregroundColor(.secondary)

            if !original.isEmpty {
                Text(original)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            if !translated.isEmpty {
                Text(translated)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .lineSpacing(5)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(coral.opacity(status == .completed ? 0.35 : 0.8))
                .frame(width: 3).padding(.vertical, 22)
        }
        .textSelection(.enabled)
        .id(id)
    }

    @State private var lastAutoScroll = Date.distantPast

    private func scrollToLatestIfNeeded(_ proxy: ScrollViewProxy) {
        guard shouldAutoScroll, Date().timeIntervalSince(lastAutoScroll) >= 0.15 else { return }
        lastAutoScroll = Date()
        proxy.scrollTo("translation-bottom", anchor: .bottom)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 10) {
            connectionIndicator
            // 录音状态提示
            if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("livetranslate.recording".localized)
                        .font(AppTypography.caption)
                        .foregroundColor(.primary)
                }
            }

            if viewModel.isFinalizing {
                Label("livetranslate.finalizing".localized, systemImage: "hourglass")
                    .font(AppTypography.caption)
                    .foregroundColor(.orange)
            }

            if case .playing = viewModel.playbackState {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("livetranslate.playing".localized)
                    if viewModel.pendingPlaybackCount > 0 {
                        Text(String(format: "livetranslate.pending".localized, viewModel.pendingPlaybackCount))
                    }
                }
                .font(AppTypography.caption)
                .foregroundColor(.green)
            }

            // 录音按钮
            Button {
                viewModel.toggleRecording()
            } label: {
                Label(viewModel.isFinalizing ? "livetranslate.finalizing".localized :
                      (viewModel.isRecording ? "livetranslate.stopAction".localized : "livetranslate.startAction".localized),
                      systemImage: viewModel.isFinalizing ? "hourglass" : (viewModel.isRecording ? "stop.fill" : "mic.fill"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(coral, in: Capsule())
            }

            .disabled(!viewModel.isConnected || viewModel.isFinalizing)
            .opacity(viewModel.isConnected && !viewModel.isFinalizing ? 1.0 : 0.5)
        }
        .padding(14)
        .modifier(TranslationGlass(reduceTransparency: reduceTransparency))
        .padding(.bottom, 8)
    }

}

private struct TranslationGlass: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
        } else {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        }
    }
}
