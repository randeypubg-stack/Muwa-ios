import SwiftUI

@main
struct MuwaNasheedsApp: App {
  @Environment(\.scenePhase) private var scenePhase

  @StateObject private var launch: LaunchPresentation
  @StateObject private var library: LibraryStore
  @StateObject private var downloads: DownloadManager
  @StateObject private var premium: PremiumManager
  @StateObject private var player: PlayerManager
  @StateObject private var subtitles: SubtitleManager
  @StateObject private var auth: AuthManager

  init() {
    _launch = StateObject(wrappedValue: LaunchPresentation())
    _ = Diagnostics.shared
    let library = LibraryStore()
    let downloads = DownloadManager()
    let premium = PremiumManager()
    premium.reportError = { Diagnostics.shared.record("premium", error: $0) }
    _library = StateObject(wrappedValue: library)
    _downloads = StateObject(wrappedValue: downloads)
    _premium = StateObject(wrappedValue: premium)
    let player = PlayerManager(library: library, downloads: downloads, premium: premium)
    _player = StateObject(wrappedValue: player)
    CarPlayCoordinator.shared.configure(player: player, library: library, downloads: downloads)
    _subtitles = StateObject(wrappedValue: SubtitleManager())
    _auth = StateObject(wrappedValue: AuthManager())
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(launch)
        .environmentObject(player)
        .environmentObject(library)
        .environmentObject(downloads)
        .environmentObject(premium)
        .environmentObject(subtitles)
        .environmentObject(auth)
        .preferredColorScheme(.dark)
        .task { await auth.restore() }
        .onChange(of: auth.user?.id, initial: true) { _, id in premium.setAccount(id) }
        .task { await premium.load() }
        .onChange(of: scenePhase) { _, phase in
          player.handleScenePhase(phase)
          if phase == .active { Task { await premium.refreshEntitlements() } }
        }
    }
  }
}
