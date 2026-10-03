"""Inject simulator-only review fixtures into the disposable CI source copy."""
from pathlib import Path
import sys
root=Path(sys.argv[1])
app=root/'Sources/App/MuwaNasheedsApp.swift'
s=app.read_text()
s=s.replace('.task { await auth.restore() }', '''.task {
          if ProcessInfo.processInfo.arguments.contains("--audit-launch") {
            await auth.restore()
          } else {
            auth.continueAsGuest()
          }
        }''')
s=s.replace('.task { await premium.load() }', '')
s=s.replace('AuthManager()', 'AuthManager(service: ProcessInfo.processInfo.arguments.contains("--audit-launch") ? HeldLaunchAuthService() : AuthService.shared)')
s += """
// Disposable Simulator-only service. Release source/IPA were packaged before
// fixture injection. A real pending session keeps the original bug reproducible.
private actor HeldLaunchAuthService: AuthServing {
  func restoreSession() async throws -> AuthUser? {
    try? String(ProcessInfo.processInfo.processIdentifier).write(to: URL.documentsDirectory.appendingPathComponent("launch-auth-pending.txt"), atomically: true, encoding: .utf8)
    try await Task.sleep(for: .seconds(45))
    try? String(ProcessInfo.processInfo.processIdentifier).write(to: URL.documentsDirectory.appendingPathComponent("launch-auth-finished.txt"), atomically: true, encoding: .utf8)
    return nil
  }
  func login(email: String, password: String) async throws -> AuthUser { throw URLError(.notConnectedToInternet) }
  func register(displayName: String, email: String, password: String) async throws -> AuthUser { throw URLError(.notConnectedToInternet) }
  func logout() async throws {}
}
"""
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
      if args.contains("--audit-profile") { selection = .profile }; if args.contains("--audit-search") { searchPresented = true }
      if args.contains("--audit-library") || args.contains("--audit-library-empty") || args.contains("--audit-playlist-create") {
        selection = .library
        requestedLibraryDestination = .playlist
        if args.contains("--audit-library-empty") || args.contains("--audit-playlist-create") {
          for playlist in library.playlists { library.deletePlaylist(playlist.id) }
        } else if library.playlists.isEmpty {
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
      try? String(ProcessInfo.processInfo.processIdentifier).write(to: URL.documentsDirectory.appendingPathComponent("preview-ready.txt"), atomically: true, encoding: .utf8)
      // A cover download must not postpone selection of the screen under review.
      if let url = Track.catalog[0].artworkURL {
        let cover = await ArtworkImageStore.shared.image(for: url)
        let backdrop = await ArtworkImageStore.shared.image(for: url, backdrop: true)
        let report = "cover=\\(cover != nil); backdrop=\\(backdrop != nil); size=\\(backdrop?.size ?? .zero)"
        try? report.write(to: URL.documentsDirectory.appendingPathComponent("artwork-check.txt"), atomically: true, encoding: .utf8)
        if let data = backdrop?.pngData() {
          try? data.write(to: URL.documentsDirectory.appendingPathComponent("cached-backdrop.png"))
        }
      }
    }
'''+needle)
s=s.replace('      .coordinateSpace(name: "playerContainer")', '      .coordinateSpace(name: "playerContainer")\n      .onAppear {\n        if ProcessInfo.processInfo.arguments.contains("--audit-launch") {\n          precondition(auth.state == .checking, "Session finished before startup review")\n          try? String(ProcessInfo.processInfo.processIdentifier).write(to: URL.documentsDirectory.appendingPathComponent("launch-home-mounted.txt"), atomically: true, encoding: .utf8)\n        }\n      }', 1)
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

# Confirm queue presentation, rather than accepting a still-visible Home screen.
p=root/'Sources/Views/Player/QueueView.swift'
s=p.read_text()
needle='    .presentationDetents([.medium, .large])'
assert needle in s
s=s.replace(needle, '''    .onAppear {
      if ProcessInfo.processInfo.arguments.contains("--audit-queue") {
        try? String(ProcessInfo.processInfo.processIdentifier).write(to: URL.documentsDirectory.appendingPathComponent("queue-ready.txt"), atomically: true, encoding: .utf8)
      }
    }
'''+needle,1)
s=s.replace('.presentationDetents([.medium, .large])', '.presentationDetents(ProcessInfo.processInfo.arguments.contains("--audit-interactions") ? [.large] : [.medium, .large])')
p.write_text(s)

# Open the actual existing create sheet for layout capture, never a stand-in.
p=root/'Sources/Views/Library/LibraryDetailView.swift'
s=p.read_text().replace('    .libraryNavigation(title: title)', '    .task { if ProcessInfo.processInfo.arguments.contains("--audit-playlist-create") { createPlaylistPresented = true } }\n    .libraryNavigation(title: title)',1)
p.write_text(s)

# Exercise the real artwork decoder/cache/backdrop with a controlled HTTPS
# response, independently of live CDN availability. Screen artwork remains the
# actual catalogue URL or its normal fallback; the test image is never a track.
p=root/'Sources/Views/Components/ArtworkView.swift'
s=p.read_text().replace('URLSession.shared.data(from: url)', 'ReviewArtworkProtocol.session.data(from: url)')
s += '''
private final class ReviewArtworkProtocol: URLProtocol, @unchecked Sendable {
  static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ReviewArtworkProtocol.self]
    return URLSession(configuration: config)
  }()
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "muwa-review.invalid" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url, let bytes = UIImage(named: "AppMark")?.pngData() else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData)); return
    }
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Type": "image/png"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: bytes)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
'''
p.write_text(s)
p=root/'Sources/App/RootView.swift'
s=p.read_text().replace('if let url = Track.catalog[0].artworkURL {', 'if let url = URL(string: "https://muwa-review.invalid/cache-check.png") {')
p.write_text(s)

# Real AVPlayer, paused on a generated local PCM fixture, for UI review only.
# Production streaming/offline source selection is packaged before this step.
# A missing published backend must not cover CarPlay design review with an
# unrelated network-error alert. Live media availability is reported separately.
import base64, io, wave
buffer=io.BytesIO()
with wave.open(buffer,'wb') as audio:
    audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(8000)
    audio.writeframes(bytes(16000))
p=root/'Sources/Services/PlayerManager.swift'
s=p.read_text().replace('AVPlayerItem(url: playbackURL)', 'AVPlayerItem(url: ProcessInfo.processInfo.arguments.contains("--audit-player") ? ReviewAudioFixture.url : playbackURL)')
s += '''
private enum ReviewAudioFixture {
  static let url: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("muwa-review-pause.wav")
    let bytes = Data(base64Encoded: "'''+base64.b64encode(buffer.getvalue()).decode()+'''")!
    try! bytes.write(to: url, options: .atomic)
    return url
  }()
}
'''
p.write_text(s)
