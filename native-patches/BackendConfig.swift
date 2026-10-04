import Foundation

enum BackendConfig {
  static let productionAPIBaseURL = URL(string: "https://93.188.187.96")!
  static let apiBaseURL = productionAPIBaseURL
  static let candidateAPIBaseURLs = [apiBaseURL]
  // Cleanup only for cookies left by older versions. Never used for requests.
  static let sessionCleanupHosts = [
    "93.188.187.96",
    "muwa-app.floot.app",
    "20d2f317-3710-4331-80ee-ea6072056928.sandbox.floot.app",
  ]
  static func shouldTryFallback(statusCode: Int) -> Bool { false }
}
