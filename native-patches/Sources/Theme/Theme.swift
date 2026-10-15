import SwiftUI

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
