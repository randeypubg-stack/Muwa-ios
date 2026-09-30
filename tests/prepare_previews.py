"""Inject simulator-only review fixtures into the disposable CI source copy."""
from pathlib import Path
import sys
root=Path(sys.argv[1])
app=root/'Sources/App/MuwaNasheedsApp.swift'
s=app.read_text()
s=s.replace('.task { await auth.restore() }', '''.task {
          auth.continueAsGuest()
        }''')
s=s.replace('.task { await premium.load() }', '')
app.write_text(s)
view=root/'Sources/App/RootView.swift'
s=view.read_text().replace('@EnvironmentObject private var auth: AuthManager',
 '@EnvironmentObject private var auth: AuthManager\n  @EnvironmentObject private var library: LibraryStore')
needle='    .animation(.easeInOut(duration: 0.24), value: auth.state)'
assert needle in s
s=s.replace(needle, '''    .task {
      player.duration = 100
      var broadUpdates = 0
      let subscription = player.objectWillChange.sink { broadUpdates += 1 }
      for tick in 1...100 {
        player.currentTime = Double(tick)
        player.progress = Double(tick) / 100
      }
      precondition(broadUpdates == 0, "Clock invalidated full player UI")
      let proof = URL.documentsDirectory.appendingPathComponent("clock-check.txt")
      try? "100 ticks; PlayerManager notifications: 0".write(to: proof, atomically: true, encoding: .utf8)
      subscription.cancel()
      player.duration = 0
      player.currentTime = 0
      print("PASS: 100 playback ticks produced zero PlayerManager notifications")
      let args = ProcessInfo.processInfo.arguments
      if let url = Track.catalog[0].artworkURL {
        let cover = await ArtworkImageStore.shared.image(for: url)
        let backdrop = await ArtworkImageStore.shared.image(for: url, backdrop: true)
        let report = "cover=\\(cover != nil); backdrop=\\(backdrop != nil); size=\\(backdrop?.size ?? .zero)"
        try? report.write(to: URL.documentsDirectory.appendingPathComponent("artwork-check.txt"), atomically: true, encoding: .utf8)
        if let data = backdrop?.pngData() {
          try? data.write(to: URL.documentsDirectory.appendingPathComponent("cached-backdrop.png"))
        }
      }
      if args.contains("--audit-player") {
        player.play(Track.catalog[0], autoplay: false)
        playerExpansion = 1
      }
      if args.contains("--audit-profile") { selection = .profile }; if args.contains("--audit-search") { searchPresented = true }
      if args.contains("--audit-library") {
        selection = .library
        requestedLibraryDestination = .playlist
        if library.playlists.isEmpty {
          let id = library.createPlaylist(name: "Избранные нашиды")
          for track in Track.catalog { library.addTrack(track, to: id) }
          _ = library.createPlaylist(name: "Для дороги")
        }
      }
      if args.contains("--audit-landscape") {
        try? await Task.sleep(for: .seconds(1))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
          scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
      }
    }
'''+needle)
view.write_text(s)

# AI review fixture, injected only after production IPA/source packaging.
manager=root/'Sources/Services/SubtitleManager.swift'
s=manager.read_text()
needle='  func load(_ track: Track, retry: Bool = false) async {'
fixture='\n    if ProcessInfo.processInfo.arguments.contains("--audit-ai") {\n      document = AISubtitleDocument(version: 2, id: "fixture", language: "ar", segments: [\n        AISubtitleSegment(id: "s0", start: 0, end: 8, original: "السلام عليكم ورحمة الله", words: [\n          SubtitleWord(text: "السلام", start: 0, end: 2), SubtitleWord(text: "عليكم", start: 2, end: 4),\n          SubtitleWord(text: "ورحمة", start: 4, end: 6), SubtitleWord(text: "الله", start: 6, end: 8)], timing: "estimated"),\n        AISubtitleSegment(id: "s1", start: 9, end: 15, original: "مرحبا بكم", words: [], timing: "phrase")])\n      translations["ru"] = AISubtitleTranslation(documentId: "fixture", language: "ru", segments: ["s0": "Мир вам и милость Аллаха", "s1": "Добро пожаловать"])\n      return\n    }\n'
assert needle in s
manager.write_text(s.replace(needle,needle+fixture))
player=root/'Sources/Views/Player/FullPlayerView.swift'
s=player.read_text().replace('    .onChange(of: expansion)', '    .task { if ProcessInfo.processInfo.arguments.contains("--audit-ai") { aiSubtitlesVisible = true } }\n    .onChange(of: expansion)',1)
player.write_text(s)
overlay=root/'Sources/Views/Player/PlayerSubtitleOverlay.swift'
s=overlay.read_text().replace('    .task(id: track.audioURL) { await manager.load(track) }', '    .task(id: track.audioURL) { await manager.load(track); language = .ru; if ProcessInfo.processInfo.arguments.contains("--audit-ai-expanded") { expanded = true } }')
overlay.write_text(s)
rootview=root/'Sources/App/RootView.swift'
s=rootview.read_text().replace('        playerExpansion = 1', '        playerExpansion = 1\n        if args.contains("--audit-ai") { player.currentTime = 3 }')
rootview.write_text(s)

# Build34 simulator-only Premium/promo views. Never included in distributable archive.
profile=root/'Sources/Views/Profile/ProfileView.swift'
s=profile.read_text().replace('    .sheet(isPresented: $promoPresented)', '    .task { let args = ProcessInfo.processInfo.arguments; if args.contains("--audit-settings") { settingsPresented = true }; if args.contains("--audit-premium") { premiumPresented = true }; if args.contains("--audit-promo") { promoPresented = true } }\n    .sheet(isPresented: $promoPresented)',1)
profile.write_text(s)

# Deterministic review states only; injected after Release/source packaging.
authfile=root/'Sources/Services/AuthManager.swift'
s=authfile.read_text().replace('  func continueAsGuest() {', '  func continueAsGuest() {\n    if ProcessInfo.processInfo.arguments.contains("--audit-owner") { state = .authenticated(AuthUser(id: 999, email: "preview@example.com", displayName: "Владелец", avatarUrl: nil, role: "user")); return }')
authfile.write_text(s)
premiumfile=root/'Sources/Services/PremiumManager.swift'
s=premiumfile.read_text().replace('  func load() async {', '  func load() async {\n    if ProcessInfo.processInfo.arguments.contains("--audit-premium") { return }')
needle='  static func request(_ body: [String: Any]) async throws -> MuwaPremiumResponse {'
s=s.replace(needle,needle+'\n    if ProcessInfo.processInfo.arguments.contains("--audit-owner") { return MuwaPremiumResponse(userId: 999, isPremium: true, expiresAt: nil, canManageCodes: true, code: nil, codes: [], alreadyRedeemed: nil) }')
premiumfile.write_text(s)
player=root/'Sources/Views/Player/FullPlayerView.swift'
s=player.read_text().replace('if ProcessInfo.processInfo.arguments.contains("--audit-ai") { aiSubtitlesVisible = true }','if ProcessInfo.processInfo.arguments.contains("--audit-ai") || ProcessInfo.processInfo.arguments.contains("--audit-ai-unavailable") { aiSubtitlesVisible = true }')
player.write_text(s)
manager=root/'Sources/Services/SubtitleManager.swift'
s=manager.read_text().replace('  func load(_ track: Track, retry: Bool = false) async {','  func load(_ track: Track, retry: Bool = false) async {\n    if ProcessInfo.processInfo.arguments.contains("--audit-ai-unavailable") { error = "Автоматическое распознавание пока не подключено."; return }',1)
manager.write_text(s)

# Exercise the real player actions in Simulator without entitlement bypass fixtures.
p=root/'Sources/Views/Player/FullPlayerView.swift'
s=p.read_text().replace('    .onChange(of: expansion)', '    .task { if ProcessInfo.processInfo.arguments.contains("--audit-queue") { queuePresented = true } }\n    .onChange(of: expansion)',1)
p.write_text(s)
