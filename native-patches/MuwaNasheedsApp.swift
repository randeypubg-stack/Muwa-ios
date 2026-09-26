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
    let library = LibraryStore()
    let downloads = DownloadManager()
    let premium = PremiumManager()
    _library = StateObject(wrappedValue: library)
    _downloads = StateObject(wrappedValue: downloads)
    _premium = StateObject(wrappedValue: premium)
    _player = StateObject(
      wrappedValue: PlayerManager(library: library, downloads: downloads, premium: premium))
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
        .task { await premium.load() }
        .onChange(of: scenePhase) { _, phase in
          player.handleScenePhase(phase)
          if phase == .active { Task { await premium.refreshEntitlements() } }
        }
    }
  }
}


