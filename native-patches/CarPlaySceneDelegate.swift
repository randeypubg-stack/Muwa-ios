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
  private var artworkTasks: [Task<Void, Never>] = []
  private var listState: ListState?

  private struct ListState: Equatable {
    let catalog: [Track]
    let favorites: Set<String>
    let history: [String]
    let downloads: Set<String>
    let playlists: [UserPlaylist]
    let queue: [String]
    let current: String?
    let playing: Bool
  }

  // CarPlay delivers these UI callbacks on the main thread. Its Objective-C
  // protocols do not declare actor isolation; bridge synchronously at entry.
  nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
    MainActor.assumeIsolated { connect(interfaceController) }
  }

  private func connect(_ interfaceController: CPInterfaceController) {
    disconnect()
    controller = interfaceController
    catalog = makeList("Слушать", symbol: "play.circle.fill")
    favorites = makeList("Избранное", symbol: "heart")
    offline = makeList("Загрузки", symbol: "arrow.down.circle")
    playlists = makeList("Плейлисты", symbol: "rectangle.stack")
    recent = makeList("Недавние", symbol: "clock")
    queue = makeList("Очередь", symbol: "list.bullet")
    guard let catalog, let favorites, let offline, let playlists else { return }
    refreshLists()
    // Audio CarPlay allows four tabs. Recent tracks remain reachable from Muwa.
    // Set the root only on connection; section updates preserve navigation.
    interfaceController.setRootTemplate(CPTabBarTemplate(templates: [catalog, favorites, offline, playlists]), animated: false) { [weak self] success, error in
      Task { @MainActor in
        guard self?.controller === interfaceController else { return }
        if let error { Diagnostics.shared.record("carplay", error: error) }
        #if DEBUG
        if success && ProcessInfo.processInfo.arguments.contains("--audit-player") {
          let proof = URL.documentsDirectory.appending(path: "carplay-connected.txt")
          try? "Muwa CarPlay connected".write(to: proof, atomically: true, encoding: .utf8)
        }
        #endif
      }
    }
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
    // A CarPlay-only launch may never mount the phone's WindowGroup tasks.
    // Refresh the same catalogue owner; its existing guard coalesces phone work.
    Task { await CatalogStore.shared.refresh() }
  }

  nonisolated func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
    MainActor.assumeIsolated {
      guard controller === interfaceController else { return }
      disconnect()
    }
  }

  private func disconnect() {
    subscriptions.removeAll()
    artworkTasks.forEach { $0.cancel() }
    artworkTasks.removeAll()
    listState = nil
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
    refreshNowPlayingButtons()
    let player = CarPlayCoordinator.shared.player
    let state = ListState(catalog: Track.catalog, favorites: library.likedIDs,
      history: library.historyIDs, downloads: CarPlayCoordinator.shared.downloads?.downloadedIDs ?? [],
      playlists: library.playlists, queue: library.queueIDs,
      current: player?.currentTrack?.id, playing: player?.isPlaying == true)
    guard state != listState else { return }
    listState = state
    artworkTasks.forEach { $0.cancel() }
    artworkTasks.removeAll()
    updateCatalog(library: library)
    update(favorites, tracks: library.favoriteTracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
    update(recent, tracks: library.historyTracks)
    update(offline, tracks: library.tracks(for: Array(CarPlayCoordinator.shared.downloads?.downloadedIDs ?? [])).filter { CarPlayCoordinator.shared.downloads?.isDownloaded($0) == true })
    update(queue, tracks: library.queueTracks)
    let rows = library.playlists.prefix(CPListTemplate.maximumItemCount).map { playlist in
      let tracks = library.tracks(in: playlist.id)
      let item = CPListItem(text: playlist.name, detailText: PlaylistSummary.text(for: tracks), image: placeholder(symbol: "music.note.list"))
      loadArtwork(for: [item], tracks: Array(tracks.prefix(1)))
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

  private func updateCatalog(library: LibraryStore) {
    guard let catalog else { return }
    let featured = Array((library.historyTracks.isEmpty ? Track.catalog : library.historyTracks).prefix(4))
    var sections: [CPListSection] = []
    if !featured.isEmpty {
      let images = featured.map { _ in placeholder(symbol: "music.note") }
      let title = library.historyTracks.isEmpty ? "Откройте для себя" : "Недавно слушали"
      let shelf: CPListImageRowItem
      if #available(iOS 17.4, *) {
        shelf = CPListImageRowItem(text: title, images: images, imageTitles: featured.map(\.title))
      } else {
        shelf = CPListImageRowItem(text: title, images: images)
      }
      shelf.listImageRowHandler = { [weak self] _, index, completion in
        Task { @MainActor in
          defer { completion() }
          guard featured.indices.contains(index) else { return }
          self?.play(featured[index], in: featured)
        }
      }
      shelf.handler = { [weak self] _, completion in
        Task { @MainActor in
          defer { completion() }
          guard let self, let recent = self.recent else { return }
          self.controller?.pushTemplate(recent, animated: true, completion: nil)
        }
      }
      sections.append(CPListSection(items: [shelf]))
      let connectedController = controller
      artworkTasks.append(Task { [weak self, weak shelf] in
        var loaded = images
        for (index, track) in featured.enumerated() {
          guard !Task.isCancelled, let url = track.artworkURL else { continue }
          if let image = await ArtworkImageStore.shared.image(for: url) {
            guard !Task.isCancelled, self?.controller === connectedController else { return }
            loaded[index] = self?.cover(image) ?? image
            shelf?.update(loaded)
          }
        }
      })
    }
    let tracks = Array(Track.catalog.prefix(max(0, CPListTemplate.maximumItemCount - featured.count - 1)))
    sections.append(CPListSection(items: makeTrackRows(tracks), header: "Вся коллекция", sectionIndexTitle: nil))
    catalog.updateSections(sections)
  }

  private func update(_ template: CPListTemplate?, tracks: [Track]) {
    guard let template else { return }
    template.updateSections([CPListSection(items: makeTrackRows(Array(tracks.prefix(CPListTemplate.maximumItemCount))))])
  }

  private func makeTrackRows(_ tracks: [Track]) -> [CPListItem] {
    let player = CarPlayCoordinator.shared.player
    let rows = tracks.map { track in
      let item = CPListItem(text: track.title, detailText: "\(track.artist) · \(track.durationText)", image: placeholder(symbol: "music.note"))
      item.isPlaying = player?.currentTrack?.id == track.id && player?.isPlaying == true
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          defer { completion() }
          self?.play(track, in: tracks)
        }
      }
      return item
    }
    loadArtwork(for: rows, tracks: tracks)
    return rows
  }

  private func play(_ track: Track, in tracks: [Track]) {
    guard controller != nil else { return }
    CarPlayCoordinator.shared.library?.replaceQueue(with: tracks)
    CarPlayCoordinator.shared.player?.play(track)
    showNowPlaying()
  }

  private func loadArtwork(for rows: [CPListItem], tracks: [Track]) {
    let connectedController = controller
    // The shared decoded cache coalesces phone/CarPlay requests. Load in order,
    // update each existing item in place, and cancel work when lists disconnect.
    artworkTasks.append(Task { [weak self] in
      for (item, track) in zip(rows, tracks) {
        guard !Task.isCancelled, let url = track.artworkURL else { continue }
        guard let image = await ArtworkImageStore.shared.image(for: url) else { continue }
        guard !Task.isCancelled, self?.controller === connectedController else { return }
        item.setImage(self?.cover(image))
      }
    })
  }

  private func cover(_ image: UIImage) -> UIImage {
    let size = CGSize(width: 120, height: 120)
    return UIGraphicsImageRenderer(size: size).image { _ in
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16).addClip()
      let scale = max(size.width / image.size.width, size.height / image.size.height)
      let width = image.size.width * scale, height = image.size.height * scale
      image.draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height))
    }
  }

  private func placeholder(symbol: String) -> UIImage {
    let size = CGSize(width: 120, height: 120)
    return UIGraphicsImageRenderer(size: size).image { context in
      UIColor(red: 0.09, green: 0.14, blue: 0.21, alpha: 1).setFill()
      context.fill(CGRect(origin: .zero, size: size))
      let icon = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 42, weight: .medium))?
        .withTintColor(UIColor(red: 0.72, green: 0.84, blue: 0.96, alpha: 1), renderingMode: .alwaysOriginal)
      icon?.draw(in: CGRect(x: 36, y: 36, width: 48, height: 48))
    }
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
