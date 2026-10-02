import Foundation
import Combine

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
  let onProgress: (Double) -> Void
  init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard totalBytesExpectedToWrite > 0 else { return }
    onProgress(min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))))
  }
}

@MainActor
final class DownloadManager: ObservableObject {
  @Published private(set) var downloadedIDs: Set<String>
  @Published private(set) var downloadingIDs: Set<String> = []
  @Published private(set) var progress: [String: Double] = [:]
  @Published private(set) var lastError: String?
  private var sources: [String: String]
  private static let sourcesKey = "muwa.native.download.sources.v1"
  private let defaults: UserDefaults
  private let fileManager: FileManager
  private var tasks: [String: Task<Void, Error>] = [:]
  private let session: URLSession
  private let folder: URL
  private static let key = "muwa.native.downloaded"

  init(defaults: UserDefaults = .standard, fileManager: FileManager = .default, folder: URL? = nil, session: URLSession = .shared) {
    self.defaults = defaults
    self.fileManager = fileManager
    self.session = session
    self.folder = folder ?? URL.applicationSupportDirectory.appending(path: "OfflineAudio")
    downloadedIDs = Set(defaults.stringArray(forKey: Self.key) ?? [])
    sources = defaults.dictionary(forKey: Self.sourcesKey) as? [String: String] ?? [:]
    for id in downloadedIDs where sources[id] == nil {
      sources[id] = Track.bundledCatalog.first(where: { $0.id == id })?.audioURL.absoluteString ?? Track.track(id: id)?.audioURL.absoluteString
    }
    defaults.set(sources, forKey: Self.sourcesKey)
    try? fileManager.createDirectory(at: self.folder, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    var url = self.folder; try? url.setResourceValues(values)
    downloadedIDs = downloadedIDs.filter { id in
      Track.track(id: id).map { track in fileManager.fileExists(atPath: Self.destination(track, folder: self.folder).path) } ?? false
    }
    defaults.set(Array(downloadedIDs), forKey: Self.key)
  }

  var storageBytes: Int64 {
    downloadedIDs.compactMap { Track.track(id: $0) }.compactMap { localURL(for: $0) }.reduce(0) { count, url in
      count + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  private static func destination(_ track: Track, folder: URL) -> URL {
    // Catalog IDs are stable; reject path components if external catalogs are introduced.
    let safeID = track.id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    let ext = track.audioURL.pathExtension.isEmpty ? "mp3" : track.audioURL.pathExtension
    return folder.appendingPathComponent("\(safeID).\(ext)")
  }

  func localURL(for track: Track) -> URL? {
    guard isDownloaded(track) else { return nil }
    return Self.destination(track, folder: folder)
  }
  func isDownloaded(_ track: Track) -> Bool {
    downloadedIDs.contains(track.id) && sources[track.id] == track.audioURL.absoluteString && fileManager.fileExists(atPath: Self.destination(track, folder: folder).path)
  }

  func download(_ track: Track) async throws {
    if isDownloaded(track) { return }
    if let existing = tasks[track.id] { try await existing.value; return }
    downloadingIDs.insert(track.id)
    progress[track.id] = 0
    lastError = nil
    let operation = Task { @MainActor in
      defer { self.downloadingIDs.remove(track.id); self.progress.removeValue(forKey: track.id); self.tasks.removeValue(forKey: track.id) }
      do {
        let delegate = DownloadProgressDelegate { value in
          Task { @MainActor in
            if self.downloadingIDs.contains(track.id) { self.progress[track.id] = value }
          }
        }
        let (temp, response) = try await self.session.download(from: track.audioURL, delegate: delegate)
        defer { try? self.fileManager.removeItem(at: temp) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          !(http.mimeType ?? "").contains("html"), !(http.mimeType ?? "").contains("json") else { throw URLError(.badServerResponse) }
        let size = (try temp.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size > 0 else { throw URLError(.zeroByteResource) }
        let destination = Self.destination(track, folder: self.folder)
        if self.fileManager.fileExists(atPath: destination.path) { try self.fileManager.removeItem(at: destination) }
        try self.fileManager.moveItem(at: temp, to: destination)
        self.sources[track.id] = track.audioURL.absoluteString
        self.defaults.set(self.sources, forKey: Self.sourcesKey)
        self.downloadedIDs.insert(track.id)
        self.defaults.set(Array(self.downloadedIDs), forKey: Self.key)
      } catch {
        if !(error is CancellationError), (error as NSError).code != NSURLErrorCancelled {
          self.lastError = error.localizedDescription
          Diagnostics.shared.record("download", error: error)
        }
        throw error
      }
    }
    tasks[track.id] = operation
    try await operation.value
  }

  func cancel(_ track: Track) { tasks[track.id]?.cancel() }
  func remove(_ track: Track) throws {
    guard tasks[track.id] == nil else { cancel(track); return }
    let id = track.id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    // Remove the saved version as well when a remote edit changes its extension.
    for url in try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.deletingPathExtension().lastPathComponent == id {
      try fileManager.removeItem(at: url)
    }
    sources.removeValue(forKey: track.id)
    defaults.set(sources, forKey: Self.sourcesKey)
    downloadedIDs.remove(track.id)
    defaults.set(Array(downloadedIDs), forKey: Self.key)
  }
}
