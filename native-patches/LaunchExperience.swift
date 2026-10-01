import SwiftUI

/// Shared by phone windows: one intro per process, independent of session restoration.
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

struct MuwaLaunchView: View {
  @EnvironmentObject private var launch: LaunchPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var reveal: CGFloat = 0
  @State private var sheen: CGFloat = -0.85
  @State private var exitOpacity = 1.0

  var body: some View {
    GeometryReader { proxy in
      let size = min(360, min(proxy.size.width, proxy.size.height) * 0.92)
      ZStack {
        Color.black
        Image("AppMark")
          .resizable().scaledToFit()
          .frame(width: size, height: size)
          .overlay {
            if !reduceMotion {
              // Brighten the supplied image itself; its black background stays black.
              Image("AppMark")
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .mask {
                  Rectangle().fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.34, height: size * 1.4)
                    .rotationEffect(.degrees(-18))
                    .offset(x: size * sheen)
                }
                .opacity(0.36)
                .blendMode(.screen)
            }
          }
          .compositingGroup()
          .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * reveal)
          .opacity(reduceMotion ? 1 : Double(reveal))
          .accessibilityLabel("Muwa")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .ignoresSafeArea()
    .opacity(exitOpacity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Muwa")
    .task { await animateLaunch() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { launch.finish() }
    }
    .onChange(of: reduceMotion) { _, enabled in
      if enabled { launch.finish() }
    }
    .onDisappear { launch.finish() }
  }

  @MainActor private func animateLaunch() async {
    guard launch.begin() else { return }
    do {
      if reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled {
        reveal = 1
        try await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.16)) { exitOpacity = 0 }
        try await Task.sleep(for: .milliseconds(160))
      } else {
        withAnimation(.easeOut(duration: 0.34)) { reveal = 1 }
        try await Task.sleep(for: .milliseconds(160))
        withAnimation(.easeInOut(duration: 0.58)) { sheen = 0.85 }
        try await Task.sleep(for: .milliseconds(660))
        withAnimation(.easeInOut(duration: 0.24)) { exitOpacity = 0 }
        try await Task.sleep(for: .milliseconds(240))
      }
      launch.finish()
    } catch {
      // Disappearance/background cancellation must never leave a blocking overlay.
      launch.finish()
    }
  }
}
