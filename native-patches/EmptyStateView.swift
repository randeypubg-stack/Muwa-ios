import SwiftUI

struct EmptyStateView: View {
  let icon: String
  let title: String
  let message: String
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: 20) {
      ZStack {
        RoundedRectangle(cornerRadius: 26).fill(MuwaPalette.blue.opacity(0.08))
          .frame(width: 92, height: 92).rotationEffect(.degrees(-12)).offset(x: -10, y: 3)
        RoundedRectangle(cornerRadius: 26)
          .fill(LinearGradient(colors: [MuwaPalette.ice.opacity(0.18), MuwaPalette.blue.opacity(0.07)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(width: 88, height: 88)
          .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
        Image(systemName: icon).font(.system(size: 32, weight: .medium)).foregroundStyle(MuwaPalette.ice)
      }
      .frame(height: 108)
      .accessibilityHidden(true)

      VStack(spacing: 10) {
        Text(title).font(MuwaTypography.section).foregroundStyle(MuwaPalette.text)
        Text(message).font(MuwaTypography.detail).foregroundStyle(MuwaPalette.secondary)
          .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: 360)

      if let actionTitle, let action {
        Button(action: action) {
          Text(actionTitle).font(MuwaTypography.title).foregroundStyle(MuwaPalette.background)
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 340)
            .background(MuwaPalette.ice, in: RoundedRectangle(cornerRadius: MuwaRadius.control))
        }
        .buttonStyle(MuwaPressStyle())
        .padding(.top, 4)
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 32)
    .frame(maxWidth: .infinity)
    .nativeCard(cornerRadius: MuwaRadius.card)
    .overlay(RoundedRectangle(cornerRadius: MuwaRadius.card).strokeBorder(.white.opacity(0.06), lineWidth: 0.75))
  }
}
