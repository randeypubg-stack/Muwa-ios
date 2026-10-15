import Foundation

enum BackendConfig {
  // API requests never migrate credentials/body to a redirected endpoint.
  // Signed uploads use their own cookie-free session, including same-host URLs.
  static func makeAPISession(_ configuration: URLSessionConfiguration) -> URLSession {
    URLSession(configuration: configuration, delegate: NoAPIRedirects(), delegateQueue: nil)
  }
  static let authenticatedSession = makeAPISession(.default)
  static let uploadSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return makeAPISession(configuration)
  }()
  static func boundedData(for request: URLRequest, using session: URLSession = authenticatedSession) async throws -> (Data, URLResponse) {
    let maximumBytes = 10 * 1024 * 1024
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard response.expectedContentLength <= Int64(maximumBytes) else { throw URLError(.dataLengthExceedsMaximum) }
    var data = Data()
    for try await byte in bytes {
      guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
      data.append(byte)
    }
    return (data, response)
  }
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

private final class NoAPIRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}
