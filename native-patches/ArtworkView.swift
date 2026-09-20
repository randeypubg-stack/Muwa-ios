import SwiftUI

struct ArtworkView: View {
  let url: URL?
  var cornerRadius: CGFloat = 24
  var placeholderSystemImage = "waveform"

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.white.opacity(0.045))

      if let url {
        AsyncImage(
          url: url,
          transaction: Transaction(animation: .easeOut(duration: 0.22))
        ) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .transition(.opacity.combined(with: .scale(scale: 0.985)))

          case .failure:
            placeholder

          case .empty:
            MuwaArtworkLoader()

          @unknown default:
            placeholder
          }
        }
      } else {
        placeholder
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(.white.opacity(0.065), lineWidth: 1)
    )
  }

  private var placeholder: some View {
    Image(systemName: placeholderSystemImage)
      .font(.system(size: 30, weight: .medium))
      .foregroundStyle(.white.opacity(0.72))
  }
}

private struct MuwaArtworkLoader: View {
  @State private var active = false

  var body: some View {
    ZStack {
      Circle()
        .stroke(.white.opacity(0.075), lineWidth: 1)
        .frame(width: 42, height: 42)
        .scaleEffect(active ? 1.12 : 0.86)
        .opacity(active ? 0.12 : 0.55)

      Image(systemName: "waveform")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
        .scaleEffect(active ? 1.04 : 0.94)
        .opacity(active ? 0.92 : 0.50)
    }
    .onAppear {
      guard !active else { return }
      withAnimation(
        .easeInOut(duration: 0.82)
          .repeatForever(autoreverses: true)
      ) {
        active = true
      }
    }
    .accessibilityLabel("Загрузка обложки")
  }
}

struct ArtworkBackdrop: View {
  let url: URL?

  var body: some View {
    ZStack {
      AppBackground()

      if let url {
        AsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image
              .resizable()
              .scaledToFill()
              .blur(radius: 44)
              .saturation(1.18)
              .opacity(0.54)
              .scaleEffect(1.22)
          }
        }
      }

      LinearGradient(
        colors: [.black.opacity(0.08), .black.opacity(0.50), .black.opacity(0.90)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .clipped()
  }
}
