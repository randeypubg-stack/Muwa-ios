import SwiftUI

// Shared visual values. Screens own layout and behavior, never a second palette.
enum MuwaPalette {
  static let background = Color(red: 0.025, green: 0.034, blue: 0.052)
  static let surface = Color(red: 0.065, green: 0.080, blue: 0.105)
  static let text = Color(red: 0.96, green: 0.97, blue: 0.99)
  static let secondary = Color(red: 0.66, green: 0.72, blue: 0.81)
  static let ice = Color(red: 0.72, green: 0.84, blue: 0.96)
  static let blue = Color(red: 0.34, green: 0.58, blue: 0.84)
  static let teal = Color(red: 0.35, green: 0.68, blue: 0.68)
  static let violet = Color(red: 0.53, green: 0.46, blue: 0.73)
}

enum MuwaSpacing {
  static let compact: CGFloat = 8
  static let item: CGFloat = 12
  static let card: CGFloat = 18
  static let section: CGFloat = 28
  static let screen: CGFloat = 20
}

enum MuwaRadius {
  static let control: CGFloat = 16
  static let artwork: CGFloat = 20
  static let card: CGFloat = 26
}
