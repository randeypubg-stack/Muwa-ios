import SwiftUI

struct AppBackground: View {
  @State private var animateGlow = false

  var body: some View {
    GeometryReader { proxy in
      let span = max(proxy.size.width, proxy.size.height)

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

        Circle()
          .fill(Color(red: 0.18, green: 0.36, blue: 0.72).opacity(0.18))
          .frame(width: span * 0.92, height: span * 0.92)
          .blur(radius: span * 0.18)
          .offset(
            x: animateGlow ? proxy.size.width * 0.12 : -proxy.size.width * 0.10,
            y: animateGlow ? -proxy.size.height * 0.15 : -proxy.size.height * 0.10
          )
          .scaleEffect(animateGlow ? 1.04 : 0.96)

        Circle()
          .fill(Color.cyan.opacity(0.055))
          .frame(width: span * 0.74, height: span * 0.74)
          .blur(radius: span * 0.17)
          .offset(
            x: animateGlow ? -proxy.size.width * 0.14 : proxy.size.width * 0.10,
            y: animateGlow ? proxy.size.height * 0.28 : proxy.size.height * 0.34
          )
          .scaleEffect(animateGlow ? 0.97 : 1.03)

        LinearGradient(
          colors: [
            .clear,
            Color.black.opacity(0.18),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .drawingGroup(opaque: false, colorMode: .linear)
      .onAppear {
        guard !animateGlow else { return }
        withAnimation(
          .easeInOut(duration: 18)
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
