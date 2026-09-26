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
      if args.contains("--audit-profile") { selection = .profile }
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

