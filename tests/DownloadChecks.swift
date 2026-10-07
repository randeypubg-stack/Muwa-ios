import Foundation

@main
struct DownloadChecks {
  @MainActor static func main() async throws {
    CatalogStore.shared.installReviewTracks(Track.reviewCatalog)
    let suite = "muwa.download.audit.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let folder = URL.temporaryDirectory.appendingPathComponent(suite)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let track = Track.catalog[0]
    defaults.set([track.id], forKey: "muwa.native.downloaded")
    let missing = DownloadManager(defaults: defaults, folder: folder)
    precondition(missing.localURL(for: track) == nil && !missing.isDownloaded(track), "Missing offline file was offered for playback")
    let file = folder.appendingPathComponent("\(track.id).\(track.audioURL.pathExtension)")
    try Data([1, 2, 3]).write(to: file)
    defaults.set([track.id], forKey: "muwa.native.downloaded")
    let existing = DownloadManager(defaults: defaults, folder: folder)
    precondition(existing.localURL(for: track) == file && existing.storageBytes == 3)
    let replacement = Track(id:track.id,title:track.title,artist:track.artist,duration:track.duration,artworkURL:track.artworkURL,audioURL:URL(string:"https://muwa-app.floot.app/replaced.mp3")!)
    precondition(existing.localURL(for:replacement) == nil, "Old audio was presented as a replaced source")
    precondition(existing.localURL(for:track) == file, "Replacing remote metadata erased a downloaded file")
    try existing.remove(track)
    precondition(existing.localURL(for: track) == nil && existing.storageBytes == 0)
    precondition(DownloadManager(defaults: defaults, folder: folder).downloadedIDs.isEmpty, "Deleted download reappeared after restart")
    if CommandLine.arguments.count > 1 {
      let base = URL(string: CommandLine.arguments[1])!
      for ext in ["mp3", "m4a", "wav"] {
        let remote = base.appending(path: "media").appending(queryItems: [URLQueryItem(name: "format", value: ext)])
        let value = Track(id: "test-\(ext)", title: "Fixture", artist: "Muwa", duration: 1, artworkURL: nil, audioURL: remote)
        CatalogStore.shared.installReviewTracks([value])
        let manager = DownloadManager(defaults: defaults, folder: folder)
        try await manager.download(value)
        guard let saved = manager.localURL(for: value) else { preconditionFailure("Playable download was not registered") }
        precondition(saved.pathExtension == ext, "Container suffix lost for a catalog URL without an extension")
        precondition(manager.progress.isEmpty && manager.downloadingIDs.isEmpty)
        let restarted = DownloadManager(defaults: defaults, folder: folder)
        precondition(restarted.localURL(for: value) == saved, "Offline container type lost after restart")
        try restarted.remove(value)
        precondition(!FileManager.default.fileExists(atPath: saved.path))
      }
      let invalid = Track(id: "invalid", title: "Invalid", artist: "Muwa", duration: 1, artworkURL: nil, audioURL: base.appending(path: "invalid-audio"))
      let manager = DownloadManager(defaults: defaults, folder: folder)
      do { try await manager.download(invalid); preconditionFailure("Non-audio response was registered offline") }
      catch { precondition(manager.localURL(for: invalid) == nil) }
      precondition(manager.progress.isEmpty && manager.downloadingIDs.isEmpty)
      let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path)
      precondition(remaining.isEmpty, "Failed download left a temporary file")
    }
    print("PASS: offline file validation, size accounting, deletion and restart")
  }
}
