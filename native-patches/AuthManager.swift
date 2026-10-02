import Foundation
import Combine

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

  private let service: any AuthServing
  private let defaults: UserDefaults
  private let guestKey = "muwa.auth.continueAsGuest"
  private var hasRestoredSession = false
  private var stateRevision = UUID()

  init(service: any AuthServing = AuthService.shared, defaults: UserDefaults = .standard) {
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
    guard !hasRestoredSession else { return }
    hasRestoredSession = true
    let revision = stateRevision
    state = .checking
    do {
      let user = try await service.restoreSession()
      guard stateRevision == revision else { return }
      if let user {
        defaults.set(false, forKey: guestKey)
        registrationJustCompleted = false
        state = .authenticated(user)
      } else {
        state = defaults.bool(forKey: guestKey) ? .guest : .signedOut
      }
    } catch {
      guard stateRevision == revision else { return }
      Diagnostics.shared.record("auth-restore", error: error)
      state = defaults.bool(forKey: guestKey) ? .guest : .signedOut
    }
  }

  func login(email: String, password: String) async -> Bool {
    await perform { revision in
      let user = try await self.service.login(email: email, password: password)
      guard self.stateRevision == revision else { throw CancellationError() }
      self.defaults.set(false, forKey: self.guestKey)
      self.registrationJustCompleted = false
      self.state = .authenticated(user)
    }
  }

  func register(displayName: String, email: String, password: String) async -> Bool {
    await perform { revision in
      let user = try await self.service.register(
        displayName: displayName, email: email, password: password)
      guard self.stateRevision == revision else { throw CancellationError() }
      self.defaults.set(false, forKey: self.guestKey)
      self.registrationJustCompleted = true
      self.state = .authenticated(user)
    }
  }

  func finishRegistrationConfirmation() {
    registrationJustCompleted = false
  }

  func continueAsGuest() {
    stateRevision = UUID()
    registrationJustCompleted = false
    defaults.set(true, forKey: guestKey)
    errorMessage = nil
    state = .guest
  }

  func showAuthentication() {
    stateRevision = UUID()
    registrationJustCompleted = false
    defaults.set(false, forKey: guestKey)
    errorMessage = nil
    state = .signedOut
  }

  func logout() async {
    guard !isWorking else { return }
    stateRevision = UUID()
    defaults.set(false, forKey: guestKey)
    registrationJustCompleted = false
    errorMessage = nil
    state = .signedOut
    isWorking = true
    defer { isWorking = false }
    do { try await service.logout() } catch { Diagnostics.shared.record("auth-logout", error: error) }
  }

  private func perform(_ operation: @escaping @MainActor (UUID) async throws -> Void) async -> Bool {
    guard !isWorking else { return false }
    stateRevision = UUID()
    let revision = stateRevision
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await operation(revision)
      return true
    } catch {
      guard stateRevision == revision, !(error is CancellationError) else { return false }
      Diagnostics.shared.record("auth", error: error)
      errorMessage = error.localizedDescription
      return false
    }
  }
}
