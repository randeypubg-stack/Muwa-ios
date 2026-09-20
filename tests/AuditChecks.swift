import Foundation

@main
struct AuditChecks {
  @MainActor static func main() throws {
    let suite = "muwa.audit.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let a = Track.catalog[0], b = Track.catalog[1]
    defaults.set([a.id, b.id], forKey: "muwa.native.playlist")
    let store = LibraryStore(defaults: defaults)
    let legacyID = store.playlists[0].id
    precondition(LibraryStore(defaults: defaults).playlists[0].id == legacyID, "Migration changes identity")
    let newID = store.createPlaylist(name: " Second ")
    store.addTrack(a, to: newID)
    store.addTrack(a, to: newID)
    precondition(store.playlist(id: newID)?.trackIDs == [a.id], "Duplicate track")
    store.toggleTrack(a, in: legacyID)
    precondition(!store.contains(a, in: legacyID) && store.contains(a, in: newID), "Wrong playlist changed")
    precondition(store.playlistIDs == [a.id, b.id], "Unstable union order")
    let restored = LibraryStore(defaults: defaults)
    precondition(restored.playlist(id: newID)?.name == "Second")
    precondition(restored.playlist(id: legacyID)?.trackIDs == [b.id])
    for track in store.queueTracks { store.removeFromQueue(track) }
    precondition(LibraryStore(defaults: defaults).queueTracks.isEmpty, "Empty queue repopulated")
    store.deletePlaylist(newID)
    store.deletePlaylist(legacyID)
    precondition(LibraryStore(defaults: defaults).playlists.isEmpty, "Deleted legacy playlist resurrected")
    print("PASS: playlist migration, restart, isolation, deduplication, order, deletion, empty queue")

    // Safe-area content sizes: small/modern iPhones, landscape, iPad and narrow iPad window.
    let cases: [(CGFloat, CGFloat, CGFloat, CGFloat, Bool)] = [
      (320, 548, 20, 0, true), (375, 647, 20, 0, true),
      (375, 724, 44, 34, true), (393, 759, 59, 34, true),
      (430, 839, 59, 34, true), (667, 355, 0, 0, true),
      (724, 369, 0, 21, true), (830, 409, 0, 21, true),
      (768, 980, 24, 20, false), (1024, 724, 24, 20, false),
      (375, 724, 24, 20, false)
    ]
    for (w, h, top, bottom, phone) in cases {
      let pad: CGFloat = phone ? 5 : (w < 600 ? 18 : 28)
      let limit: CGFloat = phone ? min(h < 740 ? 210 : 310, w * 0.68) : min(420, h * 0.48, w * 0.68)
      let g = PlayerGeometry(width: w, height: h, safeTop: top,
        chromeDrop: phone ? max(bottom - 5, 11) : 0, phone: phone,
        contentWidth: w - pad * 2, artworkLimit: limit)
      precondition(g.artworkSize > 0)
      precondition(g.actionsY + 22 <= g.chromeTop - 10, "Actions collide with bottom bar at \(w)x\(h)")
      precondition(g.transportY + (phone ? 29 : 34) + 4 <= g.actionsY - 22, "Transport/actions overlap")
      precondition(g.progressY + 24 + 8 <= g.transportY - (phone ? 29 : 34), "Progress/transport overlap")
      precondition(g.metadataY - 30 >= top + 49, "Metadata overlaps top bar")
      precondition(g.controlsX - g.controlsWidth / 2 >= 0)
      precondition(g.controlsX + g.controlsWidth / 2 <= w)
      print("PASS: geometry \(Int(w))x\(Int(h))")
    }
  }
}
