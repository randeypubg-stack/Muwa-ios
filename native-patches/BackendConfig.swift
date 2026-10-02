import Foundation

enum BackendConfig {
  static let productionAPIBaseURL = URL(string: "https://muwa-app.floot.app")!
  // Select a development environment explicitly; never retry credentials there.
  #if DEBUG && MUWA_USE_SANDBOX
    static let apiBaseURL = URL(string: "https://20d2f317-3710-4331-80ee-ea6072056928.sandbox.floot.app")!
  #else
    static let apiBaseURL = productionAPIBaseURL
  #endif
  static let candidateAPIBaseURLs = [apiBaseURL]
  // Cleanup only for cookies left by older versions. Never used for requests.
  static let sessionCleanupHosts = [
    "muwa-app.floot.app",
    "20d2f317-3710-4331-80ee-ea6072056928.sandbox.floot.app",
  ]
  static func shouldTryFallback(statusCode: Int) -> Bool { false }
}
