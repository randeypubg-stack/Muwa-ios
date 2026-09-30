import CarPlay
import Combine
import UIKit

@MainActor
final class CarPlayCoordinator {
  static let shared = CarPlayCoordinator()
  private(set) var player: PlayerManager?
  private(set) var library: LibraryStore?
  func configure(player: PlayerManager, library: LibraryStore) { self.player = player; self.library = library }
}

/// Apple's audio templates, sharing the actual player and library with the phone.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var controller: CPInterfaceController?
  private var subscription: AnyCancellable?
  private var playingSubscription: AnyCancellable?

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
    controller = interfaceController
    showLibrary()
    subscription = CarPlayCoordinator.shared.library?.objectWillChange.sink { [weak self] _ in
      Task { @MainActor in self?.showLibrary() }
    }
    playingSubscription = CarPlayCoordinator.shared.player?.$currentTrack.sink { track in
      CPNowPlayingTemplate.shared.isUpNextButtonEnabled = track != nil
    }
  }

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) {
    subscription?.cancel(); playingSubscription?.cancel(); controller = nil
  }

  private func showLibrary() {
    guard let library = CarPlayCoordinator.shared.library else { return }
    let catalog = list("Muwa", tracks: Track.catalog, symbol: "music.note.list")
    let favorites = list("Избранное", tracks: library.favoriteTracks, symbol: "heart")
    let recent = list("Недавние", tracks: library.historyTracks, symbol: "clock")
    let tabs = CPTabBarTemplate(templates: [catalog, favorites, recent])
    controller?.setRootTemplate(tabs, animated: false, completion: nil)
  }

  private func list(_ title: String, tracks: [Track], symbol: String) -> CPListTemplate {
    let rows: [CPListItem] = tracks.map { track in
      let item = CPListItem(text: track.title, detailText: track.artist)
      item.handler = { [weak self] _, completion in
        Task { @MainActor in
          CarPlayCoordinator.shared.player?.play(track)
          self?.controller?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
          completion()
        }
      }
      return item
    }
    let template = CPListTemplate(title: title, sections: [CPListSection(items: rows)])
    template.emptyViewTitleVariants = ["Пока пусто"]
    template.emptyViewSubtitleVariants = ["Добавьте нашиды в приложении Muwa"]
    template.tabTitle = title
    template.tabImage = UIImage(systemName: symbol)
    return template
  }
}
