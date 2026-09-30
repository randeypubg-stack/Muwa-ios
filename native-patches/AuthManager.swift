import Foundation

@MainActor
final class AuthManager: ObservableObject {
  enum State: Equatable {
    case checking
    case signedOut
    case guest
    case authenticated(AuthUser)
  }

  @Published private(set) var state: State = .checking
  @Published private(set) var isWorking = false
  @Published var errorMessage: String?
  @Published private(set) var registrationJustCompleted = false

  private let service: AuthService
  private let defaults: UserDefaults
  private let guestKey = "muwa.auth.continueAsGuest"

  init(service: AuthService = .shared, defaults: UserDefaults = .standard) {
    self.service = service
    self.defaults = defaults
  }

  var user: AuthUser? {
    guard case .authenticated(let user) = state else { return nil }
    return user
  }

  var isGuest: Bool { state == .guest }
  var isAuthenticated: Bool { user != nil }

  func restore() async {
    state = .checking
    do {
      if let user = try await service.restoreSession() {
        defaults.set(false, forKey: guestKey)
        registrationJustCompleted = false
        state = .authenticated(user)
      } else {
        state = defaults.bool(forKey: guestKey) ? .guest : .signedOut
      }
    } catch {
      Diagnostics.shared.record("auth-restore", error: error)
      state = defaults.bool(forKey: guestKey) ? .guest : .signedOut
    }
  }

  func login(email: String, password: String) async -> Bool {
    await perform {
      let user = try await self.service.login(email: email, password: password)
      self.defaults.set(false, forKey: self.guestKey)
      self.registrationJustCompleted = false
      self.state = .authenticated(user)
    }
  }

  func register(displayName: String, email: String, password: String) async -> Bool {
    await perform {
      let user = try await self.service.register(
        displayName: displayName, email: email, password: password)
      self.defaults.set(false, forKey: self.guestKey)
      self.registrationJustCompleted = true
      self.state = .authenticated(user)
    }
  }

  func finishRegistrationConfirmation() {
    registrationJustCompleted = false
  }

  func continueAsGuest() {
    registrationJustCompleted = false
    defaults.set(true, forKey: guestKey)
    errorMessage = nil
    state = .guest
  }

  func showAuthentication() {
    registrationJustCompleted = false
    defaults.set(false, forKey: guestKey)
    errorMessage = nil
    state = .signedOut
  }

  func logout() async {
    isWorking = true
    defer { isWorking = false }
    do { try await service.logout() } catch { Diagnostics.shared.record("auth-logout", error: error) }
    defaults.set(false, forKey: guestKey)
    registrationJustCompleted = false
    state = .signedOut
  }

  private func perform(_ operation: @escaping @MainActor () async throws -> Void) async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await operation()
      return true
    } catch {
      Diagnostics.shared.record("auth", error: error)
      errorMessage = error.localizedDescription
      return false
    }
  }
}
