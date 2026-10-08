import SwiftUI

@main
struct MuwaNasheedsApp: App {
  @Environment(\.scenePhase) private var scenePhase

  @StateObject private var library: LibraryStore
  @StateObject private var downloads: DownloadManager
  @StateObject private var premium: PremiumManager
  @StateObject private var player: PlayerManager
  @StateObject private var subtitles: SubtitleManager
  @StateObject private var auth: AuthManager

  init() {
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
        .environmentObject(player)
        .environmentObject(library)
        .environmentObject(downloads)
        .environmentObject(premium)
        .environmentObject(subtitles)
        .environmentObject(auth)
        .preferredColorScheme(.dark)
        .task { await auth.restore() }
        .task(id: auth.user?.id) { await CatalogStore.shared.refresh(force: true) }
         .onChange(of: auth.state, initial: true) { _, state in
          premium.setAccount(auth.user?.id)
          if state != .checking { Diagnostics.shared.setAccount(auth.user?.id) }
        }
        .task { await premium.load() }
        .onChange(of: scenePhase) { _, phase in
          player.handleScenePhase(phase)
          if phase == .active { Diagnostics.shared.flush(); Task { await premium.refreshEntitlements() }; Task { await CatalogStore.shared.refresh() } }
        }
    }
  }
}
