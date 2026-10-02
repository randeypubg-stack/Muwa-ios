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
  func completeRestore(_ user: AuthUser?) { restoreContinuation?.resume(returning: user); restoreContinuation = nil }
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
    let restoration = Task { await manager.restore() }
    await waitUntil { await service.isWaiting }
    await manager.restore()
    let calls = await service.restoreCalls
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

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OfflineProtocol.self]
    configuration.httpCookieStorage = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let base = BackendConfig.productionAPIBaseURL
    let cookie = HTTPCookie(properties: [.domain: base.host!, .path: "/", .name: "muwa-audit-session", .value: "fixture-only", .secure: "TRUE"])!
    HTTPCookieStorage.shared.setCookie(cookie)
    do { try await AuthService(session: session).logout(); preconditionFailure("Offline logout unexpectedly reached a server") }
    catch {}
    precondition(!(HTTPCookieStorage.shared.cookies ?? []).contains { $0.name == cookie.name }, "Offline logout left reusable local credentials")
    print("PASS: one restoration, stale account/guest response rejection, offline cookie cleanup")
  }
}
