import SwiftUI

struct ScreenHeader: View {
  let title: String
  var subtitle: String? = nil
  var showSearch = true
  var searchAction: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(MuwaTypography.display)
        if let subtitle {
          Text(subtitle)
            .font(MuwaTypography.caption)
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
