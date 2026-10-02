import SwiftUI

/// Soft radial lights avoid rectangular seams and a full-screen live blur.
/// Only this view animates; the playback clock never drives the background.
struct AppBackground: View {
  @State private var drifting = false
  @State private var visible = false
  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.scenePhase) private var scenePhase

  private var motionAllowed: Bool {
    visible && scenePhase == .active && !reduceMotion && !lowPower && !reduceTransparency
  }

  var body: some View {
    GeometryReader { proxy in
      let span = min(max(proxy.size.width, proxy.size.height), 1200)
      let strength = reduceTransparency ? 0.35 : 1.0

      ZStack {
        MuwaPalette.background

        light(MuwaPalette.blue, diameter: span * 0.94, strength: strength)
          .position(x: proxy.size.width * (drifting ? 0.72 : 0.92),
                    y: proxy.size.height * (drifting ? 0.25 : 0.12))
          .scaleEffect(drifting ? 1.08 : 0.96)

        light(MuwaPalette.teal, diameter: span * 0.72, strength: strength * 0.68)
          .position(x: proxy.size.width * (drifting ? 0.22 : -0.12),
                    y: proxy.size.height * (drifting ? 0.45 : 0.60))

        light(MuwaPalette.violet, diameter: span * 0.80, strength: strength * 0.72)
          .position(x: proxy.size.width * (drifting ? 0.92 : 0.70),
                    y: proxy.size.height * (drifting ? 0.96 : 0.82))

        LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.46)],
                       startPoint: .top, endPoint: .bottom)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
      .task(id: motionAllowed) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { drifting = false }
        guard motionAllowed else { return }
        withAnimation(.easeInOut(duration: MuwaMotion.ambientDuration).repeatForever(autoreverses: true)) {
          drifting = true
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
      }
      .onAppear { visible = true }
      .onDisappear { visible = false }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func light(_ color: Color, diameter: CGFloat, strength: Double) -> some View {
    Circle()
      .fill(RadialGradient(stops: [
        .init(color: color.opacity(0.32 * strength), location: 0),
        .init(color: color.opacity(0.17 * strength), location: 0.36),
        .init(color: color.opacity(0.045 * strength), location: 0.70),
        .init(color: .clear, location: 1),
      ], center: .center, startRadius: 0, endRadius: diameter / 2))
      .frame(width: diameter, height: diameter)
  }
}
