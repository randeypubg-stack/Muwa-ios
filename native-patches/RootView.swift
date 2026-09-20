import SwiftUI

struct RootView: View {
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var auth: AuthManager

  @State private var selection: AppTab = .home
  @State private var playerExpansion: CGFloat = 0
  @State private var searchPresented = false
  @State private var requestedLibraryDestination: LibraryDestination?

  var body: some View {
    ZStack {
      if auth.registrationJustCompleted {
        RegistrationSuccessView()
          .transition(.opacity.combined(with: .scale(scale: 0.985)))
      } else {
        switch auth.state {
        case .checking:
          LaunchGateView()
            .transition(.opacity)

        case .signedOut:
          AuthFlowView()
            .transition(.opacity)

        case .guest, .authenticated:
          appShell
            .transition(.opacity)
        }
      }
    }
    .animation(.easeInOut(duration: 0.24), value: auth.state)
    .animation(.easeInOut(duration: 0.24), value: auth.registrationJustCompleted)
    .fullScreenCover(isPresented: $searchPresented) {
      SearchView(openPlayer: {
        searchPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
          expandPlayer()
        }
      })
    }
  }

  private var appShell: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
      let progress = min(max(playerExpansion, 0), 1)
      let chromeLimit = layout.bottomChromeMaxWidth.isFinite
        ? layout.bottomChromeMaxWidth
        : max(0, layout.viewportWidth - layout.horizontalPadding * 2)
      let chromeWidth = min(
        chromeLimit,
        max(0, layout.viewportWidth - layout.horizontalPadding * 2)
      )

      ZStack(alignment: .bottom) {
        tabContent
          .blur(radius: 1.35 * progress)
          .scaleEffect(1 - (0.004 * progress))

        if player.currentTrack != nil {
          MorphingPlayerView(
            selection: $selection,
            expansion: $playerExpansion
          )
          .ignoresSafeArea()
          .zIndex(20)
        }

        BottomBar(
          selection: $selection,
          playerActive: progress > 0.56,
          openPlayer: expandPlayer,
          selectTab: { tab in
            selection = tab
            if progress > 0.001 {
              collapsePlayer()
            }
          }
        )
        .frame(width: chromeWidth)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.bottom, layout.isPhone ? 2 : max(proxy.safeAreaInsets.bottom, 10))
        .zIndex(40)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(AppBackground().ignoresSafeArea())
    }
  }

  @ViewBuilder
  private var tabContent: some View {
    Group {
      switch selection {
      case .home:
        HomeView(
          openPlayer: expandPlayer,
          openSearch: { searchPresented = true }
        )

      case .library:
        LibraryView(
          requestedDestination: $requestedLibraryDestination,
          openSearch: { searchPresented = true }
        )

      case .profile:
        ProfileView(
          openSearch: { searchPresented = true }
        )
      }
    }
    .transition(.opacity)
  }

  private func expandPlayer() {
    withAnimation(
      .spring(response: 0.50, dampingFraction: 0.92, blendDuration: 0.10)
    ) {
      playerExpansion = 1
    }
  }

  private func collapsePlayer() {
    withAnimation(
      .spring(response: 0.46, dampingFraction: 0.94, blendDuration: 0.12)
    ) {
      playerExpansion = 0
    }
  }
}

private struct LaunchGateView: View {
  var body: some View {
    ZStack {
      AppBackground().ignoresSafeArea()

      VStack(spacing: 16) {
        Image("AppMark")
          .resizable()
          .scaledToFit()
          .frame(width: 94, height: 94)
          .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
          .shadow(color: .blue.opacity(0.18), radius: 24, y: 12)

        ProgressView()
          .tint(.white.opacity(0.75))
      }
    }
  }
}

enum AppTab: Hashable {
  case home, library, profile
}
