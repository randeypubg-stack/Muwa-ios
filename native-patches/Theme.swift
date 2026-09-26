import SwiftUI

struct AppBackground: View {
  @State private var animateGlow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    GeometryReader { proxy in
      let span = max(proxy.size.width, proxy.size.height)

      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.003, green: 0.004, blue: 0.006),
            Color(red: 0.006, green: 0.007, blue: 0.010),
            Color(red: 0.002, green: 0.002, blue: 0.003),
          ],
          startPoint: .top,
          endPoint: .bottom
        )

        Circle()
          .fill(RadialGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.045), .clear], center: .center, startRadius: 0, endRadius: span * 0.46))
          .frame(width: span * 0.92, height: span * 0.92)
          .offset(
            x: animateGlow ? proxy.size.width * 0.12 : -proxy.size.width * 0.10,
            y: animateGlow ? -proxy.size.height * 0.15 : -proxy.size.height * 0.10
          )
          .scaleEffect(animateGlow ? 1.04 : 0.96)

        Circle()
          .fill(RadialGradient(colors: [.white.opacity(0.012), .clear], center: .center, startRadius: 0, endRadius: span * 0.37))
          .frame(width: span * 0.74, height: span * 0.74)
          .offset(
            x: animateGlow ? -proxy.size.width * 0.14 : proxy.size.width * 0.10,
            y: animateGlow ? proxy.size.height * 0.28 : proxy.size.height * 0.34
          )
          .scaleEffect(animateGlow ? 0.97 : 1.03)

        LinearGradient(
          colors: [
            .clear,
            Color.black.opacity(0.48),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .task(id: scenePhase == .active && !reduceMotion) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { animateGlow = false }
        guard scenePhase == .active, !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) {
          animateGlow = true
        }
      }
    }
  }
}

struct ScreenHeader: View {
  let title: String
  var subtitle: String? = nil
  var showSearch = true
  var searchAction: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 32, weight: .bold, design: .rounded))
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      if showSearch, let searchAction {
        Button(action: searchAction) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44)
            .glassPanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Поиск")
      }
    }
  }
}

extension View {
  func glassPanel(cornerRadius: CGFloat = 28) -> some View {
    modifier(MuwaGlassSurface(cornerRadius: cornerRadius))
  }

  func nativeCard(cornerRadius: CGFloat = 24) -> some View {
    self
      .background(
        LinearGradient(
          colors: [.white.opacity(0.075), .white.opacity(0.025)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
  }
}


// Static reflections keep the glass treatment light during playback.
private struct MuwaGlassSurface: ViewModifier {
  let cornerRadius: CGFloat
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    content
      .background {
        if reduceTransparency {
          shape.fill(Color(red: 0.10, green: 0.11, blue: 0.13))
        } else {
          shape.fill(.ultraThinMaterial)
            .overlay {
              shape.fill(LinearGradient(
                colors: [.white.opacity(0.09), .white.opacity(0.015), Color(red: 0.60, green: 0.74, blue: 0.94).opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
              ))
            }
        }
      }
      .overlay {
        shape.strokeBorder(
          LinearGradient(
            colors: [.white.opacity(contrast == .increased ? 0.55 : 0.30), .white.opacity(0.06), .white.opacity(0.14)],
            startPoint: .topLeading, endPoint: .bottomTrailing
          ), lineWidth: 0.75
        )
        .allowsHitTesting(false)
      }
  }
}

