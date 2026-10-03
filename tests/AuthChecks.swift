import Foundation

private actor HeldAuthService: AuthServing {
  private var restoreContinuation: CheckedContinuation<AuthUser?, Error>?
  private(set) var restoreCalls = 0
  private(set) var isWaiting = false
  func restoreSession() async throws -> AuthUser? {
    restoreCalls += 1
    isWaiting = true
    return try await withCheckedThrowingContinuation { restoreContinuation = $0 }
  }
  func completeRestore(_ user: AuthUser?) { restoreContinuation?.resume(returning: user); restoreContinuation = nil; isWaiting = false }
  func failRestore() { restoreContinuation?.resume(throwing: URLError(.notConnectedToInternet)); restoreContinuation = nil; isWaiting = false }
  func login(email: String, password: String) async throws -> AuthUser { AuthChecks.user(2) }
  func register(displayName: String, email: String, password: String) async throws -> AuthUser { AuthChecks.user(2) }
  func logout() async throws {}
}

private final class OfflineProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
  override func stopLoading() {}
}

private final class AuthRequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [URL] = []
  func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; requests.append(url) }
  var urls: [URL] { lock.lock(); defer { lock.unlock() }; return requests }
}
private final class FailedServerProtocol: URLProtocol {
  static let log = AuthRequestLog()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url else { return }
    Self.log.append(url)
    let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("{\"error\":\"Unavailable\"}".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main
struct AuthChecks {
  static func user(_ id: Int) -> AuthUser {
    AuthUser(id: id, email: "fixture@example.com", displayName: "Fixture", avatarUrl: nil, role: "user")
  }

  @MainActor static func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<10000 { if await condition() { return }; await Task.yield() }
    preconditionFailure("Auth fixture did not reach the expected state")
  }

  @MainActor static func main() async throws {
    let suite = "muwa.auth.audit.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = HeldAuthService()
    let manager = AuthManager(service: service, defaults: defaults)
    precondition(manager.state == .checking && manager.user == nil, "An unverified startup session exposed account access")
    let restoration = Task { await manager.restore() }
    await waitUntil { await service.isWaiting }
    await manager.restore()
    let calls = await service.restoreCalls
    precondition(manager.state == .checking && !manager.isWorking, "Restoration blocked explicit account actions")
    precondition(calls == 1, "A second window started duplicate session restoration")
    let loggedIn = await manager.login(email: "fixture@example.com", password: "fixture-only")
    precondition(loggedIn && manager.user?.id == 2)
    await service.completeRestore(user(1))
    await restoration.value
    precondition(manager.user?.id == 2, "Old session restoration overwrote a new login")

    let guestService = HeldAuthService()
    let guest = AuthManager(service: guestService, defaults: defaults)
    let guestRestoration = Task { await guest.restore() }
    await waitUntil { await guestService.isWaiting }
    guest.continueAsGuest()
    await guestService.completeRestore(user(1))
    await guestRestoration.value
    precondition(guest.isGuest, "Old session response replaced an explicit guest choice")

    // First install, expired cookies and offline restoration keep public listening
    // available. They do not force a sign-in screen or grant account privileges.
    for offline in [false, true] {
      defaults.set(false, forKey: "muwa.auth.continueAsGuest")
      let unavailable = HeldAuthService()
      let startup = AuthManager(service: unavailable, defaults: defaults)
      let task = Task { await startup.restore() }
      await waitUntil { await unavailable.isWaiting }
      precondition(startup.state == .checking && startup.user == nil)
      if offline { await unavailable.failRestore() } else { await unavailable.completeRestore(nil) }
      await task.value
      precondition(startup.isGuest && !startup.isAuthenticated, "Unauthenticated launch forced sign-in or granted access")
      startup.showAuthentication()
      precondition(startup.state == .signedOut, "Explicit sign-in became inaccessible")
    }

    let explicitService = HeldAuthService()
    let explicit = AuthManager(service: explicitService, defaults: defaults)
    let explicitRestore = Task { await explicit.restore() }
    await waitUntil { await explicitService.isWaiting }
    explicit.showAuthentication()
    await explicitService.completeRestore(user(1))
    await explicitRestore.value
    precondition(explicit.state == .signedOut && explicit.user == nil, "Background response dismissed explicit sign-in")

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OfflineProtocol.self]
    configuration.httpCookieStorage = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let base = BackendConfig.productionAPIBaseURL
    let legacyCookie = HTTPCookie(properties: [.domain: BackendConfig.sessionCleanupHosts.last!, .path: "/", .name: "muwa-audit-legacy", .value: "fixture-only", .secure: "TRUE"])!
    HTTPCookieStorage.shared.setCookie(legacyCookie)
    let cookie = HTTPCookie(properties: [.domain: base.host!, .path: "/", .name: "muwa-audit-session", .value: "fixture-only", .secure: "TRUE"])!
    HTTPCookieStorage.shared.setCookie(cookie)
    do { try await AuthService(session: session).logout(); preconditionFailure("Offline logout unexpectedly reached a server") }
    catch {}
    precondition(!(HTTPCookieStorage.shared.cookies ?? []).contains { $0.name == cookie.name }, "Offline logout left reusable local credentials")
    precondition(!(HTTPCookieStorage.shared.cookies ?? []).contains { $0.name == legacyCookie.name }, "Legacy sandbox credentials survived logout")
    let failedConfiguration = URLSessionConfiguration.ephemeral
    failedConfiguration.protocolClasses = [FailedServerProtocol.self]
    failedConfiguration.httpCookieStorage = nil
    let failedSession = URLSession(configuration: failedConfiguration)
    defer { failedSession.invalidateAndCancel() }
    do { _ = try await AuthService(session: failedSession).login(email: "fixture@example.invalid", password: "fixture-only"); preconditionFailure("503 login succeeded") } catch {}
    precondition(FailedServerProtocol.log.urls.count == 1, "Login retried credentials on another backend")
    precondition(FailedServerProtocol.log.urls.first?.host == BackendConfig.productionAPIBaseURL.host, "Credentials sent outside production")
    print("PASS: offline/expired startup stays usable, explicit sign-in, restoration isolation, stale response rejection, cookie cleanup, no credential fallback on HTTP 503")
  }
}
