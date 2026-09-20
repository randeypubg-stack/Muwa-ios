import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class PlayerManager: ObservableObject {
  @Published var currentTrack: Track?
  @Published var isPlaying = false
  @Published var progress: Double = 0
  @Published var currentTime: TimeInterval = 0
  @Published var duration: TimeInterval = 0
  @Published var shuffleOn = false
  @Published var repeatOn = false
  @Published private(set) var hasStartedPlaybackThisSession = false

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var artworkTask: Task<Void, Never>?
  private var currentArtwork: MPMediaItemArtwork?
  private var interruptionObserver: NSObjectProtocol?
  private var routeChangeObserver: NSObjectProtocol?
  private var wasPlayingBeforeInterruption = false

  private let library: LibraryStore
  private let downloads: DownloadManager
  private let premium: PremiumManager

  init(library: LibraryStore, downloads: DownloadManager, premium: PremiumManager) {
    self.library = library
    self.downloads = downloads
    self.premium = premium
    configureAudioSession()
    configureRemoteCommands()
    configureAudioNotifications()
  }

  deinit {
    if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
    artworkTask?.cancel()
  }

  func play(_ track: Track, autoplay: Bool = true) {
    hasStartedPlaybackThisSession = true
    currentTrack = track
    library.ensureQueueContains(track)
    library.recordHistory(track)
    currentArtwork = nil
    artworkTask?.cancel()

    player?.pause()
    removeTimeObserver()
    removeEndObserver()

    let canUseOfflineCopy = premium.isPremium && downloads.isDownloaded(track)
    let playbackURL =
      canUseOfflineCopy ? (downloads.localURL(for: track) ?? track.audioURL) : track.audioURL
    let item = AVPlayerItem(url: playbackURL)
    let newPlayer = AVPlayer(playerItem: item)
    player = newPlayer
    duration = track.duration
    currentTime = 0
    progress = 0
    addTimeObserver(to: newPlayer)
    addEndObserver(for: item)

    if autoplay {
      newPlayer.play()
      isPlaying = true
    } else {
      isPlaying = false
    }
    loadNowPlayingArtwork(for: track)
    updateNowPlaying()
  }

  func toggle() {
    guard let player else {
      if let track = currentTrack { play(track) }
      return
    }
    if isPlaying {
      player.pause()
      isPlaying = false
    } else {
      if duration > 0, currentTime >= duration - 0.35 {
        player.seek(to: .zero)
        currentTime = 0
        progress = 0
      }
      hasStartedPlaybackThisSession = true
      player.play()
      isPlaying = true
    }
    updateNowPlaying()
  }

  func seek(to fraction: Double) {
    guard duration > 0 else { return }
    let clamped = max(0, min(1, fraction))
    let seconds = clamped * duration
    player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    currentTime = seconds
    progress = clamped
    updateNowPlaying()
  }

  func next() {
    guard let current = currentTrack else {
      if let first = library.queueTracks.first { play(first) }
      return
    }
    let queue = library.queueTracks.isEmpty ? Track.catalog : library.queueTracks
    guard !queue.isEmpty else { return }

    if shuffleOn, queue.count > 1 {
      let candidates = queue.filter { $0.id != current.id }
      if let random = candidates.randomElement() { play(random) }
      return
    }

    guard let index = queue.firstIndex(where: { $0.id == current.id }) else {
      play(queue[0])
      return
    }
    let nextIndex = index + 1
    if nextIndex < queue.count {
      play(queue[nextIndex])
    } else if repeatOn {
      play(queue[0])
    } else {
      player?.pause()
      isPlaying = false
      currentTime = duration
      progress = duration > 0 ? 1 : 0
      updateNowPlaying()
    }
  }

  func previous() {
    if currentTime > 4 {
      seek(to: 0)
      return
    }
    guard let current = currentTrack else { return }
    let queue = library.queueTracks.isEmpty ? Track.catalog : library.queueTracks
    guard let index = queue.firstIndex(where: { $0.id == current.id }), !queue.isEmpty else {
      return
    }
    let previousIndex = index > 0 ? index - 1 : (repeatOn ? queue.count - 1 : 0)
    play(queue[previousIndex])
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
      try session.setActive(true)
    } catch {
      print("Audio session error: \(error)")
    }
  }

  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let self, self.premium.isPremium else { return }
        self.hasStartedPlaybackThisSession = true
        self.player?.play()
        self.isPlaying = true
        self.updateNowPlaying()
      }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let self, self.premium.isPremium else { return }
        self.player?.pause()
        self.isPlaying = false
        self.updateNowPlaying()
      }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let self, self.premium.isPremium else { return }
        self.toggle()
      }
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let self, self.premium.isPremium else { return }
        self.next()
      }
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        guard let self, self.premium.isPremium else { return }
        self.previous()
      }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      Task { @MainActor in
        guard let self, self.premium.isPremium, self.duration > 0 else { return }
        self.seek(to: event.positionTime / self.duration)
      }
      return .success
    }
  }

  func handleScenePhase(_ phase: ScenePhase) {
    switch phase {
    case .background:
      guard !premium.isPremium else { return }
      player?.pause()
      isPlaying = false
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    case .active:
      updateNowPlaying()
    default:
      break
    }
  }

  private func configureAudioNotifications() {
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        guard let self,
          let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        switch type {
        case .began:
          self.wasPlayingBeforeInterruption = self.isPlaying
          self.player?.pause()
          self.isPlaying = false
          self.updateNowPlaying()
        case .ended:
          let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
          let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
          if self.wasPlayingBeforeInterruption, options.contains(.shouldResume) {
            let canResume =
              self.premium.isPremium || UIApplication.shared.applicationState == .active
            if canResume {
              self.player?.play()
              self.isPlaying = true
              self.updateNowPlaying()
            }
          }
          self.wasPlayingBeforeInterruption = false
        @unknown default:
          break
        }
      }
    }

    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        guard let self,
          let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
          reason == .oldDeviceUnavailable
        else { return }
        self.player?.pause()
        self.isPlaying = false
        self.updateNowPlaying()
      }
    }
  }

  private func addTimeObserver(to player: AVPlayer) {
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.35, preferredTimescale: 600),
      queue: .main
    ) { [weak self, weak player] time in
      Task { @MainActor in
        guard let self, let player else { return }
        self.currentTime = time.seconds.isFinite ? time.seconds : 0
        let actual = player.currentItem?.duration.seconds ?? self.duration
        if actual.isFinite && actual > 0 { self.duration = actual }
        self.progress = self.duration > 0 ? min(1, max(0, self.currentTime / self.duration)) : 0
        self.updateNowPlaying()
      }
    }
  }

  private func removeTimeObserver() {
    if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
  }

  private func addEndObserver(for item: AVPlayerItem) {
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.repeatOn, let track = self.currentTrack {
          self.play(track)
        } else {
          self.next()
        }
      }
    }
  }

  private func removeEndObserver() {
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
  }

  private func loadNowPlayingArtwork(for track: Track) {
    guard let url = track.artworkURL else { return }
    artworkTask = Task { [weak self] in
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard !Task.isCancelled, let image = UIImage(data: data) else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        await MainActor.run {
          guard let self, self.currentTrack?.id == track.id else { return }
          self.currentArtwork = artwork
          self.updateNowPlaying()
        }
      } catch {
        // Artwork is optional; playback should never fail because of it.
      }
    }
  }

  private func updateNowPlaying() {
    guard let track = currentTrack else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
    ]
    if let currentArtwork { info[MPMediaItemPropertyArtwork] = currentArtwork }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
}