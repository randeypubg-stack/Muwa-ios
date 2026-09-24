import Foundation

enum SubtitleLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
  case arabic = "AR"
  case russian = "RU"
  case english = "EN"
  var id: String { rawValue }
}

struct SubtitleWord: Codable, Hashable, Sendable {
  let text: String
  let start: TimeInterval
  let end: TimeInterval
}

struct SubtitleSegment: Codable, Hashable, Sendable, Identifiable {
  var id: String { "\(start)-\(end)-\(ar)" }
  let start: TimeInterval
  let end: TimeInterval
  let ar: String
  let ru: String
  let en: String
  let words: [SubtitleWord]?

  func text(for language: SubtitleLanguage) -> String {
    switch language {
    case .arabic: return ar
    case .russian: return ru
    case .english: return en
    }
  }
}


// V2 is separate: old subtitles and their cache keep their original format.
enum AITranslationLanguage: String, CaseIterable, Identifiable, Codable {
  case original, ru, en, tr, uz, kk, fr
  var id: String { rawValue }
  var title: String {
    switch self {
    case .original: return "Оригинал"
    case .ru: return "Русский"
    case .en: return "English"
    case .tr: return "Türkçe"
    case .uz: return "O‘zbekcha"
    case .kk: return "Қазақша"
    case .fr: return "Français"
    }
  }
}

struct AISubtitleDocument: Codable, Equatable {
  let version: Int
  let id: String
  let language: String
  let segments: [AISubtitleSegment]
  var isRTL: Bool { ["ar", "fa", "he", "ur"].contains(language.components(separatedBy: "-")[0]) }
  func activeIndex(at time: Double) -> Int? {
    guard time.isFinite else { return nil }
    var low = 0, high = segments.count
    while low < high {
      let mid = (low + high) / 2
      if segments[mid].start <= time { low = mid + 1 } else { high = mid }
    }
    let index = low - 1
    return index >= 0 && time < segments[index].end ? index : nil
  }
  func validated() throws -> Self {
    guard version == 2, !id.isEmpty, !segments.isEmpty, segments.count <= 600 else { throw URLError(.cannotParseResponse) }
    var lastEnd: Double = 0
    var ids = Set<String>()
    for segment in segments {
      guard ids.insert(segment.id).inserted, segment.start.isFinite, segment.end.isFinite,
        segment.start >= lastEnd, segment.end > segment.start, !segment.original.isEmpty
      else { throw URLError(.cannotParseResponse) }
      lastEnd = segment.end
      var wordEnd = segment.start
      for word in segment.words {
        guard word.start.isFinite, word.end.isFinite, word.start >= wordEnd,
          word.end > word.start, word.end <= segment.end, !word.text.isEmpty
        else { throw URLError(.cannotParseResponse) }
        wordEnd = word.end
      }
    }
    return self
  }
}
struct AISubtitleSegment: Codable, Equatable, Identifiable {
  let id: String
  let start: Double
  let end: Double
  let original: String
  let words: [SubtitleWord]
  let timing: String
}
struct AISubtitleTranslation: Codable, Equatable {
  let documentId: String
  let language: String
  let segments: [String: String]
}
