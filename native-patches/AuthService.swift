import Foundation

protocol AuthServing: Sendable {
  func restoreSession() async throws -> AuthUser?
  func login(email: String, password: String) async throws -> AuthUser
  func register(displayName: String, email: String, password: String) async throws -> AuthUser
  func logout() async throws
}

actor AuthService: AuthServing {
  static let shared = AuthService()

  private struct Envelope<T: Codable>: Codable { let json: T }
  private struct LoginBody: Codable {
    let email: String
    let password: String
  }
  private struct RegisterBody: Codable {
    let email: String
    let password: String
    let displayName: String
  }
  private struct UserResponse: Codable { let user: AuthUser }
  private struct SessionError: Codable {
    let error: String?
    let message: String?
  }

  private let session: URLSession
  private let preferredBackendKey = "muwa.auth.preferredBackend"

  init(session: URLSession? = nil) {
    if let session { self.session = session; return }
    let configuration = URLSessionConfiguration.default
    configuration.httpCookieAcceptPolicy = .always
    configuration.httpShouldSetCookies = true
    configuration.httpCookieStorage = .shared
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 60
    self.session = URLSession(configuration: configuration)
  }

  func restoreSession() async throws -> AuthUser? {
    let bases = orderedBaseURLs()
    var lastTransportError: Error?

    for (index, baseURL) in bases.enumerated() {
      var request = URLRequest(url: endpoint("_api/auth/session", baseURL: baseURL))
      request.httpMethod = "GET"
      request.httpShouldHandleCookies = true
      request.setValue("application/json", forHTTPHeaderField: "Accept")

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await session.data(for: request)
      } catch {
        lastTransportError = error
        if index < bases.count - 1 { continue }
        throw error
      }

      guard let http = response as? HTTPURLResponse else {
        let error = URLError(.badServerResponse)
        if index < bases.count - 1 {
          lastTransportError = error
          continue
        }
        throw error
      }

      if http.statusCode == 401 {
        // A 401 from the preferred/authoritative backend means the user is signed out.
        return nil
      }
      if BackendConfig.shouldTryFallback(statusCode: http.statusCode), index < bases.count - 1 {
        continue
      }
      guard (200..<300).contains(http.statusCode) else {
        throw authError(
          data: data, status: http.statusCode, fallback: "Не удалось проверить сессию.")
      }

      remember(baseURL)
      return try decode(UserResponse.self, from: data).user
    }

    if let lastTransportError { throw lastTransportError }
    throw URLError(.badServerResponse)
  }

  func login(email: String, password: String) async throws -> AuthUser {
    try await post(
      path: "_api/auth/login_with_password",
      body: LoginBody(email: normalize(email), password: password)
    ).user
  }

  func register(displayName: String, email: String, password: String) async throws -> AuthUser {
    try await post(
      path: "_api/auth/register_with_password",
      body: RegisterBody(
        email: normalize(email),
        password: password,
        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    ).user
  }

  func logout() async throws {
    // Drop local credentials even if every server is offline. Clear after all
    // responses, which can otherwise recreate cookies during logout.
    defer { clearLocalSession() }
    let body = try JSONEncoder().encode(Envelope(json: EmptyBody()))
    let bases = orderedBaseURLs()
    var firstError: Error?
    var clearedAtLeastOneBackend = false

    // Clear every known backend host. This prevents an old production/sandbox
    // cookie from reviving a session after a temporary backend fallback.
    for baseURL in bases {
      var request = URLRequest(url: endpoint("_api/auth/logout", baseURL: baseURL))
      request.httpMethod = "POST"
      request.httpShouldHandleCookies = true
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await session.data(for: request)
      } catch {
        if firstError == nil { firstError = error }
        continue
      }

      guard let http = response as? HTTPURLResponse else {
        if firstError == nil { firstError = URLError(.badServerResponse) }
        continue
      }

      if (200..<300).contains(http.statusCode) || http.statusCode == 401 {
        clearedAtLeastOneBackend = true
        continue
      }
      if BackendConfig.shouldTryFallback(statusCode: http.statusCode) {
        continue
      }
      if firstError == nil {
        firstError = authError(
          data: data, status: http.statusCode, fallback: "Не удалось выйти из аккаунта.")
      }
    }

    if !clearedAtLeastOneBackend, let firstError { throw firstError }
  }

  private func clearLocalSession() {
    let storage = HTTPCookieStorage.shared
    for cookie in storage.cookies ?? [] {
      let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
      if BackendConfig.candidateAPIBaseURLs.contains(where: {
        guard let host = $0.host else { return false }
        return host == domain || host.hasSuffix("." + domain)
      }) { storage.deleteCookie(cookie) }
    }
    forgetPreferredBackend()
  }

  private func post<Body: Codable>(path: String, body: Body) async throws -> UserResponse {
    let encoded = try JSONEncoder().encode(Envelope(json: body))
    let bases = orderedBaseURLs()
    var lastTransportError: Error?

    for (index, baseURL) in bases.enumerated() {
      var request = URLRequest(url: endpoint(path, baseURL: baseURL))
      request.httpMethod = "POST"
      request.httpShouldHandleCookies = true
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.httpBody = encoded

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await session.data(for: request)
      } catch {
        lastTransportError = error
        if index < bases.count - 1 { continue }
        throw error
      }

      guard let http = response as? HTTPURLResponse else {
        let error = URLError(.badServerResponse)
        if index < bases.count - 1 {
          lastTransportError = error
          continue
        }
        throw error
      }

      if BackendConfig.shouldTryFallback(statusCode: http.statusCode), index < bases.count - 1 {
        continue
      }
      guard (200..<300).contains(http.statusCode) else {
        let fallback =
          http.statusCode == 409
          ? "Аккаунт с такой почтой уже существует."
          : http.statusCode == 401
            ? "Неверная почта или пароль."
            : http.statusCode == 429
              ? "Слишком много попыток. Попробуйте позже."
              : "Не удалось выполнить вход."
        throw authError(data: data, status: http.statusCode, fallback: fallback)
      }

      remember(baseURL)
      return try decode(UserResponse.self, from: data)
    }

    if let lastTransportError { throw lastTransportError }
    throw URLError(.badServerResponse)
  }

  private func orderedBaseURLs() -> [URL] {
    let candidates = BackendConfig.candidateAPIBaseURLs
    guard let stored = UserDefaults.standard.string(forKey: preferredBackendKey),
      let preferred = URL(string: stored),
      candidates.contains(where: { $0.absoluteString == preferred.absoluteString })
    else {
      return candidates
    }
    return [preferred] + candidates.filter { $0.absoluteString != preferred.absoluteString }
  }

  private func remember(_ baseURL: URL) {
    UserDefaults.standard.set(baseURL.absoluteString, forKey: preferredBackendKey)
  }

  private func forgetPreferredBackend() {
    UserDefaults.standard.removeObject(forKey: preferredBackendKey)
  }

  private func endpoint(_ path: String, baseURL: URL) -> URL { baseURL.appending(path: path) }
  private func normalize(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
    if let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data) {
      return envelope.json
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func authError(data: Data, status: Int, fallback: String) -> Error {
    let decoded: SessionError? =
      (try? JSONDecoder().decode(Envelope<SessionError>.self, from: data))?.json
      ?? (try? JSONDecoder().decode(SessionError.self, from: data))
    let message = decoded?.message ?? decoded?.error ?? fallback
    return NSError(
      domain: "Muwa.Auth",
      code: status,
      userInfo: [NSLocalizedDescriptionKey: localize(message, fallback: fallback)]
    )
  }

  private func localize(_ message: String, fallback: String) -> String {
    switch message.lowercased() {
    case "invalid email or password": return "Неверная почта или пароль."
    case "email already in use": return "Аккаунт с такой почтой уже существует."
    case "authentication failed": return fallback
    case "registration failed": return "Не удалось создать аккаунт."
    default:
      if message.lowercased().contains("too many failed") {
        return "Слишком много попыток входа. Попробуйте позже."
      }
      return message.isEmpty ? fallback : message
    }
  }
}

private struct EmptyBody: Codable {}
