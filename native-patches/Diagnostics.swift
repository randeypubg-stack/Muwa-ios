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

/// Local, bounded diagnostics. Never stores credentials, request bodies or user text.
@MainActor
final class Diagnostics: NSObject, ObservableObject, MXMetricManagerSubscriber {
  static let shared = Diagnostics()
  @Published private(set) var events: [DiagnosticEvent] = []
  @Published private(set) var systemReportCount = 0
  private let logger = Logger(subsystem: "app.muwa.nasheeds", category: "diagnostics")
  private let folder = URL.applicationSupportDirectory.appending(path: "Diagnostics")
  private var eventURL: URL { folder.appending(path: "events.json") }

  override private init() {
    super.init()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let data = try? Data(contentsOf: eventURL), let saved = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) {
      events = Array(saved.suffix(200))
    }
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
      .filter { $0.lastPathComponent != "events.json" }
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
    events = []
    for url in reports() + [eventURL] { try? FileManager.default.removeItem(at: url) }
    systemReportCount = 0
  }
}
