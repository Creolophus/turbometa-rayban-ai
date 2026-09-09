import Foundation

/// Each record is committed as one directory containing versioned JSON and a JPEG.
final class LeanEatStorage: @unchecked Sendable {
    static let shared = LeanEatStorage()
    private let directory: URL
    private let queue = DispatchQueue(label: "com.turbometa.leaneat.storage", qos: .utility)
    private let lock = NSLock()
    private var cached: [LeanEatRecord] = []
    private struct Envelope: Codable {
        var version = 1
        let record: LeanEatRecord
    }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TurboMeta/LeanEat", isDirectory: true)) {
        self.directory = directory
        queue.async { [self] in refreshCache() }
    }

    func loadAll() -> [LeanEatRecord] {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    func imageURL(for record: LeanEatRecord) -> URL {
        directory.appendingPathComponent(record.id.uuidString).appendingPathComponent("photo.jpg")
    }

    func save(_ record: LeanEatRecord, jpeg: Data) async throws {
        try await perform {
            try record.nutrition.validate()
            guard !record.nutrition.foods.isEmpty, !jpeg.isEmpty, jpeg.count <= 2_000_000,
                  record.imagePath == record.id.uuidString + "/photo.jpg" else { throw CocoaError(.coderInvalidValue) }
            let manager = FileManager.default
            try manager.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let final = self.directory.appendingPathComponent(record.id.uuidString)
            // Retries use the same ID and never create a duplicate or overwrite a committed result.
            if manager.fileExists(atPath: final.path) { self.refreshCache(); return }
            let staging = self.directory.appendingPathComponent(".staging-" + UUID().uuidString)
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: staging) }
            try jpeg.write(to: staging.appendingPathComponent("photo.jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try JSONEncoder().encode(Envelope(record: record))
                .write(to: staging.appendingPathComponent("record.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try manager.moveItem(at: staging, to: final)
            self.refreshCache()
        }
    }

    func delete(ids: Set<UUID>) async throws {
        try await perform {
            let manager = FileManager.default
            for id in ids {
                let source = self.directory.appendingPathComponent(id.uuidString)
                guard manager.fileExists(atPath: source.path) else { continue }
                // Rename first so a failed delete can restore the record's visibility.
                let trash = self.directory.appendingPathComponent(".trash-" + id.uuidString)
                try manager.moveItem(at: source, to: trash)
                do { try manager.removeItem(at: trash) }
                catch {
                    try? manager.moveItem(at: trash, to: source)
                    self.refreshCache()
                    throw error
                }
            }
            self.refreshCache()
        }
    }

    func reload() async {
        try? await perform { self.refreshCache() }
    }

    private func perform(_ operation: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { try operation(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func refreshCache() {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let records = folders.compactMap { folder -> LeanEatRecord? in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("record.json")),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                  envelope.version == 1, envelope.record.id.uuidString == folder.lastPathComponent else { return nil }
            return envelope.record
        }.sorted { $0.timestamp > $1.timestamp }
        lock.lock()
        cached = records
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .recordsLibraryDidChange, object: nil)
        }
    }
}
