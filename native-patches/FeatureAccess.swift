import Foundation

/// Keep verified entitlements separate from the functional validation phase.
/// Re-enable individual restrictions here after the owner accepts the features.
enum FeatureAccess {
  static let premiumRestrictionsEnabled = false
  static func allowsPremiumFeature(isPremium: Bool) -> Bool {
    !premiumRestrictionsEnabled || isPremium
  }
}
