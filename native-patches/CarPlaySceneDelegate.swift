import CarPlay
import Combine
import UIKit

@MainActor
final class CarPlayCoordinator {
  static let shared = CarPlayCoordinator()
  private(set) var player: PlayerManager?
  private(set) var library: LibraryStore?
  private(set) var downloads: DownloadManager?
  func configure(player: PlayerManager, library: LibraryStore, downloads: DownloadManager) {
    self.player = player; self.library = library; self.downloads = downloads
  }
}

/// System audio templates share the actual iPhone playback session and library.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
  private var controller: CPInterfaceController?
  private var subscriptions = Set<AnyCancellable>()
  private var catalog: CPListTemplate?
  private var favorites: CPListTemplate?
  private var recent: CPListTemplate?
  private var offline: CPListTemplate?
  private var playlists: CPListTemplate?
  private var queue: CPListTemplate?
  private var playlistDetail: (id: UUID, template: CPListTemplate)?
  private var lastError: String?

  // CarPlay delivers these UI callbacks on the main thread. Its Objective-C
  // protocols do not declare actor isolation; bridge synchronously at entry.
  nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
    MainActor.assumeIsolated { connect(interfaceController) }
  }

  private func connect(_ interfaceController: CPInterfaceController) {
    disconnect()
    controller = interfaceController
    catalog = makeList("Muwa", symbol: "music.note.list")
    favorites = makeList("Избранное", symbol: "heart")
    offline = makeList("Загрузки", symbol: "arrow.down.circle")
    playlists = makeList("Плейлисты", symbol: "rectangle.stack")
    recent = makeList("Недавние", symbol: "clock")
    queue = makeList("Очередь", symbol: "list.bullet")
    guard let catalog, let favorites, let offline, let playlists, let recent else { return }
    refreshLists()
    // Set the root only on connection. Section updates preserve navigation.
    interfaceController.setRootTemplate(CPTabBarTemplate(templates: [catalog, favorites, offline, playlists, recent]), animated: false, completion: nil)
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--audit-player") {
      let proof = URL.documentsDirectory.appending(path: "carplay-connected.txt")
      try? "Muwa CarPlay connected".write(to: proof, atomically: true, encoding: .utf8)
    }
    #endif
    CPNowPlayingTemplate.shared.add(self)
    CPNowPlayingTemplate.shared.isAlbumArtistButtonEnabled = false
    let coordinator = CarPlayCoordinator.shared
    coordinator.library?.objectWillChange
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in Task { @MainActor in self?.refreshLists() } }
      .store(in: &subscriptions)
    coordinator.downloads?.$downloadedIDs.dropFirst().receive(on: RunLoop.main)
      .sink { [weak self] _ in Task { @MainActor in self?.refreshLists() } }
      .store(in: &subscriptions)
    coordinator.player?.objectWillChange
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in Task { @MainActor in self?.refreshLists() } }
      .store(in: &subscriptions)
    coordinator.player?.$playbackError.receive(on: RunLoop.main)
      .sink { [weak self] error in Task { @MainActor in self?.showPlaybackError(error) } }
      .store(in: &subscriptions)
  }

  nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
    MainActor.assumeIsolated {
      guard controller === interfaceController else { return }
      disconnect()
    }
  }

  private func disconnect() {
    subscriptions.removeAll()
    CPNowPlayingTemplate.shared.remove(self)
    controller = nil
    catalog = nil; favorites = nil; recent = nil; offline = nil; playlists = nil
    queue = nil; playlistDetail = nil; lastError = nil
    // Disconnecting CarPlay leaves playback on the phone running.
  }

  private func makeList(_ title: String, symbol: String) -> CPListTemplate {
    let template = CPListTemplate(title: title, sections: [])
    template.emptyViewTitleVariants = ["Пока пусто"]
    template.emptyViewSubtitleVariants = ["Добавьте нашиды в приложении Muwa"]
    template.tabTitle = title
    template.tabImage = UIImage(systemName: symbol)
    template.trailingNavigationBarButtons = [CPBarButton(title: "Плеер") { [weak self] _ in
      Task { @MainActor in self?.showNowPlaying() }
    }]
    return template
  }

  private func refreshLists() {
    guard controller != nil, let library = CarPlayCoordinator.shared.library else { return }
    update(catalog, tracks: Track.catalog)
    update(favorites, tracks: library.favoriteTracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
    update(recent, tracks: library.historyTracks)
    update(offline, tracks: Track.catalog.filter { CarPlayCoordinator.shared.downloads?.isDownloaded($0) == true })
    update(queue, tracks: library.queueTracks)
    let rows = library.playlists.prefix(CPListTemplate.maximumItemCount).map { playlist in
      let item = CPListItem(text: playlist.name, detailText: "Нашидов: \(playlist.trackIDs.count)")
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          defer { completion() }
          guard let self, let library = CarPlayCoordinator.shared.library else { return }
          let detail = self.makeList(library.playlist(id: playlist.id)?.name ?? playlist.name, symbol: "rectangle.stack")
          self.playlistDetail = (playlist.id, detail)
          self.update(detail, tracks: library.tracks(in: playlist.id))
          self.controller?.pushTemplate(detail, animated: true, completion: nil)
        }
      }
      return item
    }
    playlists?.updateSections([CPListSection(items: rows)])
    if let detail = playlistDetail { update(detail.template, tracks: library.tracks(in: detail.id)) }
    refreshNowPlayingButtons()
  }

  private func update(_ template: CPListTemplate?, tracks: [Track]) {
    let player = CarPlayCoordinator.shared.player
    let rows = tracks.prefix(CPListTemplate.maximumItemCount).map { track in
      let item = CPListItem(text: track.title, detailText: track.artist)
      item.isPlaying = player?.currentTrack?.id == track.id && player?.isPlaying == true
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          defer { completion() }
          guard let self, self.controller != nil else { return }
          CarPlayCoordinator.shared.library?.replaceQueue(with: tracks)
          CarPlayCoordinator.shared.player?.play(track)
          self.showNowPlaying()
        }
      }
      return item
    }
    template?.updateSections([CPListSection(items: rows)])
  }

  private func showNowPlaying() {
    guard CarPlayCoordinator.shared.player?.currentTrack != nil,
          controller?.topTemplate !== CPNowPlayingTemplate.shared else { return }
    controller?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
  }

  private func refreshNowPlayingButtons() {
    guard let player = CarPlayCoordinator.shared.player, let library = CarPlayCoordinator.shared.library else { return }
    CPNowPlayingTemplate.shared.isUpNextButtonEnabled = !library.queueTracks.isEmpty
    var buttons: [CPNowPlayingButton] = []
    if let track = player.currentTrack, let image = UIImage(systemName: library.isLiked(track) ? "heart.fill" : "heart") {
      buttons.append(CPNowPlayingImageButton(image: image) { _ in
        Task { @MainActor in
          guard let current = CarPlayCoordinator.shared.player?.currentTrack else { return }
          CarPlayCoordinator.shared.library?.toggleLike(current)
        }
      })
    }
    if let image = UIImage(systemName: player.shuffleOn ? "shuffle.circle.fill" : "shuffle") {
      buttons.append(CPNowPlayingImageButton(image: image) { _ in
        Task { @MainActor in CarPlayCoordinator.shared.player?.shuffleOn.toggle() }
      })
    }
    let repeatSymbol = player.repeatMode == .one ? "repeat.1" : (player.repeatMode == .all ? "repeat.circle.fill" : "repeat")
    if let image = UIImage(systemName: repeatSymbol) {
      buttons.append(CPNowPlayingImageButton(image: image) { _ in
        Task { @MainActor in CarPlayCoordinator.shared.player?.cycleRepeatMode() }
      })
    }
    CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
  }

  nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
    MainActor.assumeIsolated {
      guard let queue, controller?.topTemplate !== queue else { return }
      update(queue, tracks: CarPlayCoordinator.shared.library?.queueTracks ?? [])
      controller?.pushTemplate(queue, animated: true, completion: nil)
    }
  }

  private func showPlaybackError(_ error: String?) {
    guard let error else { lastError = nil; return }
    guard error != lastError, let controller, controller.presentedTemplate == nil else { return }
    lastError = error
    let retry = CPAlertAction(title: "Повторить", style: .default) { [weak self] _ in
      Task { @MainActor in
        self?.controller?.dismissTemplate(animated: true, completion: nil)
        CarPlayCoordinator.shared.player?.retryPlayback()
      }
    }
    let close = CPAlertAction(title: "Закрыть", style: .cancel) { [weak self] _ in
      Task { @MainActor in self?.controller?.dismissTemplate(animated: true, completion: nil) }
    }
    controller.presentTemplate(CPAlertTemplate(titleVariants: [error], actions: [retry, close]), animated: true, completion: nil)
  }
}
