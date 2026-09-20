import SwiftUI

struct BottomBar: View {
  @Binding var selection: AppTab
  var playerActive = false
  let openPlayer: () -> Void
  var selectTab: ((AppTab) -> Void)? = nil

  @Namespace private var highlight
  @State private var dragSlot: Int?

  var body: some View {
    GeometryReader { proxy in
      HStack(spacing: 2) {
        item(.home, "Главная", "house.fill")
        playerItem
        item(.library, "Библиотека", "books.vertical.fill")
        item(.profile, "Профиль", "person.fill")
      }
      .frame(height: 58)
      .padding(5)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .stroke(.white.opacity(0.14), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
      .contentShape(Rectangle())
      .simultaneousGesture(
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
          .onChanged { value in
            updateDrag(at: value.location.x, width: proxy.size.width)
          }
          .onEnded { _ in
            dragSlot = nil
          }
      )
    }
    .frame(height: 68)
  }

  private var playerItem: some View {
    Button(action: openPlayer) {
      tabLabel("Плеер", "play.fill", active: playerActive)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  private func item(_ tab: AppTab, _ title: String, _ systemImage: String) -> some View {
    let active = !playerActive && selection == tab
    return Button {
      activate(tab)
    } label: {
      tabLabel(title, systemImage, active: active)
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  private func activate(_ tab: AppTab) {
    if let selectTab {
      selectTab(tab)
    } else {
      selection = tab
    }
  }

  private func updateDrag(at x: CGFloat, width: CGFloat) {
    guard width > 0 else { return }

    let normalized = min(max(x / width, 0), 0.9999)
    let slot = min(3, max(0, Int(normalized * 4)))
    guard slot != dragSlot else { return }
    dragSlot = slot

    withAnimation(.snappy(duration: 0.22)) {
      switch slot {
      case 0:
        activate(.home)
      case 1:
        if !playerActive {
          openPlayer()
        }
      case 2:
        activate(.library)
      default:
        activate(.profile)
      }
    }
  }

  private func tabLabel(_ title: String, _ systemImage: String, active: Bool) -> some View {
    VStack(spacing: 3) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
      Text(title)
        .font(.system(size: 9, weight: .medium))
    }
    .foregroundStyle(active ? .white : .white.opacity(0.66))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      if active {
        RoundedRectangle(cornerRadius: 23, style: .continuous)
          .fill(
            LinearGradient(
              colors: [.white.opacity(0.12), .white.opacity(0.045)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
              .stroke(.white.opacity(0.12), lineWidth: 1)
          )
          .matchedGeometryEffect(id: "active-tab", in: highlight)
      }
    }
    .contentShape(Rectangle())
    .animation(.snappy(duration: 0.32), value: active)
  }
}
