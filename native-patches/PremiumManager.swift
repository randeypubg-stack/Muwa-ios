import StoreKit
import SwiftUI

@MainActor
final class PremiumManager: ObservableObject {
  @Published private(set) var products: [Product] = []
  @Published private(set) var isPremium = false
  @Published private(set) var isLoading = false
  @Published var lastError: String?
  @Published private(set) var canManageCodes = false
  @Published private(set) var accountExpiresAt: Date?
  @Published private(set) var hasAccountPremium = false
  @Published private(set) var accountError: String?
  private var accountID: Int?
  private var accountRevision = UUID()
  private var accountRequestTail: Task<Void, Never>?
  private let requestAccount: ([String: Any]) async throws -> MuwaPremiumResponse
  private var storePremium = false
  private var expiryTask: Task<Void, Never>?

  let productIDs = [
    "app.muwa.nasheeds.premium.monthly",
    "app.muwa.nasheeds.premium.yearly",
  ]

  private var productLoadID: UUID?

  private var updatesTask: Task<Void, Never>?

  init(requestAccount: @escaping ([String: Any]) async throws -> MuwaPremiumResponse = MuwaPremiumAPI.request) {
    self.requestAccount = requestAccount
    updatesTask = Task { [weak self] in
      for await result in Transaction.updates {
        guard case .verified = result else { continue }
        await self?.refreshEntitlements()
      }
    }
  }

  deinit { updatesTask?.cancel(); expiryTask?.cancel() }

  func setAccount(_ id: Int?) {
    guard accountID != id else { return }
    accountRevision = UUID()
    accountID = id
    hasAccountPremium = false
    canManageCodes = false
    accountExpiresAt = nil
    accountError = nil
    expiryTask?.cancel()
    isPremium = storePremium
    if id != nil { Task { await refreshAccount() } }
  }

  func refreshAccount() async {
    guard accountID != nil else { return }
    let revision = accountRevision
    do { _ = try await accountRequest(["action": "status"]) }
    catch { if revision == accountRevision { accountError = error.localizedDescription } }
  }

  func accountRequest(_ body: [String: Any]) async throws -> MuwaPremiumResponse {
    guard let id = accountID else { throw MuwaPremiumAPI.error("Войдите в аккаунт Muwa.") }
    let revision = accountRevision
    let previous = accountRequestTail
    let operation = Task { @MainActor in
      await previous?.value
      guard self.accountRevision == revision, self.accountID == id else { throw CancellationError() }
      return try await self.performAccountRequest(body, id: id, revision: revision)
    }
    accountRequestTail = Task { _ = try? await operation.value }
    return try await operation.value
  }

  private func performAccountRequest(_ body: [String: Any], id: Int, revision: UUID) async throws -> MuwaPremiumResponse {
    do {
      let value = try await requestAccount(body)
      guard accountRevision == revision, accountID == id, value.userId == id else {
        throw CancellationError()
      }
      hasAccountPremium = value.isPremium
      canManageCodes = value.canManageCodes
      accountExpiresAt = value.expiresAt.flatMap(MuwaPremiumAPI.date)
      accountError = nil
      updateAccess()
      expiryTask?.cancel()
      if let expiry = accountExpiresAt, hasAccountPremium {
        expiryTask = Task { [weak self] in
          let delay = max(0, expiry.timeIntervalSinceNow)
          try? await Task.sleep(for: .seconds(delay))
          guard !Task.isCancelled else { return }
          self?.updateAccess()
        }
      }
      return value
    } catch {
      guard accountRevision == revision else { throw CancellationError() }
      if accountRevision == revision {
        if (error as NSError).code == 401 {
          hasAccountPremium = false
          canManageCodes = false
          accountExpiresAt = nil
        }
        updateAccess()
      }
      throw error
    }
  }

  private func updateAccess() {
    if let expiry = accountExpiresAt, expiry <= Date() { hasAccountPremium = false }
    isPremium = storePremium || hasAccountPremium
  }

  func load() async {
    Task { await refreshEntitlements() }
    guard !isLoading else { return }
    let requestID = UUID()
    productLoadID = requestID
    isLoading = true
    let timeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(10))
      guard !Task.isCancelled, let self, self.productLoadID == requestID else { return }
      self.productLoadID = nil
      self.isLoading = false
      self.lastError = "Не удалось загрузить предложения Apple. Подарочный доступ по аккаунту остаётся доступен."
    }
    defer {
      timeout.cancel()
      if productLoadID == requestID { isLoading = false }
    }
    do {
      let loaded = try await Product.products(for: productIDs).sorted(by: { $0.price < $1.price })
      guard productLoadID == requestID else { return }
      products = loaded
      lastError = nil
    } catch {
      guard productLoadID == requestID else { return }
      products = []
      lastError = error.localizedDescription
    }
    isLoading = false
    timeout.cancel()
  }

  func purchase(_ product: Product) async throws {
    let result = try await product.purchase()
    switch result {
    case .success(let verification):
      let transaction = try verification.payloadValue
      await transaction.finish()
      await refreshEntitlements()
    case .pending, .userCancelled:
      break
    @unknown default:
      break
    }
  }

  func restore() async {
    do {
      try await AppStore.sync()
      await refreshEntitlements()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  func refreshEntitlements() async {
    var premium = false
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else { continue }
      if productIDs.contains(transaction.productID),
        transaction.revocationDate == nil,
        !transaction.isUpgraded,
        transaction.expirationDate.map({ $0 > Date() }) ?? true
      {
        premium = true
      }
    }
    storePremium = premium
    updateAccess()
    await refreshAccount()
  }
}

struct MuwaGiftCode: Decodable, Identifiable {
  let id: String
  let label: String
  let durationDays: Int
  let maxUses: Int
  let uses: Int
  let expiresAt: String
  let disabled: Bool
}

struct MuwaPremiumResponse: Decodable {
  let userId: Int
  let isPremium: Bool
  let expiresAt: String?
  let canManageCodes: Bool
  let code: String?
  let codes: [MuwaGiftCode]?
  let alreadyRedeemed: Bool?
}

enum MuwaPremiumAPI {
  private static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    return URLSession(configuration: config)
  }()

  static func date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
  static func error(_ message: String, code: Int = 0) -> NSError {
    NSError(domain: "Muwa.Premium", code: code, userInfo: [NSLocalizedDescriptionKey: message])
  }
  static func request(_ body: [String: Any]) async throws -> MuwaPremiumResponse {
    let candidates = BackendConfig.candidateAPIBaseURLs
    let stored = UserDefaults.standard.string(forKey: "muwa.auth.preferredBackend")
    guard let base = candidates.first(where: { $0.absoluteString == stored }) ?? candidates.first else {
      throw error("Сервис недоступен.")
    }
    var request = URLRequest(url: base.appending(path: "_api/premium/access"))
    request.httpMethod = "POST"
    request.timeoutInterval = 25
    request.httpShouldHandleCookies = false
    let cookies = HTTPCookieStorage.shared.cookies(for: request.url!) ?? []
    for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw error("Нет ответа сервера.") }
    guard (200..<300).contains(http.statusCode) else {
      let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      throw error(payload?["error"] as? String ?? "Не удалось подключиться. Повторите позже.", code: http.statusCode)
    }
    return try JSONDecoder().decode(MuwaPremiumResponse.self, from: data)
  }
}
