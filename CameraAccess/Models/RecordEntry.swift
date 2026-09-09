import Foundation

/// The category is part of identity: UUIDs from independent stores can collide.
struct RecordEntryID: Hashable {
    let kind: RecordKind
    let value: UUID
}

enum RecordKind: String, CaseIterable {
    case liveAI, translation, audioNote, quickVision, leanEat

    var title: String {
        switch self {
        case .liveAI: return "Live AI"
        case .translation: return "records.filter.translation".localized
        case .audioNote: return "home.assistant.notes".localized
        case .quickVision: return "home.assistant.vision".localized
        case .leanEat: return "LeanEat"
        }
    }
}

enum RecordsFilter: String, CaseIterable, Identifiable {
    case all, liveAI, translation, audioNote, quickVision, leanEat, wordLearn
    var id: Self { self }
    var kind: RecordKind? { RecordKind(rawValue: rawValue) }
    var isComingSoon: Bool { self == .wordLearn }
    var title: String {
        switch self {
        case .all: return "records.filter.all".localized
        case .liveAI: return "Live AI"
        case .translation: return "records.filter.translation".localized
        case .audioNote: return "records.filter.notes".localized
        case .quickVision: return "records.filter.vision".localized
        case .leanEat: return "LeanEat"
        case .wordLearn: return "WordLearn"
        }
    }
}

/// A presentation adapter only. Original records and persistence formats stay intact.
enum RecordEntry: Identifiable {
    case liveAI(ConversationRecord)
    case translation(TranslationSession)
    case audioNote(AudioNote)
    case quickVision(QuickVisionRecord)
    case leanEat(LeanEatRecord)

    var id: RecordEntryID {
        switch self {
        case .liveAI(let record): return RecordEntryID(kind: .liveAI, value: record.id)
        case .translation(let session): return RecordEntryID(kind: .translation, value: session.id)
        case .audioNote(let note): return RecordEntryID(kind: .audioNote, value: note.id)
        case .quickVision(let record): return RecordEntryID(kind: .quickVision, value: record.id)
        case .leanEat(let record): return RecordEntryID(kind: .leanEat, value: record.id)
        }
    }

    var date: Date {
        switch self {
        case .liveAI(let record): return record.timestamp
        case .translation(let session): return session.endDate
        case .audioNote(let note): return note.createdAt
        case .quickVision(let record): return record.timestamp
        case .leanEat(let record): return record.timestamp
        }
    }

    var title: String {
        let text: String
        switch self {
        case .liveAI(let record):
            text = record.messages.first(where: { $0.role == .user })?.content ?? ""
        case .translation(let session):
            text = session.records.first(where: { !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.originalText ?? ""
        case .audioNote(let note): text = note.title
        case .quickVision(let record):
            text = record.result.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        case .leanEat(let record): text = record.title
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#*")))
        return cleaned.isEmpty ? id.kind.title : cleaned
    }

    var summary: String {
        switch self {
        case .liveAI(let record): return record.messages.last?.content ?? ""
        case .translation(let session): return session.previewText
        case .audioNote(let note):
            return note.transcript.isEmpty ? "audioNote.records.noTranscript".localized : note.transcript
        case .quickVision(let record):
            let lines = record.result.split(whereSeparator: \.isNewline)
            return lines.count > 1 ? lines.dropFirst().joined(separator: " ") : record.mode.displayName
        case .leanEat(let record): return "\(record.nutrition.totalCalories) kcal"
        }
    }

    var searchText: String {
        switch self {
        case .liveAI(let record): return record.messages.map(\.content).joined(separator: "\n")
        case .translation(let session): return session.records.map { $0.originalText + "\n" + $0.translatedText }.joined(separator: "\n")
        case .audioNote(let note): return note.title + "\n" + note.transcript
        case .quickVision(let record): return record.result + "\n" + record.prompt + "\n" + record.mode.displayName
        case .leanEat(let record): return record.title + "\n" + record.nutrition.suggestions.joined(separator: "\n")
        }
    }

    var detailMetadata: String? {
        switch self {
        case .liveAI(let record): return String(format: "records.liveAI.messageCount".localized, record.messageCount)
        case .translation(let session):
            guard let first = session.records.first else { return nil }
            if session.hasMixedLanguageDirections { return "records.translation.mixedDirection".localized }
            return first.sourceLanguage.displayName + " → " + first.targetLanguage.displayName
        case .audioNote(let note):
            let seconds = max(0, Int(note.duration))
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        case .quickVision, .leanEat: return nil
        }
    }
}

struct RecordDaySection: Identifiable {
    let date: Date
    let entries: [RecordEntry]
    var id: Date { date }
}
