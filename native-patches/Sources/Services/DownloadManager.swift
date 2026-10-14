import Foundation
import Combine
import AVFoundation

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
  static let maximumBytes: Int64 = 100 * 1024 * 1024
  private let lock = NSLock()
  private var oversized = false
  var exceededLimit: Bool { lock.lock(); defer { lock.unlock() }; return oversized }
  let onProgress: (Double) -> Void
  init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    if totalBytesWritten > Self.maximumBytes || totalBytesExpectedToWrite > Self.maximumBytes {
      lock.lock(); oversized = true; lock.unlock()
      downloadTask.cancel()
      return
    }
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
  private var extensions: [String: String]
  private static let extensionsKey = "muwa.native.download.extensions.v1"
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
    extensions = (defaults.dictionary(forKey: Self.extensionsKey) as? [String: String] ?? [:])
      .filter { ["mp3", "m4a", "wav", "aac", "ogg"].contains($0.value) }
    for id in downloadedIDs where sources[id] == nil {
      sources[id] = Track.track(id: id)?.audioURL.absoluteString
    }
    defaults.set(sources, forKey: Self.sourcesKey)
    try? fileManager.createDirectory(at: self.folder, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    var url = self.folder; try? url.setResourceValues(values)
    downloadedIDs = downloadedIDs.filter { id in
      Track.track(id: id).map { track in fileManager.fileExists(atPath: self.destination(track).path) } ?? false
    }
    defaults.set(Array(downloadedIDs), forKey: Self.key)
  }

  var storageBytes: Int64 {
    downloadedIDs.compactMap { Track.track(id: $0) }.compactMap { localURL(for: $0) }.reduce(0) { count, url in
      count + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  private func destination(_ track: Track, fileExtension: String? = nil) -> URL {
    // Catalog IDs are stable; reject path components if external catalogs are introduced.
    let safeID = track.id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    let legacyExtension = ["mp3", "m4a", "wav", "aac", "ogg"].contains(track.audioURL.pathExtension.lowercased()) ? track.audioURL.pathExtension.lowercased() : "mp3"
    let ext = fileExtension ?? extensions[track.id] ?? legacyExtension
    return folder.appendingPathComponent("\(safeID).\(ext)")
  }

  func localURL(for track: Track) -> URL? {
    guard isDownloaded(track) else { return nil }
    return destination(track)
  }
  func isDownloaded(_ track: Track) -> Bool {
    downloadedIDs.contains(track.id) && sources[track.id] == track.audioURL.absoluteString && fileManager.fileExists(atPath: destination(track).path)
  }

  func download(_ track: Track) async throws {
    if isDownloaded(track) { return }
    if let existing = tasks[track.id] { try await existing.value; return }
    guard Self.allowedSource(track.audioURL), tasks.count < 3 else { throw URLError(.resourceUnavailable) }
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
        var request = URLRequest(url: track.audioURL)
        request.timeoutInterval = 60
        let result: (URL, URLResponse)
        do { result = try await self.session.download(for: request, delegate: delegate) }
        catch { if delegate.exceededLimit { throw URLError(.dataLengthExceedsMaximum) }; throw error }
        let (temp, response) = result
        defer { try? self.fileManager.removeItem(at: temp) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
          !(http.mimeType ?? "").contains("html"), !(http.mimeType ?? "").contains("json") else { throw URLError(.badServerResponse) }
        let size = (try temp.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size > 0 else { throw URLError(.zeroByteResource) }
        guard size <= DownloadProgressDelegate.maximumBytes,
          http.url.map(Self.allowedSource) == true,
          response.expectedContentLength < 0 || response.expectedContentLength == Int64(size) || http.value(forHTTPHeaderField: "Content-Encoding") != nil else { throw URLError(.badServerResponse) }
        // URLSession supplies an extensionless .tmp URL. AVFoundation may reject
        // playable bytes at that URL (-1016), particularly M4A. Stage the file
        // with its verified container extension before asking AVFoundation.
        let ext = try Self.audioExtension(temp)
        let staged = self.folder.appendingPathComponent(".download-\(UUID()).\(ext)")
        try self.fileManager.moveItem(at: temp, to: staged)
        defer { try? self.fileManager.removeItem(at: staged) }
        guard try await AVURLAsset(url: staged).load(.isPlayable) else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        let destination = self.destination(track, fileExtension: ext)
        if self.fileManager.fileExists(atPath: destination.path) {
          _ = try self.fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
          try self.fileManager.moveItem(at: staged, to: destination)
        }
        self.extensions[track.id] = ext
        self.defaults.set(self.extensions, forKey: Self.extensionsKey)
        self.sources[track.id] = track.audioURL.absoluteString
        self.defaults.set(self.sources, forKey: Self.sourcesKey)
        self.downloadedIDs.insert(track.id)
        self.defaults.set(Array(self.downloadedIDs), forKey: Self.key)
      } catch {
        if !(error is CancellationError), (error as NSError).code != NSURLErrorCancelled {
          self.lastError = Self.message(for: error)
          Diagnostics.shared.record("download", error: error)
        }
        throw error
      }
    }
    tasks[track.id] = operation
    try await operation.value
  }

  func cancel(_ track: Track) { tasks[track.id]?.cancel() }
  // Inspect bytes rather than the signed/API URL, which has no file suffix.
  private static func allowedSource(_ url: URL) -> Bool {
    #if MUWA_TEST_FIXTURES
    if url.scheme == "http", url.host == "127.0.0.1" { return true }
    #endif
    return url.scheme == "https"
  }
  private static func audioExtension(_ file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let header = [UInt8](try handle.read(upToCount: 16) ?? Data())
    if header.starts(with: [0x49, 0x44, 0x33]) { return "mp3" }
    if header.count >= 12, Array(header[0..<4]) == Array("RIFF".utf8), Array(header[8..<12]) == Array("WAVE".utf8) { return "wav" }
    if header.count >= 12, Array(header[4..<8]) == Array("ftyp".utf8) { return "m4a" }
    if header.starts(with: Array("OggS".utf8)) { return "ogg" }
    if header.count >= 2, header[0] == 0xff, header[1] & 0xe0 == 0xe0 {
      return header[1] & 0x06 == 0 ? "aac" : "mp3"
    }
    throw URLError(.cannotDecodeContentData)
  }
  static func message(for error: Error) -> String {
    switch (error as NSError).code {
    case NSURLErrorCannotDecodeContentData: return "Сервер вернул неподдерживаемый аудиофайл. Попробуйте другой нашид."
    case NSURLErrorDataLengthExceedsMaximum: return "Размер файла превышает 100 МБ."
    case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut: return "Проверьте подключение к интернету и повторите скачивание."
    default: return "Не удалось сохранить аудио. Повторите скачивание."
    }
  }
  func remove(_ track: Track) throws {
    guard tasks[track.id] == nil else { cancel(track); return }
    let id = track.id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    // Remove the saved version as well when a remote edit changes its extension.
    for url in try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.deletingPathExtension().lastPathComponent == id {
      try fileManager.removeItem(at: url)
    }
    sources.removeValue(forKey: track.id)
    extensions.removeValue(forKey: track.id)
    defaults.set(extensions, forKey: Self.extensionsKey)
    defaults.set(sources, forKey: Self.sourcesKey)
    downloadedIDs.remove(track.id)
    defaults.set(Array(downloadedIDs), forKey: Self.key)
  }
}
