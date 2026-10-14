import Foundation

struct Track: Identifiable, Hashable, Codable, Sendable {
  let id: String
  let title: String
  let artist: String
  let duration: TimeInterval
  let artworkURL: URL?
  let captionsRevision: Int?
  let audioURL: URL

  init(id: String, title: String, artist: String, duration: TimeInterval, artworkURL: URL?, audioURL: URL, captionsRevision: Int? = nil) {
    self.id = id; self.title = title; self.artist = artist; self.duration = duration
    self.artworkURL = artworkURL; self.audioURL = audioURL; self.captionsRevision = captionsRevision
  }

  var cdnSourcePath: String? {
    let path = audioURL.path
    return path.hasPrefix("/_cdn/static/") ? path : nil
  }

  var durationText: String {
    let value = max(0, Int(duration.rounded()))
    return String(format: "%d:%02d", value / 60, value % 60)
  }

  @MainActor static var catalog: [Track] { CatalogStore.shared.tracks }



  @MainActor static func track(id: String) -> Track? {
    CatalogStore.shared.track(id: id)
  }
}
