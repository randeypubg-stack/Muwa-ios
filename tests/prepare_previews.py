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
      if args.contains("--audit-player") {
        player.play(Track.catalog[0], autoplay: false)
        playerExpansion = 1
      }
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
