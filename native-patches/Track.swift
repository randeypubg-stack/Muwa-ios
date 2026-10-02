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

  static let bundledCatalog: [Track] = [
    Track(
      id: "muwa-01",
      title: "Muwa Nasheeds",
      artist: "t.me/muwa144",
      duration: 297,
      artworkURL: URL(string: "https://muwa-app.floot.app/_cdn/static/muwa-cover-1.jpg"),
      audioURL: URL(
        string:
          "https://muwa-app.floot.app/_cdn/static/0da0908a-391c-4eac-9953-e5ed5c223b67-muwa_track_01.mp3"
      )!
    ),
    Track(
      id: "muwa-02",
      title: "Muwa Nasheed",
      artist: "t.me/muwa144",
      duration: 113,
      artworkURL: URL(string: "https://muwa-app.floot.app/_cdn/static/muwa-cover-2.jpg"),
      audioURL: URL(
        string:
          "https://muwa-app.floot.app/_cdn/static/a8fe3a89-66d5-4f3b-8eb6-52e0cce44bc2-muwa_track_02.mp3"
      )!
    ),
    Track(
      id: "muwa-03",
      title: "درب الفداء",
      artist: "t.me/muwa144",
      duration: 153,
      artworkURL: URL(string: "https://muwa-app.floot.app/_cdn/static/muwa-cover-3.jpg"),
      audioURL: URL(
        string:
          "https://muwa-app.floot.app/_cdn/static/36e59615-620c-435f-9a2a-e17925f87440-muwa_track_03.mp3"
      )!
    ),
    Track(
      id: "muwa-04",
      title: "Muwa Nasheed · 71s",
      artist: "t.me/muwa144",
      duration: 72,
      artworkURL: URL(string: "https://muwa-app.floot.app/_cdn/static/muwa-cover-4.jpg"),
      audioURL: URL(
        string:
          "https://muwa-app.floot.app/_cdn/static/cf558c26-4b41-4125-934f-97b20cb4701f-muwa_track_04.mp3"
      )!
    ),
    Track(
      id: "muwa-05",
      title: "Muwa Nasheeds 2",
      artist: "t.me/muwa144",
      duration: 162,
      artworkURL: URL(string: "https://muwa-app.floot.app/_cdn/static/muwa-cover-5.jpg"),
      audioURL: URL(
        string:
          "https://muwa-app.floot.app/_cdn/static/cb3ff162-edc5-4549-b809-06ae6be55159-muwa_track_05.mp3"
      )!
    ),
    Track(
      id: "muwa-06",
      title: "تقدم اخيا لسود الجبال",
      artist: "t.me/muwa144",
      duration: 223,
      artworkURL: URL(string: "https://muwa-app.floot.app/_cdn/static/muwa-cover-6.jpg"),
      audioURL: URL(
        string:
          "https://muwa-app.floot.app/_cdn/static/33b5cfd2-c8a5-4dda-8eec-1a9418926655-muwa_track_06.mp3"
      )!
    ),
    Track(
      id: "muwa-07",
      title: "Muwa nasheed",
      artist: "—",
      duration: 314,
      artworkURL: URL(string: "https://muwa-app.floot.app/_cdn/static/muwa-cover-7.jpg"),
      audioURL: URL(
        string:
          "https://muwa-app.floot.app/_cdn/static/87fb03cd-8f9d-4767-bb22-db0d3e4e7b80-muwa_track_07.mp3"
      )!
    ),
  ]

  @MainActor static func track(id: String) -> Track? {
    CatalogStore.shared.track(id: id)
  }
}
