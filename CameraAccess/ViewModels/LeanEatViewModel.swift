import Foundation
import SwiftUI
import Combine

@MainActor
final class LeanEatViewModel: ObservableObject {
    enum Phase: Equatable { case ready, starting, capturing, loadingPhoto, analyzing, result, failed, closed }
    enum SaveState { case none, saving, saved, failed }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var photo: UIImage?
    @Published private(set) var nutrition: FoodNutritionResponse?
    @Published private(set) var errorMessage: String?
    @Published private(set) var saveState: SaveState = .none

    let camera: StreamSessionViewModel?
    private let parentCamera: StreamSessionViewModel?
    private let storage: LeanEatStorage
    private let analyze: (Data) async throws -> FoodNutritionResponse
    private var inputPhoto: UIImage?
    private var retryLoader: (() async throws -> Data)?
    private var jpeg: Data?
    private var source: LeanEatRecord.Source = .glasses
    private var recordID = UUID()
    private var recordDate = Date()
    private var generation = UUID()
    private var operation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var cameraCleanup: Task<Void, Never>?
    private var didEnter = false
    private var suspended = false
    private var subscriptions = Set<AnyCancellable>()
    private let analysisTimeout: Double

    init(parentCamera: StreamSessionViewModel? = nil, photo: UIImage? = nil,
         storage: LeanEatStorage = .shared,
         analysisTimeout: Double = 60,
         analyze: ((Data) async throws -> FoodNutritionResponse)? = nil) {
        self.parentCamera = parentCamera
        self.camera = parentCamera?.makePhotoSession()
        self.inputPhoto = photo
        self.storage = storage
        self.analysisTimeout = analysisTimeout
        self.analyze = analyze ?? { data in
            let configuration = try LeanEatConfiguration.current()
            return try await LeanEatService(configuration: configuration).analyzeFood(data)
        }
        if let camera {
            camera.$streamingStatus.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
            camera.$hasReceivedFirstFrame.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
            camera.$hasActiveDevice.dropFirst().removeDuplicates().sink { [weak self] connected in
                self?.objectWillChange.send()
                if !connected { self?.deviceDisconnected() }
            }.store(in: &subscriptions)
        }
    }

    var hasUnsavedResult: Bool { nutrition != nil && saveState != .saved }
    var canCapture: Bool { phase == .ready && camera?.streamingStatus == .streaming && camera?.hasReceivedFirstFrame == true }

    func enter() {
        guard !didEnter else { return }
        didEnter = true
        if let inputPhoto {
            self.inputPhoto = nil
            selectPhoto(source: .glasses) {
                try await Task.detached(priority: .userInitiated) {
                    guard let data = inputPhoto.jpegData(compressionQuality: 0.9) else { throw LeanEatError.image }
                    return data
                }.value
            }
        } else { startCamera() }
    }

    func startCamera() {
        guard phase != .closed, let camera else { return }
        let token = replaceOperation()
        errorMessage = nil
        camera.refreshConnectedDevice()
        guard camera.hasActiveDevice else { phase = .ready; return }
        phase = .starting
        operation = Task {
            await cameraCleanup?.value
            guard current(token) else { return }
            await parentCamera?.stopSession()
            guard current(token) else { return }
            armTimeout(seconds: 15, token: token)
            camera.dismissError()
            await camera.handleStartStreaming()
            guard current(token) else { return }
            while !camera.hasReceivedFirstFrame && !camera.showError {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard current(token) else { return }
            }
            timeout?.cancel()
            guard !camera.showError else {
                fail(LeanEatError.camera, token: token)
                return
            }
            phase = .ready
        }
    }

    func capture() {
        guard canCapture, let camera else { return }
        let token = replaceOperation()
        phase = .capturing
        operation = Task {
            armTimeout(seconds: 15, token: token)
            do {
                let data = try await camera.capturePhotoData()
                guard current(token) else { return }
                timeout?.cancel()
                await prepareAndAnalyze(data, source: .glasses, token: token)
            } catch { fail(error, token: token) }
        }
    }

    func selectPhoto(source: LeanEatRecord.Source = .library, loader: @escaping () async throws -> Data) {
        guard phase != .closed, !hasUnsavedResult else { return }
        retryLoader = loader
        self.source = source
        let token = replaceOperation()
        phase = .loadingPhoto
        errorMessage = nil
        photo = nil
        jpeg = nil
        nutrition = nil
        saveState = .none
        stopCamera()
        operation = Task {
            do {
                let data = try await loader()
                guard current(token) else { return }
                await prepareAndAnalyze(data, source: source, token: token)
            } catch { fail(error, token: token) }
        }
    }

    private func prepareAndAnalyze(_ data: Data, source: LeanEatRecord.Source, token: UUID) async {
        stopCamera()
        phase = .loadingPhoto
        do {
            let prepared = try await LeanEatImageProcessor.prepare(data)
            guard current(token) else { return }
            jpeg = prepared
            photo = UIImage(data: prepared)
            retryLoader = nil
            self.source = source
            recordID = UUID()
            recordDate = Date()
            nutrition = nil
            saveState = .none
            await runAnalysis(prepared, token: token)
        } catch { fail(error, token: token) }
    }

    private func runAnalysis(_ data: Data, token: UUID) async {
        phase = .analyzing
        errorMessage = nil
        armTimeout(seconds: analysisTimeout, token: token)
        do {
            let result = try await analyze(data)
            guard current(token) else { return }
            timeout?.cancel()
            try result.validate()
            guard !result.foods.isEmpty else {
                phase = .failed
                errorMessage = "leaneat.noFood".localized
                return
            }
            nutrition = result
            phase = .result
            retrySaving()
        } catch { fail(error, token: token) }
    }

    func retry() {
        guard phase == .failed else { return }
        guard let jpeg else {
            if let retryLoader { selectPhoto(source: source, loader: retryLoader) }
            else { startCamera() }
            return
        }
        let token = replaceOperation()
        operation = Task { await runAnalysis(jpeg, token: token) }
    }

    func retrySaving() {
        guard let nutrition, let jpeg, saveState != .saving, saveState != .saved, phase != .closed else { return }
        let record = LeanEatRecord(id: recordID, timestamp: recordDate, source: source,
                                   imagePath: recordID.uuidString + "/photo.jpg", nutrition: nutrition)
        saveState = .saving
        saving = Task {
            do {
                try await storage.save(record, jpeg: jpeg)
                saveState = .saved
            } catch { saveState = .failed }
        }
    }

    func waitForSave() async { await saving?.value }

    /// Called only after the view has handled an unsaved-result confirmation.
    func reset() {
        guard phase != .closed else { return }
        _ = replaceOperation()
        photo = nil
        jpeg = nil
        retryLoader = nil
        nutrition = nil
        errorMessage = nil
        saveState = .none
        phase = .ready
        startCamera()
    }

    func sceneChanged(_ scene: ScenePhase) {
        if scene == .background {
            if [.ready, .starting, .capturing].contains(phase) {
                _ = replaceOperation()
                phase = .ready
                suspended = true
                stopCamera()
            }
        } else if scene == .active, suspended {
            suspended = false
            startCamera()
        }
    }

    func deviceDisconnected() {
        guard [.ready, .starting, .capturing].contains(phase) else { return }
        _ = replaceOperation()
        stopCamera()
        phase = .ready
        errorMessage = "leaneat.cameraError".localized
    }

    func close() {
        guard phase != .closed else { return }
        _ = replaceOperation()
        phase = .closed
        photo = nil
        inputPhoto = nil
        retryLoader = nil
        jpeg = nil
        nutrition = nil
        if let camera {
            let previous = cameraCleanup
            cameraCleanup = Task {
                await previous?.value
                await camera.cleanup()
            }
        }
    }

    private func stopCamera() {
        guard let camera else { return }
        camera.cancelPhotoCapture()
        let previous = cameraCleanup
        cameraCleanup = Task {
            await previous?.value
            await camera.stopSession()
        }
    }

    private func replaceOperation() -> UUID {
        generation = UUID()
        operation?.cancel()
        timeout?.cancel()
        return generation
    }

    private func current(_ token: UUID) -> Bool {
        token == generation && phase != .closed && !Task.isCancelled
    }

    private func armTimeout(seconds: Double, token: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, current(token) else { return }
            _ = replaceOperation()
            phase = .failed
            errorMessage = LeanEatError.timeout.localizedDescription
            stopCamera()
        }
    }

    private func fail(_ error: Error, token: UUID) {
        guard current(token) else { return }
        timeout?.cancel()
        errorMessage = (error as? URLError)?.code == .timedOut ? LeanEatError.timeout.localizedDescription : error.localizedDescription
        phase = .failed
        stopCamera()
    }
}
