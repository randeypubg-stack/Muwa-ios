"""Inject simulator-only review fixtures into the disposable CI source copy."""
from pathlib import Path
import sys
root=Path(sys.argv[1])
app=root/'Sources/App/MuwaNasheedsApp.swift'
s=app.read_text()
track=root/'Sources/Models/Track.swift'
track.write_text(track.read_text()+'\n#if DEBUG\n'+Path('tests/FixtureCatalog.swift').read_text()+'\n#endif\n')
s=s.replace('let library = LibraryStore()', 'CatalogStore.shared.installReviewTracks(Track.reviewCatalog)\n    if ProcessInfo.processInfo.arguments.contains("--audit-portrait") {\n      let fixture = Track(id: "portrait", title: "Portrait crop check", artist: "Muwa", duration: 60, artworkURL: URL(string: "https://muwa-review.invalid/portrait.png"), audioURL: Track.reviewCatalog[0].audioURL)\n      CatalogStore.shared.installReviewTracks([fixture])\n    }\n    let library = LibraryStore()')
s=s.replace('.task { await auth.restore() }', '''.task {
          if ProcessInfo.processInfo.arguments.contains("--audit-launch") {
            await auth.restore()
          } else {
            auth.continueAsGuest()
          }
        }''')
s=s.replace('.task { await premium.load() }', '')
# UI fixtures keep their controlled catalog; production guest requests are covered
# by CatalogChecks and the real HTTP/PostgreSQL tests. Never fetch live data here.
s=s.replace('.task { await CatalogStore.shared.refresh(force: true) }', '')
s=s.replace('Task { await CatalogStore.shared.refresh() }', '')
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
        if args.contains("--audit-buffering") {
          try? await Task.sleep(for: .seconds(1))
          player.isPlaying = true
          player.isBuffering = true
        }
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

# Override only a disposable review environment, never the release source.
# The explicit preference also reaches the real rail and native reader sheet.
s=view.read_text()
needle='      .coordinateSpace(name: "playerContainer")'
assert s.count(needle) == 1
s=s.replace(needle, needle+'''\n      .transformEnvironment(\\.accessibilityReduceMotion) { value in
        if ProcessInfo.processInfo.arguments.contains("--audit-reduce-motion") { value = true }
      }''',1)
view.write_text(s)

# AI review fixture, injected only after production IPA/source packaging.
manager=root/'Sources/Services/SubtitleManager.swift'
s=manager.read_text()
needle='  func load(_ track: Track, retry: Bool = false) async {'
fixture='\n    if ProcessInfo.processInfo.arguments.contains("--audit-ai") {\n      document = AISubtitleDocument(version: 2, id: "fixture", language: "ar", segments: [\n        AISubtitleSegment(id: "s0", start: 0, end: 8, original: "السلام عليكم ورحمة الله", words: [\n          SubtitleWord(text: "السلام", start: 0, end: 2), SubtitleWord(text: "عليكم", start: 2, end: 4),\n          SubtitleWord(text: "ورحمة", start: 4, end: 6), SubtitleWord(text: "الله", start: 6, end: 8)], timing: "estimated"),\n        AISubtitleSegment(id: "s1", start: 9, end: 15, original: "مرحبا بكم", words: [], timing: "phrase")])\n      translations["ru"] = AISubtitleTranslation(documentId: "fixture", language: "ru", segments: ["s0": "Мир вам и милость Аллаха", "s1": "Добро пожаловать"])\n      return\n    }\n'
assert needle in s
fixture=fixture.replace('      return\n', '''      if ProcessInfo.processInfo.arguments.contains("--audit-long-caption") {
        document = AISubtitleDocument(version: 2, id: "fixture", language: "ar", segments: [
          AISubtitleSegment(id: "s0", start: 0, end: 30,
            original: "يا رب إن القلب يرجو رحمتك ويعود نحو النور حين يطول درب الحياة وتبقى في الأرواح كلمات السلام والرحمة والسكينة والأمل في كل يوم وليلة",
            words: [], timing: "phrase")])
        translations = [:]
      }
      return
''',1)
manager.write_text(s.replace(needle,needle+fixture))
player=root/'Sources/Views/Player/FullPlayerView.swift'
s=player.read_text().replace('    .onChange(of: expansion)', '    .task { if ProcessInfo.processInfo.arguments.contains("--audit-ai") { subtitlesVisible = true } }\n    .onChange(of: expansion)',1)
player.write_text(s)
overlay=root/'Sources/Views/Player/PlayerSubtitleOverlay.swift'
s=overlay.read_text().replace('      await manager.load(track)', '      await manager.load(track); if ProcessInfo.processInfo.arguments.contains("--audit-ai") { language = .ru }; if ProcessInfo.processInfo.arguments.contains("--audit-ai-expanded") { expanded = true }')
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
s=player.read_text().replace('if ProcessInfo.processInfo.arguments.contains("--audit-ai") { subtitlesVisible = true }','if ProcessInfo.processInfo.arguments.contains("--audit-ai") || ProcessInfo.processInfo.arguments.contains("--audit-ai-unavailable") { subtitlesVisible = true }')
player.write_text(s)
manager=root/'Sources/Services/SubtitleManager.swift'
s=manager.read_text().replace('  func load(_ track: Track, retry: Bool = false) async {','  func load(_ track: Track, retry: Bool = false) async {\n    if ProcessInfo.processInfo.arguments.contains("--audit-ai-unavailable") { document = nil; publishedSource = "manual"; availability = .review; error = nil; return }',1)
manager.write_text(s)

# Exercise the real player actions in Simulator without entitlement bypass fixtures.
p=root/'Sources/Views/Player/FullPlayerView.swift'
s=p.read_text().replace('    .onChange(of: expansion)', '    .task { if ProcessInfo.processInfo.arguments.contains("--audit-queue") { queuePresented = true } }\n    .onChange(of: expansion)',1)
p.write_text(s)

# Restore the ordinary, free caption rail's native motion review. All mutations
# below are confined to this disposable Debug source, after Release packaging.
# The fixture never opts into AI or calls a subtitle recognition provider.
p=root/'Sources/Services/SubtitleManager.swift'
s=p.read_text()
needle='  func load(for track: Track) {'
assert s.count(needle) == 1, 'Manual-caption review must modify the existing manager'
s=s.replace(needle, needle+'''
    if ProcessInfo.processInfo.arguments.contains("--audit-subtitle-motion") {
      revisions[track.id] = track.captionsRevision ?? 0
      segmentsByTrack[track.id] = [
        SubtitleSegment(start: 0, end: 5, ar: "السلام عليكم", ru: "Мир вам", en: "Peace be upon you", words: nil),
        SubtitleSegment(start: 5, end: 10, ar: "ورحمة الله", ru: "И милость Аллаха", en: "And Allah's mercy", words: nil),
        SubtitleSegment(start: 10, end: 15, ar: "نور في القلب", ru: "Свет в сердце", en: "Light in the heart", words: nil),
        SubtitleSegment(start: 15, end: 20, ar: "سيروا في سلام", ru: "Идите с миром", en: "Walk in peace", words: nil),
        SubtitleSegment(start: 20, end: 25, ar: "رحمة وسكينة", ru: "Милость и покой", en: "Mercy and calm", words: nil)
      ]
      stateByTrack[track.id] = .ready
      return
    }
''',1)
p.write_text(s)

p=root/'Sources/Views/Player/FullPlayerView.swift'
s=p.read_text()
needle='    .onChange(of: expansion)'
assert s.count(needle) == 1, 'Motion review must use the real full-player presenter'
s=s.replace(needle, '''    .task {
      if ProcessInfo.processInfo.arguments.contains("--audit-subtitle-motion") {
        subtitlesVisible = true
      }
    }
'''+needle,1)
p.write_text(s)

p=root/'Sources/Views/Player/PlayerSubtitleOverlay.swift'
s=p.read_text()
needle='private struct SubtitleRail<Line: View>: View {'
assert s.count(needle) == 1, 'Motion review must observe the shared production rail'
s=s.replace(needle, needle+'\n  @EnvironmentObject private var reviewPlayer: PlayerManager\n  @EnvironmentObject private var reviewSubtitles: SubtitleManager',1)
needle='    .animation(animationsAllowed ? MuwaMotion.subtitleFocus : nil, value: activeIndex)'
assert s.count(needle) == 1, 'Motion review must observe the actual rail active index'
s=s.replace(needle, needle+'''
    .background(GeometryReader { proxy in
      Color.clear.onAppear {
        ReviewSubtitleMotion.recordFrame(proxy.frame(in: .global))
      }
      .onChange(of: proxy.frame(in: .global)) { _, frame in
        ReviewSubtitleMotion.recordFrame(frame)
      }
    })
    .onAppear {
      ReviewSubtitleMotion.sample(index: activeIndex, count: count,
                                 time: reviewPlayer.timeline.snapshot.time,
                                 reduceMotion: reduceMotion, manager: reviewSubtitles,
                                 track: reviewPlayer.currentTrack)
    }
    .onChange(of: activeIndex) { _, index in
      ReviewSubtitleMotion.sample(index: index, count: count,
                                 time: reviewPlayer.timeline.snapshot.time,
                                 reduceMotion: reduceMotion, manager: reviewSubtitles,
                                 track: reviewPlayer.currentTrack)
    }
''',1)
p.write_text(s)

p=root/'Sources/Services/PlayerManager.swift'
s=p.read_text()
needle='        guard let self, let player, self.player === player else { return }\n        let actual = player.currentItem?.duration.seconds ?? self.duration'
assert s.count(needle) == 1, 'Motion driver must isolate only the periodic review clock'
s=s.replace(needle, '        if ProcessInfo.processInfo.arguments.contains("--audit-subtitle-motion") { return }\n'+needle,1)
p.write_text(s)

p=root/'Sources/App/RootView.swift'
s=p.read_text()
needle='        playerExpansion = 1'
assert s.count(needle) == 1, 'Motion review must drive the mounted real player'
s=s.replace(needle, needle+'''
        if args.contains("--audit-subtitle-motion") {
          Task { @MainActor in await ReviewSubtitleMotion.drive(player) }
        }
''',1)
s += '''
#if DEBUG
// One bounded clock driver shared by the mounted production rail and capture
// harness. PID-scoped atomic handshakes make slow simctl captures deterministic.
@MainActor
enum ReviewSubtitleMotion {
  private static let pid = ProcessInfo.processInfo.processIdentifier
  private static let directory = URL.documentsDirectory
  private static var events: [[String: Any]] = []

  private static func write(_ name: String, _ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
  }

  private static func append(_ name: String, _ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    let url = directory.appendingPathComponent(name)
    let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    try? (previous + line + "\\n").write(to: url, atomically: true, encoding: .utf8)
  }

  static func recordFrame(_ frame: CGRect) {
    guard ProcessInfo.processInfo.arguments.contains("--audit-subtitle-motion") else { return }
    write("subtitle-motion-frame.json", ["pid": pid, "x": frame.minX, "y": frame.minY,
      "width": frame.width, "height": frame.height,
      "screenWidth": UIScreen.main.bounds.width, "screenHeight": UIScreen.main.bounds.height])
  }

  static func sample(index: Int, count: Int, time: Double, reduceMotion: Bool,
                     manager: SubtitleManager, track: Track?) {
    guard ProcessInfo.processInfo.arguments.contains("--audit-subtitle-motion") else { return }
    let managerIndex = track.flatMap { manager.activeIndex(for: $0, time: time) } ?? -1
    let event: [String: Any] = ["pid": pid, "activeIndex": index, "count": count,
                               "time": time, "reduceMotion": reduceMotion,
                               "managerActiveIndex": managerIndex,
                               "source": "ordinary-manual-captions", "aiOptIn": false]
    events.append(event)
    append("subtitle-motion-rail.jsonl", event)
    write("subtitle-motion-mounted.json", event)
  }

  private static func waitFor(_ name: String, seconds: Double) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    let url = directory.appendingPathComponent(name)
    while Date() < deadline {
      if (try? String(contentsOf: url, encoding: .utf8)) == String(pid) { return true }
      try? await Task.sleep(for: .milliseconds(50))
      if Task.isCancelled { return false }
    }
    write("subtitle-motion-error.json", ["pid": pid, "error": "Timed out waiting for " + name])
    return false
  }

  static func drive(_ player: PlayerManager) async {
    player.duration = 25
    player.timeline.update(time: 0, duration: 25)
    let deadline = Date().addingTimeInterval(30)
    while events.isEmpty && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    guard !events.isEmpty else {
      write("subtitle-motion-error.json", ["pid": pid, "error": "Ordinary rail never mounted"])
      return
    }
    write("subtitle-motion-ready.json", ["pid": pid, "duration": 25, "count": 5,
                                        "source": "ordinary-manual-captions", "aiOptIn": false])
    // The host resolves simctl (up to 180 s) and starts its recorder (45 s)
    // before acknowledging. Keep the fixture deadline outside that bound.
    guard await waitFor("subtitle-motion-start.txt", seconds: 240) else { return }
    var broadNotifications = 0
    var tickNotifications = 0
    let observation = player.objectWillChange.sink { broadNotifications += 1 }
    for tick in 0...124 {
      let before = broadNotifications
      player.timeline.update(time: Double(tick) * 0.2, duration: 25)
      let delta = broadNotifications - before
      tickNotifications += delta
      append("subtitle-motion-clock.jsonl", ["pid": pid, "tick": tick,
        "time": player.timeline.snapshot.time, "duration": player.timeline.snapshot.duration,
        "broadNotificationsDuringTick": delta, "trackId": player.currentTrack?.id ?? "",
        "isPlaying": player.isPlaying])
      precondition(delta == 0, "Motion clock invalidated the global PlayerManager")
      if [5, 30, 55, 80, 105].contains(tick) {
        let index = (tick - 5) / 25
        write("subtitle-motion-checkpoint-\\(index).json", ["pid": pid,
          "time": player.timeline.snapshot.time, "expectedIndex": index])
        // A real framebuffer capture can take up to 180 s on a hosted runner.
        // Retain a bounded handshake with time for validation/atomic file I/O.
        guard await waitFor("subtitle-motion-captured-\\(index).txt", seconds: 210) else {
          observation.cancel()
          return
        }
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    observation.cancel()
    write("subtitle-motion-finished.json", ["pid": pid, "ticks": 125,
      "time": player.timeline.snapshot.time, "duration": player.timeline.snapshot.duration,
      "broadNotificationsDuringTicks": tickNotifications, "source": "ordinary-manual-captions",
      "aiOptIn": false, "isPlaying": player.isPlaying])
  }
}
#endif
'''
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
s=p.read_text()
needle='BackendConfig.boundedData(for: URLRequest(url: url), using: .shared)'
assert s.count(needle) == 1, "Artwork review must intercept the current bounded network loader"
s=s.replace(needle, 'BackendConfig.boundedData(for: URLRequest(url: url), using: ReviewArtworkProtocol.session)', 1)
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
    let portrait = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 240)).image { context in
      UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 240))
    }
    guard let url = request.url, let bytes = (url.path == "/portrait.png" ? portrait : UIImage(named: "AppMark"))?.pngData() else {
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
s=p.read_text()
needle='AVPlayerItem(asset: playbackAsset(url: playbackURL))'
assert s.count(needle) == 1, "The review audio fixture must match the real playback source"
s=s.replace(needle, 'AVPlayerItem(asset: playbackAsset(url: ProcessInfo.processInfo.arguments.contains("--audit-player") ? ReviewAudioFixture.url : playbackURL))', 1)
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

# Held buffering is confined to the disposable review copy.
p=root/'Sources/Services/PlayerManager.swift'
s=p.read_text().replace('@Published private(set) var isBuffering = false', '@Published var isBuffering = false')
p.write_text(s)
