import Foundation
import MetricKit
import OSLog
import SwiftUI

struct DiagnosticEvent: Codable, Identifiable {
  let id: UUID
  let date: Date
  let area: String
  let domain: String
  let code: Int
}

/// Bounded diagnostics. Remote reports are opt-in and contain only fixed error categories.
@MainActor
final class Diagnostics: NSObject, ObservableObject, MXMetricManagerSubscriber {
  static let shared = Diagnostics()
  @Published private(set) var events: [DiagnosticEvent] = []
  @Published private(set) var systemReportCount = 0
  private let logger = Logger(subsystem: "app.muwa.nasheeds", category: "diagnostics")
  private let folder = URL.applicationSupportDirectory.appending(path: "Diagnostics")
  @Published var remoteEnabled = UserDefaults.standard.bool(forKey: "muwa.diagnostics.remote") {
    didSet { UserDefaults.standard.set(remoteEnabled, forKey: "muwa.diagnostics.remote"); if !remoteEnabled { pending = []; persistPending(); uploadRevision = UUID(); uploadTask?.cancel(); uploadTask = nil } else { flush() } }
  }
  private struct RemoteEvent: Codable { let id: UUID; let occurredAt: String; let area: String; let errorType: String; let errorCode: Int }
  private struct PendingReport: Codable { let accountId: Int?; let events: [RemoteEvent] }
  private var accountId: Int?
  private var accountReady = false
  private var pending: [RemoteEvent] = []
  private var uploadTask: Task<Void, Never>?
  private var uploadRevision = UUID()
  private var nextAttempt = Date.distantPast
  private var remoteURL: URL { folder.appending(path: "pending-remote.json") }
  private var eventURL: URL { folder.appending(path: "events.json") }

  override private init() {
    super.init()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let data = try? Data(contentsOf: eventURL), let saved = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) {
      events = Array(saved.suffix(200))
    }
    if let data = try? Data(contentsOf: remoteURL), let saved = try? JSONDecoder().decode(PendingReport.self, from: data) { accountId = saved.accountId; pending = Array(saved.events.suffix(200)) }
    if !remoteEnabled { pending = [] }
    systemReportCount = reports().count
    MXMetricManager.shared.add(self)
  }

  func record(_ area: String, error: Error) {
    if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return }
    let value = error as NSError
    let safeDomain = String(value.domain.prefix(100))
    logger.error("Failure in \(area, privacy: .public): \(safeDomain, privacy: .public) / \(value.code)")
    events.append(DiagnosticEvent(id: UUID(), date: Date(), area: area, domain: safeDomain, code: value.code))
    events = Array(events.suffix(200))
    if let data = try? JSONEncoder().encode(events) { try? data.write(to: eventURL, options: .atomic) }
    if remoteEnabled && accountReady && accountId != nil {
      let allowed = ["catalog", "download", "playback", "audio-session", "premium", "subtitles", "publication", "controller", "session-storage", "uncaught"]
      let safeArea = area.hasPrefix("auth") ? "auth" : allowed.contains(area) ? area : "other"
      let type = value.domain == NSURLErrorDomain ? "network" : value.domain == NSCocoaErrorDomain ? "storage" : value.domain == "AVFoundationErrorDomain" ? "playback" : "unknown"
      pending.append(RemoteEvent(id: events.last!.id, occurredAt: ISO8601DateFormatter().string(from: .now), area: safeArea, errorType: type, errorCode: Int(Int32(clamping: value.code))))
      pending = Array(pending.suffix(200)); persistPending(); flush()
    }
  }

  func setAccount(_ id: Int?) {
    accountReady = true
    guard accountId != id else { flush(); return }
    uploadRevision = UUID(); uploadTask?.cancel(); uploadTask = nil; pending = []; accountId = id; nextAttempt = .distantPast; persistPending()
  }
  private func persistPending() {
    if let data = try? JSONEncoder().encode(PendingReport(accountId: accountId, events: pending)) { try? data.write(to: remoteURL, options: .atomic) }
  }
  func flush() {
    guard remoteEnabled, accountReady, let id = accountId, !pending.isEmpty, uploadTask == nil, Date() >= nextAttempt else { return }
    let revision = uploadRevision
    let batch = Array(pending.prefix(20))
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "1.4.0"
    let build = info["CFBundleVersion"] as? String ?? "39"
    let batchData = (try? JSONEncoder().encode(batch)) ?? Data("[]".utf8)
    guard let rows = try? JSONSerialization.jsonObject(with: batchData) else { return }
    let body: [String: Any] = ["platform":"iOS", "version":version, "build":build, "events":rows]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
    uploadTask = Task {
      defer { if uploadRevision == revision { uploadTask = nil } }
      var request = URLRequest(url: BackendConfig.apiBaseURL.appending(path: "_api/diagnostics/events"))
      request.httpMethod = "POST"; request.httpBody = data; request.timeoutInterval = 20
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard !Task.isCancelled, uploadRevision == revision, accountId == id, remoteEnabled else { return }
        if (response as? HTTPURLResponse)?.statusCode == 200 {
          let ids = Set(batch.map(\.id)); pending.removeAll { ids.contains($0.id) }; persistPending(); nextAttempt = Date().addingTimeInterval(30)
        } else { nextAttempt = Date().addingTimeInterval((response as? HTTPURLResponse)?.statusCode == 429 ? 3600 : 60) }
      } catch { if uploadRevision == revision && accountId == id { nextAttempt = Date().addingTimeInterval(60) } }
    }
  }

  nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
    let data = payloads.map { $0.jsonRepresentation() }
    Task { @MainActor in self.saveReports(data, kind: "diagnostic") }
  }

  nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
    let data = payloads.map { $0.jsonRepresentation() }
    Task { @MainActor in self.saveReports(data, kind: "metric") }
  }

  private func reports() -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
      .filter { $0.lastPathComponent != "events.json" && $0.lastPathComponent != "pending-remote.json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  private func saveReports(_ data: [Data], kind: String) {
    for item in data {
      let name = "\(Date().timeIntervalSince1970)-\(kind)-\(UUID()).json"
      try? item.write(to: folder.appending(path: name), options: .atomic)
    }
    let saved = reports()
    for url in saved.dropLast(10) { try? FileManager.default.removeItem(at: url) }
    systemReportCount = min(saved.count, 10)
  }

  func export() throws -> URL {
    // MetricKit crash/hang payloads are OS supplied; export only on an explicit share action.
    let reports = reports().compactMap { try? Data(contentsOf: $0) }.compactMap { try? JSONSerialization.jsonObject(with: $0) }
    let eventData = try JSONEncoder().encode(events)
    let info = Bundle.main.infoDictionary ?? [:]
    let body: [String: Any] = ["platform": "iOS", "version": info["CFBundleShortVersionString"] ?? "",
      "build": info["CFBundleVersion"] ?? "", "errors": try JSONSerialization.jsonObject(with: eventData), "systemReports": reports]
    let url = URL.temporaryDirectory.appending(path: "Muwa-diagnostics.json")
    try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    return url
  }

  func clear() {
    events = []; pending = []; persistPending(); uploadRevision = UUID(); uploadTask?.cancel(); uploadTask = nil
    for url in reports() + [eventURL] { try? FileManager.default.removeItem(at: url) }
    systemReportCount = 0
  }
}
