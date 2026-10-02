import Foundation

@main
struct DownloadChecks {
  @MainActor static func main() throws {
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
    try existing.remove(track)
    precondition(existing.localURL(for: track) == nil && existing.storageBytes == 0)
    precondition(DownloadManager(defaults: defaults, folder: folder).downloadedIDs.isEmpty, "Deleted download reappeared after restart")
    print("PASS: offline file validation, size accounting, deletion and restart")
  }
}
