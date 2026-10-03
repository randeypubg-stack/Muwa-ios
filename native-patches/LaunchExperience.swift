import SwiftUI

/// Owns a brief mark animation inside Home, never the presentation of the app shell.
@MainActor
final class LaunchPresentation: ObservableObject {
  @Published private(set) var isVisible: Bool
  private var started = false

  init(skipIntro: Bool? = nil) {
    var review = false
    #if DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    review = arguments.contains(where: { $0.hasPrefix("--audit-") }) && !arguments.contains("--audit-launch")
    #endif
    isVisible = !(skipIntro ?? review)
  }

  func begin() -> Bool {
    guard isVisible, !started else { return false }
    started = true
    return true
  }

  func finish() {
    guard isVisible else { return }
    isVisible = false
  }
}

/// Branding animates in the Home toolbar while browsing and playback are usable.
struct MuwaLaunchView: View {
  @EnvironmentObject private var launch: LaunchPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var sheen: CGFloat = -0.85

  var body: some View {
    Image("AppMark")
      .resizable().scaledToFit()
      .frame(width: 42, height: 42)
      .overlay {
        if !reduceMotion && launch.isVisible {
          Image("AppMark")
            .resizable().scaledToFit()
            .mask {
              Rectangle()
                .fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 14, height: 58)
                .rotationEffect(.degrees(-18))
                .offset(x: 42 * sheen)
            }
            .opacity(0.36)
            .blendMode(.screen)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .allowsHitTesting(false)
      .accessibilityLabel("Muwa")
      .task { await animateMark() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background { launch.finish() }
      }
      .onChange(of: reduceMotion) { _, enabled in
        if enabled { launch.finish() }
      }
      .onDisappear { launch.finish() }
  }

  @MainActor private func animateMark() async {
    guard launch.begin() else { return }
    defer { launch.finish() }
    guard !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
    withAnimation(.easeInOut(duration: 0.58)) { sheen = 0.85 }
    try? await Task.sleep(for: .milliseconds(580))
  }
}
