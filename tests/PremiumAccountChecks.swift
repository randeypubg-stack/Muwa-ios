import Foundation

@MainActor
final class RequestGate {
  var entered = false
  var continuation: CheckedContinuation<Void, Never>?
  func pause() async {
    entered = true
    await withCheckedContinuation { continuation = $0 }
  }
  func release() { continuation?.resume(); continuation = nil }
}

@main
struct PremiumAccountChecks {
  @MainActor
  static func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10000 {
      if condition() { return }
      await Task.yield()
    }
    preconditionFailure("Async condition did not complete")
  }

  static func response(_ id: Int, _ active: Bool, expiry: String? = nil) -> MuwaPremiumResponse {
    MuwaPremiumResponse(userId: id, isPremium: active, expiresAt: expiry, canManageCodes: false, code: nil, codes: nil, alreadyRedeemed: nil)
  }

  @MainActor
  static func main() async throws {
    let gate = RequestGate()
    var first = true
    var redeemed = false
    let manager = PremiumManager { body in
      if first {
        first = false
        await gate.pause()
        return response(1, false)
      }
      if body["action"] as? String == "redeem" { redeemed = true }
      return response(1, redeemed)
    }
    manager.setAccount(1)
    await waitUntil { gate.entered }
    let redeem = Task { try await manager.accountRequest(["action": "redeem", "code": "test"]) }
    for _ in 0..<20 { await Task.yield() }
    precondition(!redeemed, "Redemption must wait for prior status completion")
    gate.release()
    _ = try await redeem.value
    precondition(manager.isPremium && manager.hasAccountPremium, "Old status must not overwrite redeemed access")
    manager.setAccount(nil)
    precondition(!manager.hasAccountPremium && !manager.canManageCodes, "Logout must clear account entitlement")
    print("PASS account requests ordered, redemption retained, logout clears access")

    let oldGate = RequestGate()
    var firstOld = true
    var newSeen = false
    var obsoleteMutationRan = false
    let switching = PremiumManager { body in
      if firstOld {
        firstOld = false
        await oldGate.pause()
        return response(1, true)
      }
      if body["action"] as? String == "redeem" { obsoleteMutationRan = true }
      newSeen = true
      return response(2, false)
    }
    switching.setAccount(1)
    await waitUntil { oldGate.entered }
    let obsolete = Task { try await switching.accountRequest(["action": "redeem", "code": "old-account"]) }
    for _ in 0..<20 { await Task.yield() }
    switching.setAccount(2)
    oldGate.release()
    do { _ = try await obsolete.value; preconditionFailure("Obsolete mutation succeeded") }
    catch is CancellationError {}
    await waitUntil { newSeen }
    precondition(!obsoleteMutationRan, "Queued mutation for old account must never be sent")
    precondition(!switching.hasAccountPremium, "Old account grant leaked to new account")
    print("PASS account switch rejects old responses and queued mutations")

    let expired = PremiumManager { _ in response(3, true, expiry: "2020-01-01T00:00:00.000Z") }
    expired.setAccount(3)
    _ = try await expired.accountRequest(["action": "status"])
    precondition(!expired.isPremium, "Expired account grant must not unlock access")
    precondition(MuwaPremiumAPI.date("2026-09-27T10:00:00Z") != nil)
    precondition(MuwaPremiumAPI.date("2026-09-27T10:00:00.123Z") != nil)
    print("PASS expiry and timestamp parsing")
  }
}
