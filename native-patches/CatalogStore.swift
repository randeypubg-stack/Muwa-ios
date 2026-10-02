import Combine
import Foundation

/// One catalogue owner. The bundled seven tracks bootstrap the first offline launch;
/// a successfully fetched empty catalogue remains empty, rather than resurrecting tracks.
@MainActor
final class CatalogStore: ObservableObject {
  static let shared = CatalogStore()
  @Published private(set) var tracks: [Track]
  private var known: [String: Track]
  private var refreshing = false
  private var lastRefresh = Date.distantPast
  private let session: URLSession
  private let baseURL: URL
  private let defaults: UserDefaults
  private let cacheKey = "muwa.native.catalog.v1"
  private struct Cache: Codable { let tracks: [Track]; let known: [Track] }
  private struct Document: Decodable { let version: Int; let tracks: [Item] }
  private struct Item: Decodable {
    let id: String; let title: String; let artist: String; let duration: Double
    let audio: String; let artwork: String?; let captionsRevision: Int
  }

  init(defaults: UserDefaults = .standard, session: URLSession = .shared, baseURL: URL = BackendConfig.apiBaseURL) {
    self.session = session; self.baseURL = baseURL
    self.defaults = defaults
    let cached = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    tracks = cached?.tracks ?? Track.bundledCatalog
    known = Dictionary((cached?.known ?? Track.bundledCatalog).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
  }

  func track(id: String) -> Track? { known[id] }

  func refresh(force: Bool = false) async {
    guard !refreshing, (force || Date().timeIntervalSince(lastRefresh) >= 30) else { return }
    refreshing = true
    defer { refreshing = false }
    do {
      var request = URLRequest(url: baseURL.appending(path: "_api/catalog/tracks"))
      request.timeoutInterval = 20
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 10 * 1024 * 1024 else { throw URLError(.badServerResponse) }
      let document = try JSONDecoder().decode(Document.self, from: data)
      guard document.version == 1, document.tracks.count <= 10000 else { throw URLError(.cannotParseResponse) }
      var ids = Set<String>()
      let values = try document.tracks.map { row -> Track in
        guard row.id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              ids.insert(row.id).inserted, !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              row.duration.isFinite, row.duration > 0, row.duration <= 86400,
              let url = URL(string: row.audio, relativeTo: baseURL)?.absoluteURL,
              url.scheme == "https", row.captionsRevision >= 0 else { throw URLError(.cannotParseResponse) }
        let artwork = row.artwork.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        guard artwork == nil || artwork?.scheme == "https" else { throw URLError(.cannotParseResponse) }
        return Track(id: row.id, title: row.title, artist: row.artist, duration: row.duration, artworkURL: artwork, audioURL: url, captionsRevision: row.captionsRevision)
      }
      guard !Task.isCancelled else { return }
      // Keep metadata for downloaded/queued tracks; remote archive never destroys user IDs or interrupts AVPlayer.
      values.forEach { known[$0.id] = $0 }
      if tracks != values { tracks = values }
      if let encoded = try? JSONEncoder().encode(Cache(tracks: values, known: Array(known.values))) { defaults.set(encoded, forKey: cacheKey) }
      lastRefresh = Date()
    } catch {
      guard !Task.isCancelled else { return }
      Diagnostics.shared.record("catalog", error: error)
      // Network failure keeps the last valid snapshot. Refresh does not select or autoplay a track.
    }
  }
}
