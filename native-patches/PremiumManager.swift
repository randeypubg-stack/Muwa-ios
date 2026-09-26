import StoreKit
import SwiftUI

@MainActor
final class PremiumManager: ObservableObject {
  @Published private(set) var products: [Product] = []
  @Published private(set) var isPremium = false
  @Published private(set) var isLoading = false
  @Published var lastError: String?

  let productIDs = [
    "app.muwa.nasheeds.premium.monthly",
    "app.muwa.nasheeds.premium.yearly",
  ]

  private var updatesTask: Task<Void, Never>?

  init() {
    updatesTask = Task { [weak self] in
      for await result in Transaction.updates {
        guard case .verified = result else { continue }
        await self?.refreshEntitlements()
      }
    }
  }

  deinit { updatesTask?.cancel() }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      products = try await Product.products(for: productIDs)
        .sorted(by: { $0.price < $1.price })
      lastError = nil
    } catch {
      products = []
      lastError = error.localizedDescription
    }
    await refreshEntitlements()
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
    isPremium = premium
  }
}

