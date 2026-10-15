import SwiftUI

// Semantic system fonts scale with Dynamic Type and retain Arabic glyph fallback.
enum MuwaTypography {
  static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)
  static let section = Font.system(.title2, design: .rounded).weight(.bold)
  static let title = Font.system(.headline, design: .rounded).weight(.semibold)
  static let body = Font.body
  static let detail = Font.subheadline
  static let caption = Font.caption
  static let label = Font.system(.caption2, design: .rounded).weight(.semibold)
}
