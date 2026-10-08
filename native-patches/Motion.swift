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

/// A local, non-interactive loading accent. It never observes the playback
/// clock or adds a gesture above Play, and stops rendering in the background.
struct PlaybackLoadingRing: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active || reduceMotion || lowPower)) { context in
      let moving = scenePhase == .active && !reduceMotion && !lowPower
      let angle = moving ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360 : 0
      Circle().trim(from: 0, to: 0.72)
        .stroke(AngularGradient(colors: [.white.opacity(0.08), .white.opacity(0.95)], center: .center), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .rotationEffect(.degrees(angle))
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
  }
}
