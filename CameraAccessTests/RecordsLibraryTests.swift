import XCTest
@testable import CameraAccess

@MainActor
final class RecordsLibraryTests: XCTestCase {
    private func conversation(id: UUID = UUID(), time: TimeInterval = 100, text: String = "hello") -> RecordEntry {
        .liveAI(ConversationRecord(id: id, timestamp: Date(timeIntervalSince1970: time), messages: [ConversationMessage(role: .user, content: text)]))
    }

    func testChronologyAndCompositeIdentity() {
        let id = UUID()
        let older = conversation(id: id)
        let newer = RecordEntry.quickVision(QuickVisionRecord(id: id, timestamp: Date(timeIntervalSince1970: 90000), mode: .standard, prompt: "", result: "flower"))
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { [older, newer, older] }, delete: { _ in }))
        model.reload()
        XCTAssertEqual(model.entries.map(\.id), [newer.id, older.id])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(model.sections(calendar: calendar).count, 2)
    }

    func testFullTextSearchAndFilterIntersection() {
        let entry = conversation(text: String(repeating: "opening ", count: 30) + "Café destination")
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { [entry] }, delete: { _ in }))
        model.reload()
        model.query = "CAFE destination"
        XCTAssertEqual(model.visibleEntries.count, 1)
        model.filter = .quickVision
        XCTAssertTrue(model.visibleEntries.isEmpty)
    }

    func testSelectionTracksVisibleResults() {
        let first = conversation(text: "one"), second = conversation(text: "two")
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { [first, second] }, delete: { _ in }))
        model.reload()
        model.isSelecting = true
        model.selectAll()
        XCTAssertEqual(model.selectedIDs.count, 2)
        model.query = "one"
        XCTAssertTrue(model.selectedIDs.isEmpty)
        model.selectAll()
        XCTAssertEqual(model.selectedIDs, [first.id])
        model.filter = .liveAI
        XCTAssertFalse(model.isSelecting)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testDeletionResolvesLatestRecordAndPreservesOtherTypes() {
        let id = UUID()
        var rows = [conversation(id: id, text: "old")]
        let other = RecordEntry.quickVision(QuickVisionRecord(id: id, mode: .standard, prompt: "", result: "keep"))
        var deletedTitle: String?
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { rows }, delete: { targets in
            deletedTitle = targets.first?.title
            let ids = Set(targets.map(\.id))
            rows.removeAll { ids.contains($0.id) }
        }))
        model.reload()
        let selected = model.entries[0].id
        rows = [conversation(id: id, text: "updated"), other]
        model.delete(ids: [selected])
        XCTAssertEqual(deletedTitle, "updated")
        XCTAssertEqual(model.entries.map(\.id), [other.id])
        XCTAssertFalse(model.deletionFailed)
    }

    func testTranslationSearchAndDeletionIncludeNewTurns() {
        let sessionID = UUID()
        var turns = [TranslateRecord(sessionID: sessionID, sourceLanguage: .zh, targetLanguage: .en, originalText: "咖啡店", translatedText: "coffee shop")]
        var deletedIDs = Set<UUID>()
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: {
            TranslationSessionBuilder.group(records: turns).map(RecordEntry.translation)
        }, delete: { entries in
            for case .translation(let session) in entries { deletedIDs.formUnion(session.records.map(\.id)) }
            turns.removeAll { deletedIDs.contains($0.id) }
        }))
        model.reload()
        model.query = "coffee"
        XCTAssertEqual(model.visibleEntries.count, 1)
        model.query = "咖啡"
        XCTAssertEqual(model.visibleEntries.count, 1)
        let selected = model.entries[0].id
        turns.append(TranslateRecord(sessionID: sessionID, sourceLanguage: .zh, targetLanguage: .en, originalText: "谢谢", translatedText: "thank you"))
        let expectedIDs = Set(turns.map(\.id))
        model.delete(ids: [selected])
        XCTAssertEqual(deletedIDs, expectedIDs)
        XCTAssertTrue(model.entries.isEmpty)
    }

    func testEditedNoteSearchAndRefresh() {
        var note = AudioNote(id: UUID(), title: "note", createdAt: Date(), updatedAt: Date(), duration: 10,
                             audioRelativePath: "unused", input: .iPhone, languageHints: [], diarizationEnabled: false,
                             status: .transcribing, segments: [], speakerNames: [:])
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { [.audioNote(note)] }, delete: { _ in }))
        model.reload()
        model.query = "corrected"
        XCTAssertTrue(model.visibleEntries.isEmpty)
        note.segments = [AudioTranscriptSegment(beginTimeMs: 0, endTimeMs: 1000, originalText: "original", editedText: "corrected", speakerID: nil)]
        note.status = .completed
        model.reload()
        XCTAssertEqual(model.visibleEntries.count, 1)
        XCTAssertEqual(model.visibleEntries[0].summary, "corrected")
        model.query = "original"
        XCTAssertTrue(model.visibleEntries.isEmpty)
    }

    func testFailedDeletionRetainsSelection() {
        let entry = conversation()
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { [entry] }, delete: { _ in }))
        model.reload()
        model.isSelecting = true
        model.delete(ids: [entry.id])
        XCTAssertTrue(model.deletionFailed)
        XCTAssertEqual(model.selectedIDs, [entry.id])
        XCTAssertEqual(model.entries.count, 1)
    }
}
