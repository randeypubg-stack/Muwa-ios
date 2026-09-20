import SwiftUI

struct RootView: View {
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var auth: AuthManager

  @State private var selection: AppTab = .home
  @State private var fullPlayerPresented = false
  @State private var playerCollapseProgress: CGFloat = 0
  @State private var searchPresented = false
  @State private var requestedLibraryDestination: LibraryDestination?

  @Namespace private var playerTransition

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
          openFullPlayer()
        }
      })
    }
  }

  private var appShell: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
      let reveal = min(max(playerCollapseProgress, 0), 1)

      ZStack {
        shellContent(layout: layout)
          .blur(radius: fullPlayerPresented ? 6.5 * (1 - reveal) : 0)
          .scaleEffect(fullPlayerPresented ? 0.986 + (0.014 * reveal) : 1)
          .animation(.linear(duration: 0.06), value: playerCollapseProgress)

        if fullPlayerPresented {
          FullPlayerView(
            selection: $selection,
            transitionNamespace: playerTransition,
            collapseProgress: $playerCollapseProgress,
            onCollapse: collapseFullPlayer
          )
          .zIndex(30)
          .transition(.identity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func shellContent(layout: AdaptiveLayout) -> some View {
    ZStack {
      AppBackground().ignoresSafeArea()

      Group {
        switch selection {
        case .home:
          HomeView(
            openPlayer: openFullPlayer,
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
    .safeAreaInset(edge: .bottom, spacing: 10) {
      VStack(spacing: 10) {
        if player.currentTrack != nil {
          MiniPlayerView(
            openPlayer: openFullPlayer,
            transitionNamespace: playerTransition,
            isExpanded: fullPlayerPresented
          )
          .opacity(
            fullPlayerPresented
              ? min(1, max(0.02, playerCollapseProgress * 1.45))
              : 1
          )
        }

        BottomBar(
          selection: $selection,
          playerActive: false,
          openPlayer: openFullPlayer
        )
        .opacity(
          fullPlayerPresented
            ? min(1, max(0, playerCollapseProgress * 1.25))
            : 1
        )
      }
      .frame(maxWidth: layout.bottomChromeMaxWidth)
      .padding(.horizontal, layout.horizontalPadding)
      .padding(.bottom, layout.isCompactLandscapePhone ? 4 : 10)
      .frame(maxWidth: .infinity)
      .allowsHitTesting(!fullPlayerPresented)
    }
  }

  private func openFullPlayer() {
    playerCollapseProgress = 0
    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
      fullPlayerPresented = true
    }
  }

  private func collapseFullPlayer() {
    withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88)) {
      playerCollapseProgress = 1
      fullPlayerPresented = false
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
      if !fullPlayerPresented {
        playerCollapseProgress = 0
      }
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
