import Foundation
import SwiftUI

struct UserPlaylist: Identifiable, Codable, Hashable {
  let id: UUID
  var name: String
  var trackIDs: [String]
  let createdAt: Date

  init(id: UUID = UUID(), name: String, trackIDs: [String] = [], createdAt: Date = Date()) {
    self.id = id
    self.name = name
    self.trackIDs = trackIDs
    self.createdAt = createdAt
  }
}

@MainActor
final class LibraryStore: ObservableObject {
  @Published private(set) var likedIDs: Set<String>
  @Published private(set) var historyIDs: [String]
  @Published private(set) var playlists: [UserPlaylist]
  @Published private(set) var queueIDs: [String]
  @Published private(set) var publications: [PublicationDraft]

  private let defaults: UserDefaults

  private enum Key {
    static let liked = "muwa.native.liked"
    static let history = "muwa.native.history"
    static let legacyPlaylist = "muwa.native.playlist"
    static let playlists = "muwa.native.playlists.v2"
    static let queue = "muwa.native.queue"
    static let publications = "muwa.native.publications"
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    likedIDs = Set(defaults.stringArray(forKey: Key.liked) ?? [])
    historyIDs = defaults.stringArray(forKey: Key.history) ?? []

    if
      let data = defaults.data(forKey: Key.playlists),
      let decoded = try? JSONDecoder().decode([UserPlaylist].self, from: data)
    {
      playlists = decoded
    } else {
      let legacy = defaults.stringArray(forKey: Key.legacyPlaylist) ?? []
      playlists = legacy.isEmpty
        ? []
        : [UserPlaylist(name: "Мой плей-лист", trackIDs: legacy)]
    }

    queueIDs = defaults.stringArray(forKey: Key.queue) ?? Track.catalog.map(\.id)

    if
      let data = defaults.data(forKey: Key.publications),
      let decoded = try? JSONDecoder().decode([PublicationDraft].self, from: data)
    {
      publications = decoded
    } else {
      publications = []
    }
    // Persist migration once so playlist identities survive a restart.
    if defaults.data(forKey: Key.playlists) == nil { persistPlaylists() }
  }

  var favoriteTracks: [Track] { tracks(for: Array(likedIDs)) }
  var historyTracks: [Track] { tracks(for: historyIDs) }
  var playlistIDs: [String] {
    var seen = Set<String>()
    return playlists.flatMap(\.trackIDs).filter { seen.insert($0).inserted }
  }
  var playlistTracks: [Track] { tracks(for: playlistIDs) }
  var queueTracks: [Track] { tracks(for: queueIDs) }
  var drafts: [PublicationDraft] { publications.filter { $0.status == .draft } }

  func isLiked(_ track: Track) -> Bool { likedIDs.contains(track.id) }
  func isInPlaylist(_ track: Track) -> Bool {
    playlists.contains { $0.trackIDs.contains(track.id) }
  }

  func playlist(id: UUID) -> UserPlaylist? {
    playlists.first(where: { $0.id == id })
  }

  func tracks(in playlistID: UUID) -> [Track] {
    guard let playlist = playlist(id: playlistID) else { return [] }
    return tracks(for: playlist.trackIDs)
  }

  func contains(_ track: Track, in playlistID: UUID) -> Bool {
    playlist(id: playlistID)?.trackIDs.contains(track.id) == true
  }

  func toggleLike(_ track: Track) {
    if likedIDs.contains(track.id) {
      likedIDs.remove(track.id)
    } else {
      likedIDs.insert(track.id)
    }
    persistLiked()
  }

  // Compatibility helper for existing menus: use the first playlist, creating one if needed.
  func togglePlaylist(_ track: Track) {
    let targetID: UUID
    if let first = playlists.first {
      targetID = first.id
    } else {
      targetID = createPlaylist(name: "Мой плей-лист")
    }
    toggleTrack(track, in: targetID)
  }

  @discardableResult
  func createPlaylist(name: String) -> UUID {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalName = trimmed.isEmpty ? "Новый плей-лист" : trimmed
    let playlist = UserPlaylist(name: finalName)
    playlists.insert(playlist, at: 0)
    persistPlaylists()
    return playlist.id
  }

  func renamePlaylist(_ id: UUID, name: String) {
    guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    playlists[index].name = trimmed
    persistPlaylists()
  }

  func deletePlaylist(_ id: UUID) {
    playlists.removeAll(where: { $0.id == id })
    persistPlaylists()
  }

  func addTrack(_ track: Track, to playlistID: UUID) {
    guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
    guard !playlists[index].trackIDs.contains(track.id) else { return }
    playlists[index].trackIDs.append(track.id)
    persistPlaylists()
  }

  func removeTrack(_ track: Track, from playlistID: UUID) {
    guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
    playlists[index].trackIDs.removeAll(where: { $0 == track.id })
    persistPlaylists()
  }

  func toggleTrack(_ track: Track, in playlistID: UUID) {
    if contains(track, in: playlistID) {
      removeTrack(track, from: playlistID)
    } else {
      addTrack(track, to: playlistID)
    }
  }

  func recordHistory(_ track: Track) {
    historyIDs.removeAll(where: { $0 == track.id })
    historyIDs.insert(track.id, at: 0)
    if historyIDs.count > 40 {
      historyIDs = Array(historyIDs.prefix(40))
    }
    defaults.set(historyIDs, forKey: Key.history)
  }

  func addNext(_ track: Track, after current: Track?) {
    queueIDs.removeAll(where: { $0 == track.id })
    if let current, let index = queueIDs.firstIndex(of: current.id) {
      queueIDs.insert(track.id, at: min(index + 1, queueIDs.count))
    } else {
      queueIDs.insert(track.id, at: 0)
    }
    persistQueue()
  }

  func removeFromQueue(_ track: Track) {
    queueIDs.removeAll(where: { $0 == track.id })
    persistQueue()
  }

  func moveQueue(fromOffsets source: IndexSet, toOffset destination: Int) {
    queueIDs.move(fromOffsets: source, toOffset: destination)
    persistQueue()
  }

  func ensureQueueContains(_ track: Track) {
    if !queueIDs.contains(track.id) {
      queueIDs.append(track.id)
      persistQueue()
    }
  }

  func addPublication(_ draft: PublicationDraft) {
    publications.insert(draft, at: 0)
    persistPublications()
  }

  func updatePublication(_ draft: PublicationDraft) {
    if let index = publications.firstIndex(where: { $0.id == draft.id }) {
      publications[index] = draft
    } else {
      publications.insert(draft, at: 0)
    }
    persistPublications()
  }

  func deletePublication(_ id: UUID) {
    publications.removeAll(where: { $0.id == id })
    persistPublications()
  }

  func tracks(for ids: [String]) -> [Track] {
    ids.compactMap(Track.track(id:))
  }

  private func persistLiked() {
    defaults.set(Array(likedIDs), forKey: Key.liked)
  }

  private func persistPlaylists() {
    if let data = try? JSONEncoder().encode(playlists) {
      defaults.set(data, forKey: Key.playlists)
    }
  }

  private func persistQueue() {
    defaults.set(queueIDs, forKey: Key.queue)
  }

  private func persistPublications() {
    if let data = try? JSONEncoder().encode(publications) {
      defaults.set(data, forKey: Key.publications)
    }
  }
}

