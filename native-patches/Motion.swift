import SwiftUI

enum MuwaMotion {
  static let ambientDuration: TimeInterval = 24
  static let press = Animation.spring(response: 0.24, dampingFraction: 0.78)
  static let reorder = Animation.spring(response: 0.36, dampingFraction: 0.88)
}

struct MuwaPressStyle: ButtonStyle {
  var scale: CGFloat = 0.97
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(reduceMotion ? nil : MuwaMotion.press, value: configuration.isPressed)
  }
}
