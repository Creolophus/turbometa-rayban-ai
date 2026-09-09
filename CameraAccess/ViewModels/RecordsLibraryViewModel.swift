import Foundation

extension Notification.Name {
    static let recordsLibraryDidChange = Notification.Name("recordsLibraryDidChange")
}

/// Injectable store adapter keeps aggregation/search tests independent of SDK and disk.
@MainActor
struct RecordsLibraryStore {
    var load: () -> [RecordEntry]
    var delete: ([RecordEntry]) -> Void
    var deleteFood: (Set<UUID>) async throws -> Void = { try await LeanEatStorage.shared.delete(ids: $0) }

    static var live: RecordsLibraryStore {
        RecordsLibraryStore(load: {
            ConversationStorage.shared.loadAllConversations().map(RecordEntry.liveAI)
                + TranslationSessionBuilder.group(records: LiveTranslateHistoryStorage.shared.loadAll()).map(RecordEntry.translation)
                + AudioNoteStorage.shared.loadAll().map(RecordEntry.audioNote)
                + QuickVisionStorage.shared.loadAllRecords().map(RecordEntry.quickVision)
                + LeanEatStorage.shared.loadAll().map(RecordEntry.leanEat)
        }, delete: { entries in
            var translationIDs = Set<UUID>()
            for entry in entries {
                switch entry {
                case .liveAI(let record): ConversationStorage.shared.deleteConversation(record.id)
                case .translation(let session): translationIDs.formUnion(session.records.map(\.id))
                case .audioNote(let note): AudioNoteLibrary.shared.delete(note.id)
                case .quickVision(let record): QuickVisionStorage.shared.deleteRecord(record.id)
                case .leanEat: break // Photo packages are deleted asynchronously by the view model.
                }
            }
            if !translationIDs.isEmpty {
                LiveTranslateHistoryStorage.shared.deleteRecords(ids: translationIDs)
            }
        })
    }
}

@MainActor
final class RecordsLibraryViewModel: ObservableObject {
    @Published private(set) var entries: [RecordEntry] = []
    @Published var filter: RecordsFilter = .all {
        didSet { if oldValue != filter { endSelection() } }
    }
    @Published var query = "" {
        didSet { if oldValue != query { selectedIDs.removeAll() } }
    }
    @Published var isSelecting = false
    @Published var selectedIDs = Set<RecordEntryID>()
    @Published var deletionFailed = false

    private let store: RecordsLibraryStore
    private var isDeleting = false

    init(store: RecordsLibraryStore? = nil) {
        self.store = store ?? .live
    }

    var visibleEntries: [RecordEntry] {
        guard !filter.isComingSoon else { return [] }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in
            (filter.kind == nil || entry.id.kind == filter.kind)
                && words.allSatisfy { entry.searchText.localizedStandardContains($0) }
        }
    }

    func sections(calendar: Calendar = .current) -> [RecordDaySection] {
        let grouped = Dictionary(grouping: visibleEntries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { RecordDaySection(date: $0, entries: grouped[$0] ?? []) }
    }

    func reload() {
        guard !isDeleting else { return }
        var seen = Set<RecordEntryID>()
        entries = store.load().sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            let lhs = $0.id.kind.rawValue + $0.id.value.uuidString
            let rhs = $1.id.kind.rawValue + $1.id.value.uuidString
            return lhs < rhs
        }.filter { seen.insert($0.id).inserted }
        selectedIDs.formIntersection(Set(visibleEntries.map(\.id)))
    }

    func toggle(_ id: RecordEntryID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func selectAll() { selectedIDs = Set(visibleEntries.map(\.id)) }
    func endSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    func delete(ids: Set<RecordEntryID>) {
        guard !isDeleting else { return }
        // Resolve current sessions again so deletion includes turns appended since selection.
        reload()
        let targets = entries.filter { ids.contains($0.id) }
        isDeleting = true
        let foodIDs = Set(targets.compactMap { entry -> UUID? in
            if case .leanEat(let record) = entry { return record.id }
            return nil
        })
        if !foodIDs.isEmpty {
            Task {
                do { try await store.deleteFood(foodIDs) }
                catch { deletionFailed = true }
                finishDeleting(targets: targets, ids: ids)
            }
            return
        }
        finishDeleting(targets: targets, ids: ids)
    }

    private func finishDeleting(targets: [RecordEntry], ids: Set<RecordEntryID>) {
        store.delete(targets)
        isDeleting = false
        reload()
        let remaining = Set(entries.map(\.id)).intersection(ids)
        deletionFailed = !remaining.isEmpty
        if remaining.isEmpty { endSelection() }
        else { selectedIDs = remaining }
    }
}
