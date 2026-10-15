import Foundation

@main
struct NetworkPolicyChecks {
  static func main() async throws {
    let base = URL(string: CommandLine.arguments[1])!
    let marker = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "muwa_audit_cookie", .value: "fixture-only"])!
    HTTPCookieStorage.shared.setCookie(marker)
    defer { HTTPCookieStorage.shared.deleteCookie(marker) }
    var request = URLRequest(url: base.appending(path: "redirect"))
    request.httpMethod = "POST"
    request.httpBody = Data("fixture-body".utf8)
    request.setValue("fixture-only", forHTTPHeaderField: "Cookie")
    let (_, redirect) = try await BackendConfig.boundedData(for: request)
    precondition((redirect as? HTTPURLResponse)?.statusCode == 307, "API followed a redirect carrying credentials")
    let (uploadData, _) = try await BackendConfig.boundedData(for: URLRequest(url: base.appending(path: "cookie")), using: BackendConfig.uploadSession)
    let upload = try JSONSerialization.jsonObject(with: uploadData) as! [String: String]
    precondition(upload["cookie"] == "", "Signed upload session leaked a same-host login cookie")
    for path in ["declared-large", "chunked-large"] {
      do {
        _ = try await BackendConfig.boundedData(for: URLRequest(url: base.appending(path: path)))
        preconditionFailure("Oversized response accepted: \(path)")
      } catch {
        precondition((error as NSError).code == NSURLErrorDataLengthExceedsMaximum, "Unexpected bounded-response error: \(error)")
      }
    }
    let (stateData, _) = try await BackendConfig.boundedData(for: URLRequest(url: base.appending(path: "state")))
    let state = try JSONSerialization.jsonObject(with: stateData) as! [String: Int]
    precondition(state["redirectHits"] == 0, "Redirect target received a request")
    print("PASS: actual HTTP redirect isolation, cookie-free uploads and declared/chunked response bounds")
  }
}
