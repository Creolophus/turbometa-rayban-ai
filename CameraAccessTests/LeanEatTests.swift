import XCTest
import SwiftUI
@testable import CameraAccess

@MainActor
final class LeanEatTests: XCTestCase {
    private var directory: URL!
    private var storage: LeanEatStorage!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LeanEatTests-" + UUID().uuidString)
        storage = LeanEatStorage(directory: directory)
    }

    override func tearDown() async throws {
        await storage.reload()
        try? FileManager.default.removeItem(at: directory)
        storage = nil
    }

    static let response = """
    {"foods":[{"name":"鸡胸肉","portion":"100 g","calories":165,"protein":31,"fat":3.6,
    "carbs":0,"health_rating":"良好"}],"total_calories":165,"total_protein":31,"total_fat":3.6,
    "total_carbs":0,"health_score":82,"suggestions":["搭配蔬菜"]}
    """

    private func result() throws -> FoodNutritionResponse { try LeanEatService.parse(Self.response) }

    private func photo() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.jpegData(compressionQuality: 0.8)!
    }

    private func record(id: UUID = UUID()) throws -> LeanEatRecord {
        LeanEatRecord(id: id, timestamp: Date(), source: .library,
                      imagePath: id.uuidString + "/photo.jpg", nutrition: try result())
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("State did not settle")
    }

    func testParsesWrappedJSONAndRejectsInvalidNumbers() throws {
        XCTAssertEqual(try LeanEatService.parse("json\n" + Self.response + "\n").healthScore, 82)
        XCTAssertThrowsError(try LeanEatService.parse(Self.response.replacingOccurrences(of: "\"health_score\":82", with: "\"health_score\":182")))
        XCTAssertThrowsError(try LeanEatService.parse(Self.response.replacingOccurrences(of: "\"protein\":31", with: "\"protein\":-1")))
        XCTAssertThrowsError(try LeanEatService.parse("not json"))
    }

    func testEmptyFoodIsNotSaved() async throws {
        let empty = FoodNutritionResponse(foods: [], totalCalories: 0, totalProtein: 0, totalFat: 0, totalCarbs: 0, healthScore: 0, suggestions: [])
        let model = LeanEatViewModel(storage: storage, analyze: { _ in empty })
        model.selectPhoto { self.photo() }
        try await waitUntil { model.phase == .failed }
        XCTAssertNil(model.nutrition)
        XCTAssertTrue(storage.loadAll().isEmpty)
        model.close()
    }

    func testSaveIsIdempotentAndSurvivesReload() async throws {
        let record = try record()
        try await storage.save(record, jpeg: photo())
        try await storage.save(record, jpeg: photo())
        XCTAssertEqual(storage.loadAll().count, 1)
        let restored = LeanEatStorage(directory: directory)
        await restored.reload()
        XCTAssertEqual(restored.loadAll().first?.nutrition.totalCalories, 165)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.imageURL(for: record).path))
    }

    func testDeleteRemovesRecordAndPhoto() async throws {
        let record = try record()
        try await storage.save(record, jpeg: photo())
        try await storage.delete(ids: [record.id])
        XCTAssertTrue(storage.loadAll().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.imageURL(for: record).path))
        let restored = LeanEatStorage(directory: directory)
        await restored.reload()
        XCTAssertTrue(restored.loadAll().isEmpty)
    }

    func testSaveFailureKeepsResultAndRetryDoesNotAnalyzeAgain() async throws {
        try Data([0]).write(to: directory)
        var calls = 0
        let nutrition = try result()
        let model = LeanEatViewModel(storage: storage, analyze: { _ in calls += 1; return nutrition })
        model.selectPhoto { self.photo() }
        try await waitUntil { model.saveState == .failed }
        XCTAssertEqual(model.phase, .result)
        XCTAssertTrue(model.hasUnsavedResult)
        try FileManager.default.removeItem(at: directory)
        model.retrySaving()
        await model.waitForSave()
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertFalse(model.hasUnsavedResult)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(storage.loadAll().count, 1)
        model.close()
    }

    func testDeleteFailureRetainsRecord() async throws {
        let record = try record()
        try await storage.save(record, jpeg: photo())
        let blocker = directory.appendingPathComponent(".trash-" + record.id.uuidString)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        do { try await storage.delete(ids: [record.id]); XCTFail("Expected deletion failure") } catch {}
        await storage.reload()
        XCTAssertEqual(storage.loadAll().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.imageURL(for: record).path))
    }

    func testLateAnalysisAfterCloseCannotRestoreResultOrSave() async throws {
        var continuation: CheckedContinuation<FoodNutritionResponse, Never>?
        let model = LeanEatViewModel(storage: storage, analyze: { _ in
            await withCheckedContinuation { continuation = $0 }
        })
        model.selectPhoto { self.photo() }
        try await waitUntil { continuation != nil }
        model.close()
        continuation?.resume(returning: try result())
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.phase, .closed)
        XCTAssertNil(model.photo)
        XCTAssertNil(model.nutrition)
        XCTAssertTrue(storage.loadAll().isEmpty)
    }

    func testLateLibraryLoadAfterCloseIsIgnored() async throws {
        var continuation: CheckedContinuation<Data, Never>?
        var calls = 0
        let nutrition = try result()
        let model = LeanEatViewModel(storage: storage, analyze: { _ in calls += 1; return nutrition })
        model.selectPhoto { await withCheckedContinuation { continuation = $0 } }
        try await waitUntil { continuation != nil }
        model.close()
        continuation?.resume(returning: photo())
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.photo)
    }

    func testAnalysisTimeoutAndLateResponse() async throws {
        var continuation: CheckedContinuation<FoodNutritionResponse, Never>?
        let model = LeanEatViewModel(storage: storage, analysisTimeout: 0.05, analyze: { _ in
            await withCheckedContinuation { continuation = $0 }
        })
        model.selectPhoto { self.photo() }
        try await waitUntil { continuation != nil && model.phase == .failed }
        continuation?.resume(returning: try result())
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.phase, .failed)
        XCTAssertTrue(storage.loadAll().isEmpty)
        model.close()
    }

    func testRetryAndAnotherMealProduceDistinctRecords() async throws {
        var calls = 0
        let nutrition = try result()
        let model = LeanEatViewModel(storage: storage, analyze: { _ in
            calls += 1
            if calls == 1 { throw LeanEatError.timeout }
            return nutrition
        })
        model.selectPhoto { self.photo() }
        try await waitUntil { model.phase == .failed }
        model.retry()
        try await waitUntil { model.saveState == .saved }
        model.reset()
        model.selectPhoto { self.photo() }
        try await waitUntil { model.saveState == .saved }
        XCTAssertEqual(storage.loadAll().count, 2)
        XCTAssertEqual(calls, 3)
        model.close()
    }

    func testRecordsFilterAndSearchIncludeFood() throws {
        let food = try record()
        let model = RecordsLibraryViewModel(store: RecordsLibraryStore(load: { [.leanEat(food)] }, delete: { _ in }))
        model.reload()
        model.filter = .leanEat
        model.query = "蔬菜"
        XCTAssertEqual(model.visibleEntries.count, 1)
        model.query = "not present"
        XCTAssertTrue(model.visibleEntries.isEmpty)
        XCTAssertFalse(RecordsFilter.leanEat.isComingSoon)
        XCTAssertTrue(RecordsFilter.wordLearn.isComingSoon)
    }

    func testFailedLibraryLoadCanBeRetried() async throws {
        var loads = 0
        let nutrition = try result()
        let model = LeanEatViewModel(storage: storage, analyze: { _ in nutrition })
        model.selectPhoto {
            loads += 1
            if loads == 1 { throw LeanEatError.image }
            return self.photo()
        }
        try await waitUntil { model.phase == .failed }
        model.retry()
        try await waitUntil { model.saveState == .saved }
        XCTAssertEqual(loads, 2)
        XCTAssertEqual(storage.loadAll().count, 1)
        model.close()
    }

    func testImageIsDownsampledAndInvalidDataRejected() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2200, height: 1200)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2200, height: 1200))
        }
        let data = try await LeanEatImageProcessor.prepare(image.jpegData(compressionQuality: 1)!)
        XCTAssertLessThanOrEqual(data.count, 2_000_000)
        XCTAssertLessThanOrEqual(UIImage(data: data)!.size.width, 1600)
        do { _ = try await LeanEatImageProcessor.prepare(Data([0])); XCTFail("Invalid photo accepted") } catch {}
    }
}
