import SwiftUI
import UIKit

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
      let windowInsets = activeWindowSafeAreaInsets
      let safeTop = max(proxy.safeAreaInsets.top, windowInsets.top)
      let safeBottom = max(proxy.safeAreaInsets.bottom, windowInsets.bottom)
      let safeLeading = max(proxy.safeAreaInsets.leading, windowInsets.left)
      let safeTrailing = max(proxy.safeAreaInsets.trailing, windowInsets.right)
      let chromeSideInset = max(
        layout.horizontalPadding,
        safeLeading,
        safeTrailing
      )

      let chromeLimit = layout.bottomChromeMaxWidth.isFinite
        ? layout.bottomChromeMaxWidth
        : max(0, layout.viewportWidth - layout.horizontalPadding * 2)

      let chromeWidth = min(
        chromeLimit,
        max(0, layout.viewportWidth - chromeSideInset * 2)
      )

      let chromeDrop: CGFloat =
        layout.isPhone
        ? max(safeBottom - 5, 11)
        : 0

      ZStack(alignment: .bottom) {
        tabContent
          .blur(radius: 1.10 * progress)
          .scaleEffect(1 - (0.003 * progress))

        if player.hasStartedPlaybackThisSession, player.currentTrack != nil {
          MorphingPlayerView(
            selection: $selection,
            expansion: $playerExpansion,
            chromeDrop: chromeDrop,
            safeTopInset: safeTop,
            safeBottomInset: safeBottom,
            safeLeadingInset: safeLeading,
            safeTrailingInset: safeTrailing
          )
          .ignoresSafeArea(
            .container,
            edges: layout.isLandscape ? .horizontal : []
          )
          .opacity(Double(min(1, progress * 10)))
          .allowsHitTesting(progress > 0.004)
          .zIndex(20)
        }

        VStack(spacing: 8) {
          if player.hasStartedPlaybackThisSession, player.currentTrack != nil {
            MiniPlayerView(openPlayer: expandPlayer)
              .opacity(Double(1 - smoothStep(progress / 0.18)))
              .allowsHitTesting(progress < 0.08)
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
          .padding(.horizontal, layout.isPhone ? 4 : 0)
          .offset(y: layout.isPhone ? -3 : 0)
        }
        .frame(width: chromeWidth)
        .padding(.bottom, layout.isPhone ? 6 : 0)
        .offset(y: chromeDrop)
        .zIndex(40)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .coordinateSpace(name: "playerContainer")
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
    guard player.hasStartedPlaybackThisSession, player.currentTrack != nil else { return }

    withAnimation(
      .spring(response: 0.50, dampingFraction: 0.94, blendDuration: 0.12)
    ) {
      playerExpansion = 1
    }
  }

  private func collapsePlayer() {
    withAnimation(
      .spring(response: 0.48, dampingFraction: 0.96, blendDuration: 0.14)
    ) {
      playerExpansion = 0
    }
  }

  private var activeWindowSafeAreaInsets: UIEdgeInsets {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .flatMap { $0.windows }
      .first(where: \ .isKeyWindow)?
      .safeAreaInsets ?? .zero
  }

  private func smoothStep(_ value: CGFloat) -> CGFloat {
    let x = min(1, max(0, value))
    return x * x * (3 - (2 * x))
  }
}

private struct LaunchGateView: View {
  @State private var reveal = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      ZStack {
        Circle()
          .stroke(.white.opacity(0.10), lineWidth: 1)
          .frame(width: 132, height: 132)
          .scaleEffect(reveal ? 1.26 : 0.72)
          .opacity(reveal ? 0 : 0.62)

        Image("AppMark")
          .resizable()
          .scaledToFit()
          .frame(width: 92, height: 92)
          .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
          .scaleEffect(reveal ? 1 : 0.84)
          .opacity(reveal ? 1 : 0.18)
          .shadow(
            color: .white.opacity(reveal ? 0.14 : 0),
            radius: reveal ? 18 : 0
          )
      }
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.58)) {
        reveal = true
      }
    }
  }
}

enum AppTab: Hashable {
  case home, library, profile
}

