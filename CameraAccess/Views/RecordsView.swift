import SwiftUI

struct RecordsView: View {
    @StateObject private var model: RecordsLibraryViewModel
    @ObservedObject private var audioLibrary = AudioNoteLibrary.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool
    @State private var detail: RecordEntry?
    @State private var deletionIDs = Set<RecordEntryID>()
    @State private var confirmsDeletion = false
    @State private var filterBarHeight: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(model: RecordsLibraryViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? RecordsLibraryViewModel())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                searchField
                    .padding(.top, 12)
                archive
                    .contentMargins(.top, filterBarHeight + 8, for: .scrollContent)
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: 12)
                            Rectangle()
                        }
                        .ignoresSafeArea(edges: .bottom)
                    }
                    .overlay(alignment: .top) {
                        filters
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterBarHeight = $0 }
                    }
                    .padding(.top, 14)
            }
            .background(HomeStyle.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.isSelecting { selectionBar }
            }
            .sheet(item: $detail, onDismiss: model.reload) { entry in
                detailView(entry)
            }
            .confirmationDialog("records.delete.title".localized, isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("records.delete.confirm".localized, role: .destructive) {
                    model.delete(ids: deletionIDs)
                    deletionIDs.removeAll()
                }
                Button("common.cancel".localized, role: .cancel) { deletionIDs.removeAll() }
            } message: {
                Text(String(format: "records.archive.delete.message".localized, deletionIDs.count))
            }
            .alert("records.archive.delete.failed".localized, isPresented: $model.deletionFailed) {
                Button("common.done".localized, role: .cancel) {}
            }
        }
        .tint(HomeStyle.coral)
        .onAppear(perform: model.reload)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordsLibraryDidChange).receive(on: RunLoop.main)) { _ in model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .liveTranslateHistoryDidChange).receive(on: RunLoop.main)) { _ in model.reload() }
        .onReceive(audioLibrary.$notes) { _ in model.reload() }
    }

    private var header: some View {
        HStack {
            Text("records.title".localized)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if model.isSelecting {
                Button("common.done".localized) { model.endSelection() }
                    .frame(minHeight: 44)
            } else {
                Menu {
                    Button {
                        searchFocused = false
                        model.isSelecting = true
                    } label: {
                        Label("records.select".localized, systemImage: "checkmark.circle")
                    }
                    .disabled(model.visibleEntries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .modifier(RecordsGlassSurface())
                }
                .accessibilityLabel("records.archive.manage".localized)
                .accessibilityIdentifier("records.manage")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("records.archive.search".localized, text: $model.query)
                .font(.body)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("records.search")
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("records.archive.clearSearch".localized)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, model.query.isEmpty ? 14 : 0)
        .frame(minHeight: 44)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5) }
        .padding(.horizontal, 20)
    }

    private var filters: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(RecordsFilter.allCases) { filter in
                        Button {
                            searchFocused = false
                            model.filter = filter
                        } label: {
                            Text(filter.title)
                                .font(.subheadline.weight(model.filter == filter ? .semibold : .regular))
                                .foregroundStyle(model.filter == filter ? HomeStyle.coral : .primary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(model.filter == filter ? HomeStyle.coral.opacity(0.12) : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
                        .accessibilityIdentifier("records.filter.\(filter.rawValue)")
                        .id(filter)
                    }
                }
                .padding(3)
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(Capsule())
            .modifier(RecordsFilterGlassSurface(reduceTransparency: reduceTransparency))
            .onChange(of: model.filter) { _, filter in
                withAnimation(.snappy) { proxy.scrollTo(filter, anchor: .center) }
            }
        }
        .padding(.horizontal, 20)
    }

    private var archive: some View {
        ScrollView {
            if model.filter.isComingSoon {
                ContentUnavailableView {
                    Label(model.filter.title, systemImage: model.filter == .leanEat ? "leaf" : "book.closed")
                } description: {
                    Text("records.comingSoon".localized)
                }
                .padding(.top, 40)
            } else if model.visibleEntries.isEmpty {
                ContentUnavailableView {
                    Label(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? "records.empty".localized : "records.archive.noResults".localized,
                          systemImage: model.query.isEmpty ? "tray" : "magnifyingglass")
                } description: {
                    Text(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "records.archive.emptyHint".localized : "records.archive.searchHint".localized)
                }
                .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.sections()) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            dayHeader(section.date)
                            VStack(spacing: 0) {
                                ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                                    Button {
                                        searchFocused = false
                                        if model.isSelecting { model.toggle(entry.id) }
                                        else { detail = entry }
                                    } label: {
                                        RecordArchiveRow(entry: entry, isSelecting: model.isSelecting,
                                                         isSelected: model.selectedIDs.contains(entry.id))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("records.row.\(entry.id.kind.rawValue).\(entry.id.value)")
                                    .accessibilityAddTraits(model.selectedIDs.contains(entry.id) ? .isSelected : [])
                                    .contextMenu {
                                        if !model.isSelecting {
                                            Button(role: .destructive) { confirmDeletion([entry.id]) } label: {
                                                Label("common.delete".localized, systemImage: "trash")
                                            }
                                        }
                                    }
                                    if index < section.entries.count - 1 {
                                        Divider().padding(.leading, model.isSelecting ? 106 : 82)
                                    }
                                }
                            }
                            .background(HomeStyle.card, in: RoundedRectangle(cornerRadius: 18))
                            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.065), lineWidth: 0.5) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .refreshable { model.reload() }
        .id(model.filter)
    }

    private func dayHeader(_ date: Date) -> some View {
        let calendar = Calendar.current
        let relative: String? = calendar.isDateInToday(date) ? "records.archive.today".localized
            : calendar.isDateInYesterday(date) ? "records.archive.yesterday".localized : nil
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(relative ?? date.formatted(.dateTime.year().month().day().locale(languageManager.currentLanguage.locale)))
                .font(.headline)
            if relative != nil {
                Text(date.formatted(.dateTime.month().day().locale(languageManager.currentLanguage.locale)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var selectionBar: some View {
        VStack(spacing: 4) {
            Text(String(format: "records.archive.selected".localized, model.selectedIDs.count))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("records.selectAll".localized, action: model.selectAll)
                    .frame(minHeight: 44)
                Spacer()
                Button(role: .destructive) { confirmDeletion(model.selectedIDs) } label: {
                    Label("common.delete".localized, systemImage: "trash")
                }
                .disabled(model.selectedIDs.isEmpty)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(HomeStyle.background)
    }

    private func confirmDeletion(_ ids: Set<RecordEntryID>) {
        deletionIDs = ids
        confirmsDeletion = !ids.isEmpty
    }

    @ViewBuilder
    private func detailView(_ entry: RecordEntry) -> some View {
        switch entry {
        case .liveAI(let record):
            ConversationDetailView(conversation: record) { model.delete(ids: [entry.id]); detail = nil }
        case .translation(let session):
            TranslationSessionDetailView(session: session) { model.delete(ids: [entry.id]); detail = nil }
        case .audioNote(let note):
            AudioNoteDetailView(noteID: note.id) { model.reload(); detail = nil }
        case .quickVision(let record):
            QuickVisionRecordDetailView(record: record)
        case .leanEat(let record):
            LeanEatRecordDetailView(record: record)
        }
    }
}

private struct RecordsFilterGlassSurface: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(HomeStyle.card, in: Capsule())
        } else {
            content.glassEffect(.regular, in: Capsule())
        }
    }
}

private struct RecordsGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(HomeStyle.card, in: Circle()) }
        else { content.glassEffect(.regular.interactive(), in: Circle()) }
    }
}

private struct RecordArchiveRow: View {
    let entry: RecordEntry
    let isSelecting: Bool
    let isSelected: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color {
        switch entry.id.kind {
        case .liveAI: return HomeStyle.coral
        case .translation: return HomeStyle.violet
        case .audioNote: return .orange
        case .quickVision: return .teal
        case .leanEat: return .green
        }
    }

    private var icon: String {
        switch entry.id.kind {
        case .liveAI: return "bubble.left.and.text.bubble.right"
        case .translation: return "character.bubble"
        case .audioNote: return "waveform"
        case .quickVision: return "eye"
        case .leanEat: return "leaf"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? HomeStyle.coral : .secondary)
                    .accessibilityHidden(true)
            }
            artwork
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 40 : 54,
                       height: dynamicTypeSize.isAccessibilitySize ? 40 : 54)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                if !entry.summary.isEmpty && entry.summary != entry.title {
                    Text(entry.summary.replacingOccurrences(of: "\n", with: " "))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                }
                Text(metadata)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .audioNote(let note) = entry, note.status != .completed {
                    Text("audioNote.status.\(note.status.rawValue)".localized)
                        .font(.caption2)
                        .foregroundStyle(note.status == .failed ? Color.red : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isSelecting {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 88)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var metadata: String {
        ([entry.id.kind.title, entry.date.formatted(date: .omitted, time: .shortened)] + [entry.detailMetadata].compactMap { $0 })
            .joined(separator: " · ")
    }

    @ViewBuilder private var artwork: some View {
        if case .quickVision(let record) = entry, let image = record.thumbnail {
            Image(uiImage: image).resizable().scaledToFill()
        } else if case .leanEat(let record) = entry {
            LeanEatStoredPhoto(record: record)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.gradient)
                .overlay { Image(systemName: icon).font(.system(size: 24, weight: .medium)).foregroundStyle(.white) }
        }
    }
}

struct TranslationSessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let session: TranslationSession
    let onDelete: () -> Void
    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    sessionSummary

                    LazyVStack(spacing: AppSpacing.md) {
                        ForEach(session.records) { record in
                            TranslationTurnDetailCell(record: record)
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColors.secondaryBackground.ignoresSafeArea())
            .navigationTitle("records.translation.detail.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
            }
            .confirmationDialog(
                "records.delete.title".localized,
                isPresented: $confirmsDeletion
            ) {
                Button("records.delete.confirm".localized, role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("records.delete.message".localized)
            }
        }
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(directionText)
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            Text(String(
                format: "records.translation.detail.timeRange".localized,
                session.startDate.formatted(date: .abbreviated, time: .shortened),
                session.endDate.formatted(date: .abbreviated, time: .shortened)
            ))
            .font(AppTypography.caption)
            .foregroundColor(AppColors.textSecondary)

            Text(String(format: "records.translation.turnCount".localized, session.turnCount))
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.tertiaryBackground)
        .cornerRadius(AppCornerRadius.lg)
    }

    private var directionText: String {
        if session.hasMixedLanguageDirections {
            return "records.translation.mixedDirection".localized
        }
        let directions = session.records.map {
            "\($0.sourceLanguage.flag) \($0.sourceLanguage.displayName) → \($0.targetLanguage.flag) \($0.targetLanguage.displayName)"
        }
        return directions.first ?? ""
    }
}

private struct TranslationTurnDetailCell: View {
    let record: TranslateRecord

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("\(record.sourceLanguage.flag) → \(record.targetLanguage.flag)")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text(record.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textTertiary)
            }

            if let status = record.status, status != .completed {
                Text(status.label).font(.caption).foregroundStyle(.secondary)
            }

            if !record.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(record.originalText)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
            }

            if !record.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(record.translatedText)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.tertiaryBackground)
        .cornerRadius(AppCornerRadius.lg)
    }
}
