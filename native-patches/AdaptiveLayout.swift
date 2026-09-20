import SwiftUI
import UIKit

struct AdaptiveLayout {
  let size: CGSize
  let safeArea: EdgeInsets

  private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

  var isPhone: Bool { idiom == .phone }
  var isPad: Bool { idiom == .pad }

  private var activeOrientation: UIInterfaceOrientation? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first(where: { $0.activationState == .foregroundActive })?
      .interfaceOrientation
  }

  var isLandscape: Bool {
    if let orientation = activeOrientation {
      if orientation.isLandscape { return true }
      if orientation.isPortrait { return false }
    }

    if isPhone {
      let screen = UIScreen.main.bounds.size
      if screen.width != screen.height {
        return screen.width > screen.height
      }
    }

    return size.width > size.height
  }

  // On iPhone, clamp SwiftUI's proposed geometry to the actual physical screen
  // in points. This prevents a fullScreenCover/window proposal from being treated
  // like an iPad-sized canvas and shifting content off-screen.
  var viewportWidth: CGFloat {
    let proposed = max(size.width, 1)
    guard isPhone else { return proposed }

    let screen = UIScreen.main.bounds.size
    let portraitWidth = min(screen.width, screen.height)
    let landscapeWidth = max(screen.width, screen.height)
    let physicalWidth = isLandscape ? landscapeWidth : portraitWidth
    return min(proposed, physicalWidth)
  }

  var viewportHeight: CGFloat {
    let proposed = max(size.height, 1)
    guard isPhone else { return proposed }

    let screen = UIScreen.main.bounds.size
    let portraitHeight = max(screen.width, screen.height)
    let landscapeHeight = min(screen.width, screen.height)
    let physicalHeight = isLandscape ? landscapeHeight : portraitHeight
    return min(proposed, physicalHeight)
  }

  var isCompactLandscapePhone: Bool {
    isPhone && isLandscape && viewportHeight < 520
  }

  var isWide: Bool {
    isPad && viewportWidth >= 700
  }

  var isExtraWide: Bool {
    isPad && viewportWidth >= 1000
  }

  var horizontalPadding: CGFloat {
    let width = viewportWidth
    if isPhone {
      return 2
    }
    if width < 600 { return isLandscape ? 22 : 18 }
    if width >= 1000 { return 40 }
    return 28
  }

  var contentMaxWidth: CGFloat {
    let width = viewportWidth
    if isPhone {
      return max(0, min(width - horizontalPadding * 2, 620))
    }
    if width >= 1000 { return min(width - horizontalPadding * 2, 1180) }
    if width >= 700 { return min(width - horizontalPadding * 2, 980) }
    return max(0, min(width - horizontalPadding * 2, 620))
  }

  // Split player is iPad-only. An iPhone must never enter an iPad-style
  // two-column player, even if a hosting controller reports an oversized width.
  var playerUsesSplitLayout: Bool {
    isPad && viewportWidth >= 700
  }

  var playerArtworkSize: CGFloat {
    let width = viewportWidth
    let height = viewportHeight

    if isPad {
      return min(420, height * 0.48, width * (playerUsesSplitLayout ? 0.38 : 0.68))
    }
    if isLandscape {
      return min(250, height * 0.54, width * 0.42)
    }
    return min(310, width * 0.68)
  }

  var libraryColumns: Int {
    let width = viewportWidth
    if isPhone {
      if isLandscape && width >= 700 { return 3 }
      return 2
    }
    if width >= 1000 { return 4 }
    if width >= 700 { return 4 }
    if width >= 560 { return 3 }
    return 2
  }

  var homeRecommendationColumns: Int {
    let width = viewportWidth
    if isPhone { return isLandscape && width >= 700 ? 3 : 2 }
    if width >= 1000 { return 4 }
    if width >= 700 { return 3 }
    return 2
  }

  var listColumns: Int {
    (!isPhone && viewportWidth >= 900) ? 2 : 1
  }

  var bottomChromeMaxWidth: CGFloat {
    if isPhone {
      return max(0, viewportWidth - horizontalPadding * 2)
    }
    if viewportWidth >= 700 { return 720 }
    if isLandscape { return 680 }
    return .infinity
  }

  var authUsesSplitLayout: Bool {
    guard !isPhone else { return false }
    return viewportWidth >= 780 || (isLandscape && viewportWidth >= 620 && viewportHeight <= 620)
  }

  var authFormMaxWidth: CGFloat {
    if isCompactLandscapePhone { return min(390, viewportWidth - horizontalPadding * 2) }
    if isPad { return 460 }
    return min(430, viewportWidth - horizontalPadding * 2)
  }
}

struct AdaptiveFrame: ViewModifier {
  let maxWidth: CGFloat

  func body(content: Content) -> some View {
    content
      .frame(maxWidth: maxWidth)
      .frame(maxWidth: .infinity, alignment: .center)
  }
}

extension View {
  func adaptiveFrame(maxWidth: CGFloat) -> some View {
    modifier(AdaptiveFrame(maxWidth: maxWidth))
  }
}
