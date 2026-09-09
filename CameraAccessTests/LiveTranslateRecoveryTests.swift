import Foundation
import XCTest
@testable import CameraAccess

final class LiveTranslateRecoveryTests: XCTestCase {
    private func source(_ id: String, final: Bool = true) -> TranslateSourceTranscriptEvent {
        .init(itemID: id, confirmedText: "source " + id, pendingText: "", isFinal: final)
    }
    private func text(_ id: String, final: Bool = true, value: String = "译文") -> TranslateTextEvent {
        .init(responseID: "r" + id, itemID: "a" + id, confirmedText: value, pendingText: "", isFinal: final)
    }
    private func linked(_ id: String = "1") -> TranslationTurnCoordinator {
        var c = TranslationTurnCoordinator(sourceLanguage: .en, targetLanguage: .zh)
        _ = c.receiveSource(source(id))
        _ = c.receiveLink(sourceItemID: id, responseItemID: "a" + id)
        return c
    }

    func testTextDoneWaitsForResponseOutcome() {
        var c = linked()
        let provisional = c.receiveTranslation(text("1"))
        XCTAssertTrue(provisional.recordsToUpsert.isEmpty)
        let done = c.receiveResponseFinished(responseID: "r1", status: "completed")
        XCTAssertEqual(done.turns.first?.status, .completed)
        XCTAssertEqual(done.turns.first?.id, provisional.turns.first?.id)
        XCTAssertEqual(done.turns.first?.timestamp, provisional.turns.first?.timestamp)
    }

    func testFailedResponseNeverBecomesSuccessfulRecord() {
        var c = linked()
        _ = c.receiveTranslation(text("1"))
        let result = c.receiveResponseFinished(responseID: "r1", status: "failed")
        XCTAssertEqual(result.recordsToUpsert.first?.status, .failed)
        XCTAssertEqual(result.recordsToUpsert.first?.translatedText, "译文")
    }

    func testEmptyCompletedResponseHasTerminalStatus() {
        var c = linked()
        _ = c.receiveTranslation(text("1", value: ""))
        let result = c.receiveResponseFinished(responseID: "r1")
        XCTAssertEqual(result.turns.first?.status, .empty)
    }

    func testSourceFailureCreatesRecoverableVisibleRecord() {
        var c = linked()
        let result = c.receiveSourceFailure(itemID: "1")
        XCTAssertEqual(result.turns.first?.status, .failed)
        XCTAssertEqual(result.recordsToUpsert.first?.originalText, "source 1")
    }

    func testTimeoutRecoversInPlaceWhenLateResultArrives() {
        var c = linked()
        let timeout = c.tick(at: Date().addingTimeInterval(31))
        XCTAssertEqual(timeout.turns.first?.status, .timedOut)
        _ = c.receiveTranslation(text("1"))
        let recovered = c.receiveResponseFinished(responseID: "r1")
        XCTAssertEqual(recovered.turns.first?.status, .completed)
        XCTAssertEqual(timeout.turns.first?.id, recovered.turns.first?.id)
    }

    func testFinalizationPreservesUnlinkedTextWithoutGuessing() {
        var c = TranslationTurnCoordinator(sourceLanguage: .en, targetLanguage: .zh)
        _ = c.receiveSource(source("1"))
        _ = c.receiveTranslation(text("2"))
        let result = c.finalize()
        XCTAssertEqual(result.turns.count, 2)
        XCTAssertTrue(result.turns.allSatisfy { $0.status == .unlinked })
        XCTAssertEqual(result.recordsToUpsert.filter { !$0.originalText.isEmpty }.first?.translatedText, "")
        XCTAssertEqual(result.recordsToUpsert.filter { !$0.translatedText.isEmpty }.first?.originalText, "")
    }

    func testCompletionDoesNotMoveOlderTurnAfterNewerTurn() {
        var c = linked()
        _ = c.receiveSource(source("2"))
        _ = c.receiveLink(sourceItemID: "2", responseItemID: "a2")
        _ = c.receiveTranslation(text("2"))
        let result = c.receiveResponseFinished(responseID: "r2")
        XCTAssertEqual(result.turns.map(\.sourceItemID), ["1", "2"])
        XCTAssertEqual(result.turns.last?.status, .completed)
    }

    func testFailedEmptyAudioHeadCanBeSealedAndQueueAdvances() {
        var q = TranslationAudioQueue()
        q.register(responseID: "failed")
        q.append(Data([0, 0]), responseID: "next")
        XCTAssertNil(q.activateNextIfReady())
        _ = q.markServerFinished("failed")
        XCTAssertEqual(q.activateNextIfReady(), "failed")
        XCTAssertTrue(q.completeActiveIfDrained("failed"))
        XCTAssertEqual(q.activateNextIfReady(), "next")
    }

    func testPartialRecordStatusRoundTripsAndLegacyStatusIsOptional() throws {
        var record = TranslateRecord(sourceLanguage: .en, targetLanguage: .zh, originalText: "hello", translatedText: "")
        record.status = .incomplete
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(TranslateRecord.self, from: data).status, .incomplete)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "status")
        XCTAssertNil(try JSONDecoder().decode(TranslateRecord.self, from: JSONSerialization.data(withJSONObject: json)).status)
    }
    func testQueuedSaveCannotRestoreDeletedRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LiveTranslateHistoryStorage(fileURL: directory.appendingPathComponent("history.json"))
        let finished = expectation(description: "Queued writes drained")
        finished.expectedFulfillmentCount = 8
        for _ in 0..<8 {
            store.enqueue([TranslateRecord(sourceLanguage: .en, targetLanguage: .zh,
                                           originalText: "test", translatedText: "测试")]) { _ in finished.fulfill() }
        }
        store.deleteAll()
        wait(for: [finished], timeout: 5)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testLateLinkReplacesPreviouslySavedOrphan() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LiveTranslateHistoryStorage(fileURL: directory.appendingPathComponent("history.json"))
        let session = UUID()
        var orphan = TranslateRecord(sessionID: session, responseID: "r", sourceLanguage: .en,
                                     targetLanguage: .zh, originalText: "", translatedText: "你好")
        orphan.status = .unlinked
        let linked = TranslateRecord(sessionID: session, sourceItemID: "s", responseID: "r", sourceLanguage: .en,
                                     targetLanguage: .zh, originalText: "Hello", translatedText: "你好")
        let saved = expectation(description: "Both revisions saved")
        saved.expectedFulfillmentCount = 2
        store.enqueue([orphan]) { _ in saved.fulfill() }
        store.enqueue([linked]) { _ in saved.fulfill() }
        wait(for: [saved], timeout: 5)
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(store.loadAll().first?.id, linked.id)
    }

}
