import SwiftUI

struct AppBackground: View {
  @State private var animateGlow = false

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.035, green: 0.075, blue: 0.12),
            Color(red: 0.018, green: 0.038, blue: 0.065),
            Color(red: 0.008, green: 0.014, blue: 0.025),
          ],
          startPoint: .top,
          endPoint: .bottom
        )

        RadialGradient(
          colors: [
            Color(red: 0.24, green: 0.43, blue: 0.78).opacity(0.24),
            .clear,
          ],
          center: .center,
          startRadius: 0,
          endRadius: max(proxy.size.width, proxy.size.height) * 0.48
        )
        .frame(
          width: proxy.size.width * 1.35,
          height: proxy.size.height * 0.72
        )
        .offset(
          x: animateGlow ? proxy.size.width * 0.12 : -proxy.size.width * 0.10,
          y: animateGlow ? -proxy.size.height * 0.08 : -proxy.size.height * 0.16
        )
        .scaleEffect(animateGlow ? 1.08 : 0.94)

        RadialGradient(
          colors: [
            Color.cyan.opacity(0.075),
            .clear,
          ],
          center: .center,
          startRadius: 0,
          endRadius: max(proxy.size.width, proxy.size.height) * 0.42
        )
        .frame(
          width: proxy.size.width * 1.10,
          height: proxy.size.height * 0.66
        )
        .offset(
          x: animateGlow ? -proxy.size.width * 0.16 : proxy.size.width * 0.08,
          y: animateGlow ? proxy.size.height * 0.31 : proxy.size.height * 0.22
        )
        .scaleEffect(animateGlow ? 0.94 : 1.06)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
      .onAppear {
        guard !animateGlow else { return }
        withAnimation(
          .easeInOut(duration: 14)
            .repeatForever(autoreverses: true)
        ) {
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
    self
      .background(
        .ultraThinMaterial,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(.white.opacity(0.10), lineWidth: 1)
      )
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
