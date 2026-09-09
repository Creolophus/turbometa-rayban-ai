/*
 * Live Translate ViewModel
 * 实时翻译状态管理
 */

import Foundation
import SwiftUI
import UIKit

@MainActor
class LiveTranslateViewModel: ObservableObject {

    private static let translateVoiceDefaultsKey = "translate_voice"
    private static let translateVoiceMigrationKey = "translate_voice_migration_v2"
    private static let legacyTranslateVoiceRawValues: Set<String> = [
        "Cherry", "Nofish", "Jada", "Dylan", "Sunny", "Peter", "Kiki", "Eric"
    ]

    // MARK: - Connection State
    @Published var isConnected = false
    @Published var isRecording = false

    // MARK: - Translation State
    @Published var currentTranslation = ""       // 当前翻译结果
    @Published var currentOriginal = ""          // 当前原文（暂不支持，保留字段）
    @Published var streamingTranslation = ""     // 流式翻译片段
    /// Records belonging to the currently active/most recently stopped
    /// recording session. Historical sessions stay in Records and are not
    /// rendered on the live workspace.
    @Published var currentSessionRecords: [TranslateRecord] = []
    @Published var translationHistory: [TranslateRecord] = []
    @Published private(set) var historyRecordCount = 0
    /// Display-reduced provisional turns. The view intentionally does not
    /// render raw coordinator snapshots because one speech turn can produce
    /// several interim ASR packets before the authoritative item link arrives.
    @Published var activeTurns: [TranslationDisplayTurn] = []
    @Published var playbackState: TranslationPlaybackState = .idle
    @Published var pendingPlaybackCount = 0
    @Published var isFinalizing = false

    // MARK: - Error State
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Settings (持久化)
    @Published var sourceLanguage: TranslateLanguage {
        didSet {
            UserDefaults.standard.set(sourceLanguage.rawValue, forKey: "translate_source_language")
            updateServiceSettings()
        }
    }

    @Published var targetLanguage: TranslateLanguage {
        didSet {
            UserDefaults.standard.set(targetLanguage.rawValue, forKey: "translate_target_language")
            // Cantonese and Greek are text-only targets in Qwen3.5. Keep the
            // selected target intact, but never leave an invalid audio mode
            // enabled after restoring or changing the language.
            if audioOutputEnabled && !targetLanguage.supportsAudioOutput {
                audioOutputEnabled = false
                return
            }
            updateServiceSettings()
        }
    }

    @Published var selectedVoice: TranslateVoice {
        didSet {
            UserDefaults.standard.set(selectedVoice.rawValue, forKey: "translate_voice")
            updateServiceSettings()
        }
    }

    @Published var audioOutputEnabled: Bool {
        didSet {
            if audioOutputEnabled && !targetLanguage.supportsAudioOutput {
                audioOutputEnabled = false
                return
            }
            UserDefaults.standard.set(audioOutputEnabled, forKey: "translate_audio_enabled")
            updateServiceSettings()
        }
    }

    /// 使用 iPhone 麦克风（而非眼镜麦克风）
    /// 眼镜麦克风适合翻译自己说的话，iPhone 麦克风适合翻译对方说的话
    @Published var usePhoneMic: Bool {
        didSet {
            UserDefaults.standard.set(usePhoneMic, forKey: "translate_use_phone_mic")
        }
    }

    // MARK: - Private
    private var translateService: LiveTranslateService?
    private let historyStorage: LiveTranslateHistoryStorage
    private var turnCoordinator: TranslationTurnCoordinator
    private var currentSessionID: UUID?
    private var persistedRecordSignatures: [UUID: String] = [:]
    private var finalizationTask: Task<Void, Never>?
    private var settingsReconnectTask: Task<Void, Never>?
    private var recoveryReconnectTask: Task<Void, Never>?
    private var shouldMaintainConnection = false
    private var hasFinalizedCurrentSession = false
    private var turnWatchdog: Task<Void, Never>?
    private var pendingDisplayTurns: [TranslationDisplayTurn] = []
    private var displayFlushTask: Task<Void, Never>?

    // MARK: - Init

    init(historyStorage: LiveTranslateHistoryStorage = .shared) {
        self.historyStorage = historyStorage
        // 从 UserDefaults 加载设置
        let savedSource = UserDefaults.standard.string(forKey: "translate_source_language") ?? "en"
        self.sourceLanguage = TranslateLanguage(rawValue: savedSource) ?? .en

        let savedTarget = UserDefaults.standard.string(forKey: "translate_target_language") ?? "zh"
        let targetLanguageValue = TranslateLanguage(rawValue: savedTarget) ?? .zh
        self.targetLanguage = targetLanguageValue

        self.selectedVoice = Self.loadTranslateVoice()

        let savedAudioOutputEnabled = UserDefaults.standard.object(forKey: "translate_audio_enabled") as? Bool ?? true
        let normalizedAudioOutputEnabled = Self.normalizedAudioOutputEnabled(
            audioEnabled: savedAudioOutputEnabled,
            targetLanguage: targetLanguageValue
        )
        self.audioOutputEnabled = normalizedAudioOutputEnabled
        if savedAudioOutputEnabled != normalizedAudioOutputEnabled {
            UserDefaults.standard.set(normalizedAudioOutputEnabled, forKey: "translate_audio_enabled")
        }
        self.usePhoneMic = UserDefaults.standard.object(forKey: "translate_use_phone_mic") as? Bool ?? false
        // Use the local values here because `self` is not fully initialized
        // until every stored property has been assigned.
        self.turnCoordinator = TranslationTurnCoordinator(
            sourceLanguage: TranslateLanguage(rawValue: savedSource) ?? .en,
            targetLanguage: TranslateLanguage(rawValue: savedTarget) ?? .zh
        )
        self.translationHistory = historyStorage.loadAll()
        self.historyRecordCount = translationHistory.count
        self.currentSessionID = nil
        self.persistedRecordSignatures = Dictionary(uniqueKeysWithValues: translationHistory.map {
            ($0.id, Self.signature(for: $0))
        })
    }

    /// Loads the Qwen3.5 voice and performs the one-time migration from the
    /// voices used by the previous Qwen3 realtime endpoint. Legacy values are
    /// never sent to the server; they are replaced with the official default
    /// Tina and persisted before the service can be configured.
    private static func loadTranslateVoice(
        defaults: UserDefaults = .standard
    ) -> TranslateVoice {
        let savedRawValue = defaults.string(forKey: translateVoiceDefaultsKey)
        let migrationCompleted = defaults.bool(forKey: translateVoiceMigrationKey)

        let voice: TranslateVoice
        if migrationCompleted {
            voice = TranslateVoice(rawValue: savedRawValue ?? "") ?? .tina
        } else {
            let savedVoice = savedRawValue.flatMap(TranslateVoice.init(rawValue:))
            if let savedVoice,
               !legacyTranslateVoiceRawValues.contains(savedRawValue ?? "") {
                voice = savedVoice
            } else {
                voice = .tina
            }
            defaults.set(voice.rawValue, forKey: translateVoiceDefaultsKey)
            defaults.set(true, forKey: translateVoiceMigrationKey)
        }

        // If a value was removed or corrupted after migration, repair it so
        // the next session still sends a legal voice.
        if savedRawValue != voice.rawValue {
            defaults.set(voice.rawValue, forKey: translateVoiceDefaultsKey)
        }
        return voice
    }

    /// Qwen3.5 only emits audio for the official audio-capable target
    /// languages. This keeps a previously enabled audio preference from
    /// producing an invalid session after a language-model upgrade.
    static func normalizedAudioOutputEnabled(
        audioEnabled: Bool,
        targetLanguage: TranslateLanguage
    ) -> Bool {
        audioEnabled && targetLanguage.supportsAudioOutput
    }

    // MARK: - Connection

    func connect() {
        shouldMaintainConnection = true
        guard translateService == nil else { return }
        connectFreshService()
    }

    private func connectFreshService() {
        // Translation is Alibaba-only and must keep working regardless of the
        // provider selected for general Live AI chat.
        let apiKey = APIProviderManager.staticAlibabaAPIKey
        guard !apiKey.isEmpty else {
            errorMessage = "livetranslate.error.noApiKey".localized
            showError = true
            return
        }

        isConnected = false
        let service = LiveTranslateService(apiKey: apiKey)
        translateService = service
        setupCallbacks()

        service.updateSettings(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            voice: selectedVoice,
            audioEnabled: audioOutputEnabled
        )

        service.connect()
    }

    func disconnect() {
        shouldMaintainConnection = false
        settingsReconnectTask?.cancel()
        settingsReconnectTask = nil
        recoveryReconnectTask?.cancel()
        recoveryReconnectTask = nil
        if isRecording { stopRecording(); return }
        if isFinalizing { return } // The finalization task retains its owner until persistence completes.
        turnWatchdog?.cancel()
        translateService?.disconnect()
        translateService = nil
        isConnected = false
        isRecording = false
        isFinalizing = false
        playbackState = .idle
        pendingPlaybackCount = 0
    }

    // MARK: - Recording

    func toggleRecording() {
        guard !isFinalizing else { return }
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard isConnected, !isFinalizing else { return }
        guard let service = translateService,
              service.startRecording(usePhoneMic: usePhoneMic) else {
            isRecording = false
            return
        }

        // A business session starts only after the audio engine has actually
        // started. Reconnecting the WebSocket never reaches this branch and
        // therefore cannot create or clear a session.
        let sessionID = UUID()
        currentSessionID = sessionID
        hasFinalizedCurrentSession = false
        turnCoordinator = TranslationTurnCoordinator(
            sessionID: sessionID,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        currentSessionRecords.removeAll()
        displayFlushTask?.cancel()
        displayFlushTask = nil
        pendingDisplayTurns = []
        activeTurns.removeAll()
        currentTranslation = ""
        currentOriginal = ""
        streamingTranslation = ""
        isRecording = true
        turnWatchdog?.cancel()
        turnWatchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.isRecording else { return }
                let update = self.turnCoordinator.tick()
                self.apply(update)
            }
        }
    }

    func stopRecording() {
        guard isRecording, !isFinalizing, let service = translateService else { return }
        isRecording = false
        isFinalizing = true
        service.stopRecording()

        finalizationTask = Task { @MainActor [self, service] in
            await service.finishSession()
            guard !Task.isCancelled else { return }
            guard self.translateService === service else { return }
            self.finalizeCurrentSession()
            service.disconnect()
            self.translateService = nil
            self.isConnected = false
            self.isFinalizing = false
            self.finalizationTask = nil
            if self.shouldMaintainConnection {
                self.connectFreshService()
            }
        }
    }

    // MARK: - Language Swap

    func swapLanguages() {
        // Text-only languages are valid targets when audio output is off, so
        // swapping is gated by model support rather than audio capability.
        guard TranslateLanguage.targetLanguages.contains(sourceLanguage),
              TranslateLanguage.targetLanguages.contains(targetLanguage) else {
            errorMessage = "livetranslate.error.cannotSwap".localized
            showError = true
            return
        }

        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp

        // 清空当前翻译
        currentTranslation = ""
        streamingTranslation = ""
    }

    // MARK: - Private Methods

    private func setupCallbacks() {
        guard let service = translateService else { return }

        service.onConnected = { [weak self, weak service] in
            DispatchQueue.main.async {
                guard let self, let service, self.translateService === service else { return }
                self.isConnected = true
                print("✅ [TranslateVM] 已连接")
            }
        }

        service.onSourceTranscript = { [weak self, weak service] event in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveSource(event)
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onTranslation = { [weak self, weak service] event in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveTranslation(event)
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onResponseItem = { [weak self, weak service] responseID, responseItemID in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveResponseItem(
                    responseID: responseID,
                    itemID: responseItemID
                )
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onTurnLink = { [weak self, weak service] sourceItemID, responseItemID in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveLink(
                    sourceItemID: sourceItemID,
                    responseItemID: responseItemID
                )
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onPlaybackStateChanged = { [weak self, weak service] state, pendingCount in
            Task { @MainActor in
                guard let self, let service, self.translateService === service else { return }
                self.playbackState = state
                self.pendingPlaybackCount = pendingCount
            }
        }

        service.onSpeechStarted = { [weak self, weak service] itemID in
            Task { @MainActor in
                guard let self, let service, self.translateService === service else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveSpeechStarted(itemID: itemID)
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onSpeechStopped = { [weak self, weak service] itemID in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveSpeechStopped(itemID: itemID)
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onResponseStarted = { [weak self, weak service] responseID in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveResponseStarted(responseID: responseID)
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onSourceFailed = { [weak self, weak service] itemID in
            Task { @MainActor in
                guard let self, let service, self.translateService === service else { return }
                let update = self.turnCoordinator.receiveSourceFailure(itemID: itemID)
                self.apply(update)
            }
        }

        service.onResponseFinished = { [weak self, weak service] responseID, status in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                var coordinator = self.turnCoordinator
                let update = coordinator.receiveResponseFinished(responseID: responseID, status: status)
                self.turnCoordinator = coordinator
                self.apply(update)
            }
        }

        service.onSessionFinished = { [weak self, weak service] in
            Task { @MainActor in
                guard let self, let service,
                      self.translateService === service,
                      self.currentSessionID != nil else { return }
                self.finalizeCurrentSession()
            }
        }

        service.onDisconnected = { [weak self, weak service] expected, reason in
            Task { @MainActor in
                guard let self, let service, self.translateService === service else { return }
                self.isConnected = false

                // During normal finalization, finishSession owns cleanup and
                // reconnect. Do not race it with a second connection attempt.
                if self.isFinalizing { return }

                self.isRecording = false
                if self.currentSessionID != nil {
                    self.finalizeCurrentSession()
                }
                self.translateService = nil

                guard self.shouldMaintainConnection else { return }
                if !expected, let reason, !reason.isEmpty {
                    print("⚠️ [TranslateVM] 连接异常，准备恢复: \(reason)")
                }
                self.scheduleRecoveryReconnect()
            }
        }

        service.onError = { [weak self, weak service] error in
            DispatchQueue.main.async {
                guard let self, let service, self.translateService === service else { return }
                self.errorMessage = error
                self.showError = true
            }
        }
    }

    private func updateServiceSettings() {
        // An Alibaba LiveTranslate session is immutable after it starts. End
        // the active business session; the latest preferences are applied to
        // the fresh socket created by the finalization path.
        if isRecording {
            stopRecording()
            return
        }
        guard !isFinalizing else { return }

        turnCoordinator.updateLanguages(source: sourceLanguage, target: targetLanguage)
        guard shouldMaintainConnection else { return }

        // Source/target swapping changes two @Published properties. Coalesce
        // them so the server sees one new session with the final pair.
        settingsReconnectTask?.cancel()
        settingsReconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled,
                  self.shouldMaintainConnection,
                  !self.isRecording,
                  !self.isFinalizing else { return }
            self.settingsReconnectTask = nil
            let oldService = self.translateService
            self.translateService = nil
            self.isConnected = false
            oldService?.disconnect()
            self.connectFreshService()
        }
    }

    private func scheduleRecoveryReconnect() {
        recoveryReconnectTask?.cancel()
        recoveryReconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled,
                  self.shouldMaintainConnection,
                  self.translateService == nil else { return }
            self.recoveryReconnectTask = nil
            self.connectFreshService()
        }
    }

    // MARK: - Turn Handling

    /// Preserve final and partial rows after graceful completion or failure.
    private func finalizeCurrentSession() {
        guard currentSessionID != nil, !hasFinalizedCurrentSession else { return }
        hasFinalizedCurrentSession = true
        var coordinator = turnCoordinator
        let update = coordinator.finalize()
        turnCoordinator = coordinator
        apply(update)
        turnWatchdog?.cancel()
        currentOriginal = ""
        streamingTranslation = ""
    }

    private func apply(_ update: TranslationCoordinatorUpdate) {
        guard currentSessionID != nil else {
            activeTurns = []
            return
        }
        // One stable timeline; completion changes the row state, not its position.
        let turns = update.turns.map { snapshot in
            TranslationDisplayTurn(
                id: snapshot.id, sourceItemID: snapshot.sourceItemID, responseID: snapshot.responseID,
                originalText: snapshot.originalText, translatedText: snapshot.translatedText,
                isSourceFinal: snapshot.isSourceFinal, isTranslationFinal: snapshot.isTranslationFinal,
                status: snapshot.status, timestamp: snapshot.timestamp,
                sourceLanguage: turnCoordinator.sourceLanguage, targetLanguage: turnCoordinator.targetLanguage
            )
        }
        pendingDisplayTurns = turns
        if displayFlushTask == nil {
            displayFlushTask = Task { @MainActor [self] in
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                if activeTurns != pendingDisplayTurns { activeTurns = pendingDisplayTurns }
                displayFlushTask = nil
            }
        }
        if let latest = turns.last {
            currentOriginal = latest.originalText
            streamingTranslation = latest.translatedText
        } else {
            currentOriginal = ""
            streamingTranslation = ""
        }

        let changed = update.recordsToUpsert.filter { persistedRecordSignatures[$0.id] != Self.signature(for: $0) }
        guard !changed.isEmpty else { return }
        for record in changed { persistedRecordSignatures[record.id] = Self.signature(for: record) }
        let session = currentSessionID
        historyStorage.enqueue(changed) { [self] records in
            guard let records else {
                errorMessage = "livetranslate.saveFailed".localized
                showError = true
                for record in changed where persistedRecordSignatures[record.id] == Self.signature(for: record) {
                    persistedRecordSignatures.removeValue(forKey: record.id)
                }
                return
            }
            translationHistory = records
            historyRecordCount = records.count
            if currentSessionID == session {
                currentSessionRecords = records.filter { $0.sessionID == session }
                currentTranslation = changed.last?.translatedText ?? currentTranslation
            }
        }
    }

    private static func signature(for record: TranslateRecord) -> String {
        [record.sourceItemID ?? "", record.responseID ?? "", record.originalText, record.translatedText, record.status?.rawValue ?? "completed"]
            .joined(separator: "\u{1F}")
    }

    func retrySavingRecords() {
        let update = turnCoordinator.tick()
        apply(update)
    }

    // MARK: - Clear

    func clearTranslation() {
        currentTranslation = ""
        streamingTranslation = ""
        currentOriginal = ""
    }

    func clearHistory() {
        historyStorage.deleteAll()
        translationHistory.removeAll()
        currentSessionRecords.removeAll()
        historyRecordCount = 0
        persistedRecordSignatures.removeAll()
    }
}
