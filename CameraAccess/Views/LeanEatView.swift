import SwiftUI
import PhotosUI

struct LeanEatView: View {
    @StateObject private var model: LeanEatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection: PhotosPickerItem?
    @State private var confirmUnsaved = false
    @State private var pendingReset = false

    init(streamViewModel: StreamSessionViewModel) {
        _model = StateObject(wrappedValue: LeanEatViewModel(parentCamera: streamViewModel))
    }

    init(model: LeanEatViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    /// Legacy photo preview enters the same analysis/result flow, without another camera.
    init(photo: UIImage) {
        _model = StateObject(wrappedValue: LeanEatViewModel(photo: photo))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LeanEat").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { leave(reset: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }
                .modifier(LeanEatGlass())
                .accessibilityLabel("close".localized)
                .accessibilityIdentifier("leaneat.close")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 16) {
                    if let photo = model.photo {
                        Image(uiImage: photo).resizable().scaledToFit()
                            .frame(maxHeight: 240).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .accessibilityLabel("leaneat.foodPhoto".localized)
                    } else if let camera = model.camera {
                        LeanEatCameraPreview(camera: camera)
                    } else if model.phase == .ready {
                        ContentUnavailableView("leaneat.library".localized, systemImage: "photo",
                            description: Text("leaneat.noGlassesHint".localized))
                    }
                    switch model.phase {
                    case .starting, .capturing, .loadingPhoto, .analyzing:
                        VStack(spacing: 14) {
                            ProgressView().tint(HomeStyle.coral)
                            Text(progressLabel).font(.headline)
                            if model.phase == .analyzing {
                                Text("leaneat.analyzingHint".localized).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                        .accessibilityElement(children: .combine)
                    case .failed:
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
                            Text("leaneat.error.title".localized).font(.headline)
                            Text(model.errorMessage ?? "").font(.body).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(20).background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 24))
                    case .result:
                        if let nutrition = model.nutrition { LeanEatNutritionContent(nutrition: nutrition) }
                        if model.saveState == .failed {
                            Label("leaneat.saveFailed".localized, systemImage: "exclamationmark.icloud")
                                .font(.subheadline).foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 20))
                        }
                    default:
                        if let error = model.errorMessage {
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls.padding(14).modifier(LeanEatGlass())
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
        }
        .background(HomeStyle.background.ignoresSafeArea())
        .tint(HomeStyle.coral)
        .interactiveDismissDisabled(model.hasUnsavedResult)
        .task { model.enter() }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, scene in model.sceneChanged(scene) }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            model.selectPhoto {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw LeanEatError.image }
                return data
            }
            selection = nil
        }
        .alert("leaneat.unsavedTitle".localized, isPresented: $confirmUnsaved) {
            Button("leaneat.retrySave".localized) { model.retrySaving() }
            Button("leaneat.discard".localized, role: .destructive) { finishLeave() }
            Button("common.cancel".localized, role: .cancel) {}
        } message: { Text("leaneat.unsavedMessage".localized) }
    }

    private var progressLabel: String {
        switch model.phase {
        case .starting: return "leaneat.connecting".localized
        case .capturing: return "leaneat.capturing".localized
        case .loadingPhoto: return "leaneat.loadingPhoto".localized
        default: return "leaneat.analyzing".localized
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 10) {
            if model.phase == .result {
                if model.saveState == .saving {
                    Label("leaneat.saving".localized, systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                } else if model.saveState == .saved {
                    Label("leaneat.saved".localized, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                if model.saveState == .failed {
                    action("leaneat.retrySave", icon: "arrow.clockwise", primary: true) { model.retrySaving() }
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    action("leaneat.another", icon: "camera", primary: false) { leave(reset: true) }
                    action("common.done", icon: "checkmark", primary: true) { leave(reset: false) }
                }
            } else if model.phase == .ready || model.phase == .failed {
                if model.phase == .failed {
                    action("leaneat.retry", icon: "arrow.clockwise", primary: true) { model.retry() }
                    if model.photo != nil {
                        action("leaneat.reselect", icon: "camera", primary: false) { model.reset() }
                    }
                } else {
                    action("leaneat.capture", icon: "camera.fill", primary: true) { model.capture() }
                        .disabled(!model.canCapture).opacity(model.canCapture ? 1 : 0.45)
                    if model.camera?.hasReceivedFirstFrame != true, model.camera != nil {
                        action("leaneat.reconnect", icon: "arrow.clockwise", primary: false) { model.startCamera() }
                    }
                }
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    Label("leaneat.library".localized, systemImage: "photo")
                        .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("leaneat.library")
            } else {
                Text("leaneat.canClose".localized).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func action(_ key: String, icon: String, primary: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Group {
                if typeSize.isAccessibilitySize { Text(key.localized) }
                else { Label(key.localized, systemImage: icon) }
            }.font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 12)
                .foregroundStyle(primary ? .white : HomeStyle.coral)
                .background(primary ? HomeStyle.coral : HomeStyle.coral.opacity(0.09), in: Capsule())
        }
        .accessibilityIdentifier(key)
    }

    private func leave(reset: Bool) {
        pendingReset = reset
        Task {
            await model.waitForSave()
            if model.hasUnsavedResult { confirmUnsaved = true }
            else { finishLeave() }
        }
    }

    private func finishLeave() {
        if pendingReset { model.reset() }
        else { model.close(); dismiss() }
    }
}

private struct LeanEatCameraPreview: View {
    @ObservedObject var camera: StreamSessionViewModel
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "eyeglasses")
                Text(camera.connectedDevice.displayName).lineLimit(1)
                Spacer()
                Text(camera.connectedDevice.statusText).font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline).padding(14).background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 18))
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(HomeStyle.card)
                if let image = camera.currentVideoFrame {
                    GeometryReader { geometry in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "eyeglasses").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("leaneat.noGlasses".localized).font(.headline)
                        Text("leaneat.noGlassesHint".localized).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center).padding(24)
                }
            }
            .frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 24))
            Text("leaneat.frameHint".localized).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct LeanEatNutritionContent: View {
    let nutrition: FoodNutritionResponse
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 16) {
            card {
                Text("leaneat.estimatedCalories".localized).font(.subheadline).foregroundStyle(.secondary)
                Text("\(nutrition.totalCalories) kcal").font(.title.bold())
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 14))
                layout {
                    nutrient("leaneat.protein", value: nutrition.totalProtein)
                    nutrient("leaneat.fat", value: nutrition.totalFat)
                    nutrient("leaneat.carbs", value: nutrition.totalCarbs)
                }
            }
            card {
                HStack {
                    Text("leaneat.healthscore".localized).font(.headline)
                    Spacer()
                    Text("\(nutrition.healthScore)").font(.headline)
                }
                ProgressView(value: Double(nutrition.healthScore), total: 100).tint(.green)
                    .accessibilityLabel("leaneat.healthscore".localized).accessibilityValue("\(nutrition.healthScore)/100")
            }
            card {
                Text("leaneat.foods".localized).font(.headline)
                ForEach(nutrition.foods) { food in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(food.name).font(.body.weight(.medium))
                            Spacer()
                            Text("\(food.calories) kcal").font(.subheadline)
                        }
                        Text(food.portion).font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "leaneat.macros".localized, food.protein, food.fat, food.carbs))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            if !nutrition.suggestions.isEmpty {
                card {
                    Text("leaneat.suggestions".localized).font(.headline)
                    ForEach(Array(nutrition.suggestions.enumerated()), id: \.offset) { _, text in
                        Text(text).font(.body).foregroundStyle(.secondary)
                    }
                }
            }
            Text("leaneat.estimateHint".localized).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func nutrient(_ key: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key.localized).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.1f g", value)).font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct LeanEatRecordDetailView: View {
    let record: LeanEatRecord
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LeanEatStoredPhoto(record: record).frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text(record.timestamp.formatted()).font(.caption).foregroundStyle(.secondary)
                    LeanEatNutritionContent(nutrition: record.nutrition)
                }
                .padding(20)
            }
            .background(HomeStyle.background)
            .navigationTitle("LeanEat").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localized) { dismiss() }
                }
            }
        }
    }
}

struct LeanEatStoredPhoto: View {
    let record: LeanEatRecord
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "leaf").foregroundStyle(.green) }
        }
        .task(id: record.id) {
            let url = LeanEatStorage.shared.imageURL(for: record)
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}

private struct LeanEatGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 28)) }
        else { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28)) }
    }
}
