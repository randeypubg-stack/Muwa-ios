import CryptoKit
import Combine
import Foundation

@MainActor
final class SubtitleManager: ObservableObject {
  enum LoadState: Equatable {
    case idle
    case loading
    case ready
    case unavailable(String)
  }

  @Published private(set) var segmentsByTrack: [String: [SubtitleSegment]] = [:]
  @Published private(set) var stateByTrack: [String: LoadState] = [:]

  private let apiBaseURL = BackendConfig.apiBaseURL
  private var tasks: [String: Task<Void, Never>] = [:]

  func state(for track: Track) -> LoadState {
    stateByTrack[track.id] ?? .idle
  }

  func segments(for track: Track) -> [SubtitleSegment] {
    segmentsByTrack[track.id] ?? loadCached(trackID: track.id) ?? []
  }

  func load(for track: Track) {
    if segmentsByTrack[track.id] != nil { return }
    if let cached = loadCached(trackID: track.id), !cached.isEmpty {
      segmentsByTrack[track.id] = cached
      stateByTrack[track.id] = .ready
      return
    }
    guard tasks[track.id] == nil else { return }
    guard let src = track.cdnSourcePath else {
      stateByTrack[track.id] = .unavailable(
        "Для этого файла нет поддерживаемого источника субтитров.")
      return
    }

    stateByTrack[track.id] = .loading
    tasks[track.id] = Task { [weak self] in
      guard let self else { return }
      defer { self.tasks[track.id] = nil }
      do {
        let result = try await self.fetch(track: track, src: src)
        guard !Task.isCancelled else { return }
        self.segmentsByTrack[track.id] = result
        self.stateByTrack[track.id] = .ready
        self.saveCache(result, trackID: track.id)
      } catch {
        guard !Task.isCancelled else { return }
        self.stateByTrack[track.id] = .unavailable(error.localizedDescription)
      }
    }
  }

  func activeIndex(for track: Track, time: TimeInterval) -> Int? {
    let values = segments(for: track)
    return values.firstIndex(where: { time >= $0.start && time < $0.end })
  }

  private struct RequestBody: Codable {
    let src: String
    let title: String
    let durationSeconds: Double
    let embeddedLyrics: String?
  }

  private struct Envelope<T: Codable>: Codable {
    let json: T
  }

  private struct ResponseBody: Codable {
    let segments: [SubtitleSegment]
    let source: String
  }

  private struct ErrorBody: Codable {
    let error: String
    let code: String?
  }

  private func fetch(track: Track, src: String) async throws -> [SubtitleSegment] {
    let encoded = try JSONEncoder().encode(
      Envelope(
        json: RequestBody(
          src: src,
          title: track.title,
          durationSeconds: max(track.duration, 1),
          embeddedLyrics: nil
        )))
    let bases = BackendConfig.candidateAPIBaseURLs
    var lastTransportError: Error?

    for (index, baseURL) in bases.enumerated() {
      let url = baseURL.appending(path: "_api/transcribe")
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.timeoutInterval = 180
      request.httpBody = encoded

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await URLSession.shared.data(for: request)
      } catch {
        lastTransportError = error
        if index < bases.count - 1 { continue }
        throw error
      }

      guard let http = response as? HTTPURLResponse else {
        let error = URLError(.badServerResponse)
        if index < bases.count - 1 {
          lastTransportError = error
          continue
        }
        throw error
      }

      if BackendConfig.shouldTryFallback(statusCode: http.statusCode), index < bases.count - 1 {
        continue
      }
      if (200..<300).contains(http.statusCode) {
        if let wrapped = try? JSONDecoder().decode(Envelope<ResponseBody>.self, from: data) {
          return wrapped.json.segments
        }
        return try JSONDecoder().decode(ResponseBody.self, from: data).segments
      }

      let message: String
      if let wrapped = try? JSONDecoder().decode(Envelope<ErrorBody>.self, from: data) {
        message = wrapped.json.error
      } else if let plain = try? JSONDecoder().decode(ErrorBody.self, from: data) {
        message = plain.error
      } else {
        message = "Субтитры временно недоступны."
      }
      throw NSError(
        domain: "Muwa.Subtitles",
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }

    if let lastTransportError { throw lastTransportError }
    throw URLError(.badServerResponse)
  }

  private func cacheURL(trackID: String) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appending(path: "muwa-subtitles-\(trackID).json")
  }

  private func loadCached(trackID: String) -> [SubtitleSegment]? {
    guard let url = cacheURL(trackID: trackID),
      let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode([SubtitleSegment].self, from: data),
      !decoded.isEmpty
    else { return nil }
    return decoded
  }

  private func saveCache(_ segments: [SubtitleSegment], trackID: String) {
    guard let url = cacheURL(trackID: trackID),
      let data = try? JSONEncoder().encode(segments)
    else { return }
    try? data.write(to: url, options: .atomic)
  }
}


@MainActor
final class AISubtitleManager: ObservableObject {
  @Published private(set) var document: AISubtitleDocument?
  @Published private(set) var translations: [String: AISubtitleTranslation] = [:]
  @Published private(set) var isRecognizing = false
  @Published private(set) var translatingLanguage: String?
  @Published private(set) var error: String?
  private var source: String?
  private var requestID = UUID()
  private var translationID = UUID()
  private var retryAfter = Date.distantPast

  func load(_ track: Track, retry: Bool = false) async {
    let key = track.audioURL.absoluteString
    if source == key && (document != nil || isRecognizing || (!retry && error != nil)) { return }
    if source == key && retry && Date() < retryAfter { return }
    let id = UUID(); requestID = id; translationID = UUID()
    source = key; document = nil; translations = [:]; error = nil; translatingLanguage = nil
    isRecognizing = true
    defer { if requestID == id { isRecognizing = false } }
    do {
      if let cached = await AISubtitleDisk.shared.load(key: key), let valid = try? cached.validated() {
        guard requestID == id, !Task.isCancelled else { return }
        document = valid; return
      }
      guard let src = track.cdnSourcePath, track.duration > 0, track.duration <= 600 else {
        throw AISubtitleAPIError(message: "AI-субтитры доступны для опубликованного аудио до 10 минут.", code: "UNSUPPORTED")
      }
      let result: AISubtitleDocument = try await request("subtitles/original", body: OriginalRequest(src: src, durationSeconds: track.duration))
      let valid = try result.validated()
      guard requestID == id, !Task.isCancelled else { return }
      document = valid
      await AISubtitleDisk.shared.save(valid, key: key)
    } catch {
      guard requestID == id else { return }
      if !Task.isCancelled { self.error = error.localizedDescription }
    }
  }

  func translate(_ language: AITranslationLanguage) async {
    guard language != .original, let doc = document, translations[language.rawValue] == nil else { return }
    guard Date() >= retryAfter else { return }
    let id = UUID(); translationID = id
    translatingLanguage = language.rawValue; error = nil
    defer { if translationID == id { translatingLanguage = nil } }
    do {
      let cacheKey = doc.id + "|" + language.rawValue
      let cached = await AISubtitleDisk.shared.translation(key: cacheKey)
      let result: AISubtitleTranslation
      if let cached { result = cached }
      else { result = try await request("subtitles/translate", body: TranslationRequest(documentId: doc.id, language: language.rawValue)) }
      guard result.documentId == doc.id, result.language == language.rawValue,
        Set(result.segments.keys) == Set(doc.segments.map(\.id)),
        result.segments.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
      else { throw URLError(.cannotParseResponse) }
      guard translationID == id, document?.id == doc.id, !Task.isCancelled else { return }
      translations[language.rawValue] = result
      await AISubtitleDisk.shared.saveTranslation(result, key: cacheKey)
    } catch {
      guard translationID == id, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }
  private struct OriginalRequest: Encodable { let src: String; let durationSeconds: Double }
  private struct TranslationRequest: Encodable { let documentId: String; let language: String }
  private func request<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
    // Follow the authenticated backend; never send a charged request to multiple backends.
    let preferred = UserDefaults.standard.string(forKey: "muwa.auth.preferredBackend")
    let base = BackendConfig.candidateAPIBaseURLs.first(where: { $0.absoluteString == preferred }) ?? BackendConfig.apiBaseURL
    var req = URLRequest(url: base.appending(path: "_api/" + path))
    req.httpMethod = "POST"; req.httpShouldHandleCookies = true
    req.timeoutInterval = 240
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(http.statusCode) else {
      let payload = try? JSONDecoder().decode(AISubtitleAPIError.self, from: data)
      if http.statusCode == 429 { retryAfter = Date().addingTimeInterval(60) }
      if http.statusCode == 409 { retryAfter = Date().addingTimeInterval(15) }
      throw payload ?? AISubtitleAPIError(message: "AI-субтитры временно недоступны. Обычные субтитры сохранены.", code: "HTTP_ERROR")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
}
private struct AISubtitleAPIError: Decodable, LocalizedError {
  let message: String
  let code: String?
  enum CodingKeys: String, CodingKey { case message = "error", code }
  var errorDescription: String? { message }
}
private actor AISubtitleDisk {
  static let shared = AISubtitleDisk()
  private func url(_ key: String) -> URL? {
    let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("muwa-ai-v2-" + hash + ".json")
  }
  func load(key: String) -> AISubtitleDocument? { read(key) }
  func translation(key: String) -> AISubtitleTranslation? { read(key) }
  func save(_ value: AISubtitleDocument, key: String) { write(value, key: key) }
  func saveTranslation(_ value: AISubtitleTranslation, key: String) { write(value, key: key) }
  private func read<T: Decodable>(_ key: String) -> T? {
    guard let url = url(key), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }
  private func write<T: Encodable>(_ value: T, key: String) {
    guard let url = url(key), let data = try? JSONEncoder().encode(value) else { return }
    try? data.write(to: url, options: .atomic)
  }
}
