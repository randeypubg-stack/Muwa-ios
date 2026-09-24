import Foundation
@main struct AISubtitleChecks {
  static func main() throws {
    let a = AISubtitleSegment(id: "s0", start: 1, end: 3, original: "مرحبا", words: [], timing: "phrase")
    let b = AISubtitleSegment(id: "s1", start: 6, end: 8, original: "بكم", words: [], timing: "phrase")
    let doc = try AISubtitleDocument(version: 2, id: "test", language: "ar", segments: [a,b]).validated()
    precondition(doc.isRTL && doc.activeIndex(at: 0) == nil)
    precondition(doc.activeIndex(at: 1) == 0 && doc.activeIndex(at: 2.9) == 0)
    precondition(doc.activeIndex(at: 3) == nil && doc.activeIndex(at: 5) == nil)
    precondition(doc.activeIndex(at: 6) == 1 && doc.activeIndex(at: 8) == nil)
    precondition(doc.activeIndex(at: .nan) == nil)
    let roundtrip = try JSONDecoder().decode(AISubtitleDocument.self, from: JSONEncoder().encode(doc))
    precondition(roundtrip == doc)
    let overlap = AISubtitleDocument(version: 2, id: "test", language: "ar", segments: [b,a])
    precondition((try? overlap.validated()) == nil)
    let duplicate = AISubtitleDocument(version: 2, id: "test", language: "ar", segments: [a,a])
    precondition((try? duplicate.validated()) == nil)
    let legacy = Data("[{\"start\":1,\"end\":3,\"ar\":\"مرحبا\",\"ru\":\"Привет\",\"en\":\"Hello\"}]".utf8)
    let old = try JSONDecoder().decode([SubtitleSegment].self, from: legacy)
    precondition(old[0].text(for: .russian) == "Привет")
    print("PASS: subtitle v2 boundaries, silent gaps, RTL, serialization, validation, legacy decoding")
  }
}
