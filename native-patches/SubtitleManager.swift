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

  private var tasks: [String: Task<Void, Never>] = [:]
  private var revisions: [String: Int] = [:]
  private func cacheID(_ track: Track) -> String { (track.captionsRevision ?? 0) > 0 ? "\(track.id)-r\(track.captionsRevision!)" : track.id }

  func state(for track: Track) -> LoadState {
    stateByTrack[track.id] ?? .idle
  }

  func segments(for track: Track) -> [SubtitleSegment] {
    (revisions[track.id] == (track.captionsRevision ?? 0) ? segmentsByTrack[track.id] : nil) ?? loadCached(trackID: cacheID(track)) ?? []
  }

  func load(for track: Track) {
    let revision = track.captionsRevision ?? 0
    if revisions[track.id] != revision {
      tasks[track.id]?.cancel(); tasks[track.id] = nil; segmentsByTrack[track.id] = nil
      revisions[track.id] = revision
    }
    if segmentsByTrack[track.id] != nil { return }
    if let cached = loadCached(trackID: cacheID(track)), !cached.isEmpty {
      segmentsByTrack[track.id] = cached
      stateByTrack[track.id] = .ready
      return
    }
    guard tasks[track.id] == nil else { return }
    stateByTrack[track.id] = .loading
    tasks[track.id] = Task { [weak self] in
      guard let self else { return }
      defer { if self.revisions[track.id] == revision { self.tasks[track.id] = nil } }
      do {
        let result = try await self.fetchPublished(track: track)
        guard !Task.isCancelled, self.revisions[track.id] == revision else { return }
        self.segmentsByTrack[track.id] = result
        self.stateByTrack[track.id] = .ready
        self.saveCache(result, trackID: self.cacheID(track))
      } catch {
        guard !Task.isCancelled, self.revisions[track.id] == revision else { return }
        Diagnostics.shared.record("subtitles", error: error)
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

  private func fetchPublished(track: Track) async throws -> [SubtitleSegment] {
    var parts = URLComponents(url: BackendConfig.apiBaseURL.appending(path: "_api/catalog/captions"), resolvingAgainstBaseURL: false)!
    parts.queryItems = [URLQueryItem(name: "trackId", value: track.id)]
    var request = URLRequest(url: parts.url!); request.timeoutInterval = 20
    do {
      let (data, response) = try await BackendConfig.boundedData(for: request)
      if (response as? HTTPURLResponse)?.statusCode == 200 {
        let result = try JSONDecoder().decode(ResponseBody.self, from: data)
        // A positive revision also represents an intentional removal of captions.
        if (track.captionsRevision ?? 0) > 0 || !result.segments.isEmpty { return result.segments }
      }
    } catch {
      if Task.isCancelled { throw CancellationError() }
      if (track.captionsRevision ?? 0) > 0 { throw error }
    }
    if (track.captionsRevision ?? 0) > 0 { throw URLError(.badServerResponse) }
    guard let src = track.cdnSourcePath else { return [] }
    return try await fetch(track: track, src: src)
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
        (data, response) = try await BackendConfig.boundedData(for: request)
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
  @Published private(set) var publishedSource: String?
  var availableLanguages: [AITranslationLanguage] {
    publishedSource == nil ? AITranslationLanguage.allCases
      : AITranslationLanguage.allCases.filter { $0 == .original || translations[$0.rawValue] != nil }
  }
  private var source: String?
  private var requestID = UUID()
  private var translationID = UUID()
  private var retryAfter = Date.distantPast

  func load(_ track: Track, retry: Bool = false) async {
    let isCatalog = track.cdnSourcePath == nil
    let key = isCatalog ? "\(track.id)|\(track.audioURL.absoluteString)|r\(track.captionsRevision ?? 0)" : track.audioURL.absoluteString
    if source == key && (isRecognizing || (!retry && (document != nil || error != nil))) { return }
    if source == key && retry && Date() < retryAfter { return }
    let id = UUID(); requestID = id; translationID = UUID()
    if source != key || !retry { document = nil; translations = [:]; publishedSource = nil }
    source = key; error = nil; translatingLanguage = nil
    isRecognizing = true
    defer { if requestID == id { isRecognizing = false } }
    do {
      if isCatalog {
        var parts = URLComponents(url: BackendConfig.apiBaseURL.appending(path: "_api/catalog/captions"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "trackId", value: track.id)]
        var req = URLRequest(url: parts.url!); req.timeoutInterval = 20
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await BackendConfig.boundedData(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(PublishedCaptions.self, from: data)
        guard requestID == id, !Task.isCancelled else { return }
        publishedSource = payload.source
        guard !payload.segments.isEmpty else {
          document = nil; translations = [:]
          throw AISubtitleAPIError(message: "Текст ещё готовится или ожидает проверки владельцем. Попробуйте обновить позже.", code: "NOT_READY")
        }
        installPublished(track: track, captions: payload.segments, revision: payload.revision)
        return
      }
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
      if !Task.isCancelled, document == nil { self.error = error.localizedDescription }
    }
  }

  func translate(_ language: AITranslationLanguage) async {
    guard language != .original, let doc = document, translations[language.rawValue] == nil else { return }
    guard publishedSource == nil else { return } // Local captions never start a paid provider request.
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
  private struct PublishedCaptions: Decodable {
    let segments: [SubtitleSegment]; let source: String; let revision: Int
  }
  func usePublishedFallback(_ track: Track, captions: [SubtitleSegment]) {
    guard document == nil, !captions.isEmpty else { return }
    publishedSource = "published"
    installPublished(track: track, captions: captions, revision: track.captionsRevision ?? 0)
    error = nil
  }
  private func installPublished(track: Track, captions: [SubtitleSegment], revision: Int) {
    guard let doc = try? AISubtitleDocument.published(trackID: track.id, revision: revision, captions: captions) else { return }
    document = doc
    error = nil
    translations = [:]
    for language in [SubtitleLanguage.russian, .english] where language.rawValue.lowercased() != doc.language {
      let values = Dictionary(uniqueKeysWithValues: captions.enumerated().compactMap { index, caption -> (String, String)? in
        let value = caption.text(for: language).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : ("s\(index)", value)
      })
      if Set(values.keys) == Set(doc.segments.map(\.id)) {
        translations[language.rawValue.lowercased()] = AISubtitleTranslation(documentId: doc.id, language: language.rawValue.lowercased(), segments: values)
      }
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
    let (data, response) = try await BackendConfig.boundedData(for: req)
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
