import Foundation

@main
struct AuditChecks {
  @MainActor static func main() throws {
    CatalogStore.shared.installReviewTracks(Track.reviewCatalog)
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
    store.replaceQueue(with: [b, a, b])
    precondition(store.queueTracks.map(\.id) == [b.id, a.id], "Playback source order or deduplication changed")
    precondition(LibraryStore(defaults: defaults).queueIDs == [b.id, a.id], "CarPlay queue was not persisted")
    store.addNext(a, after: a)
    precondition(store.queueIDs == [b.id, a.id], "Current track moved when adding itself next")
    store.addNext(b, after: a)
    precondition(store.queueIDs == [a.id, b.id], "Play-next did not move the requested neighbor")
    store.moveQueue(fromOffsets: IndexSet(integer: 0), toOffset: 2)
    precondition(store.queueIDs == [b.id, a.id], "Downward row move failed")
    precondition(LibraryStore(defaults: defaults).queueIDs == [b.id, a.id], "Row move was not persisted")
    store.moveQueue(fromOffsets: IndexSet(integer: 1), toOffset: 0)
    precondition(store.queueIDs == [a.id, b.id], "Upward row move failed")
    store.moveQueue(fromOffsets: IndexSet(integer: 9), toOffset: 0)
    precondition(store.queueIDs == [a.id, b.id], "Invalid drag changed the queue")
    precondition(store.playlist(id: newID)?.trackIDs == [a.id], "Queue drag changed a playlist")
    defaults.set([a.id, "temporarily-unavailable", b.id], forKey: "muwa.native.queue")
    let partial = LibraryStore(defaults: defaults)
    partial.moveQueue(fromOffsets: IndexSet(integer: 0), toOffset: 2)
    precondition(partial.queueIDs == [b.id, "temporarily-unavailable", a.id], "Drag lost unavailable saved IDs")
    precondition(LibraryStore(defaults: defaults).queueIDs == partial.queueIDs, "Partial catalogue reorder did not survive restart")
    store.replaceQueue(with: [])
    precondition(LibraryStore(defaults: defaults).queueTracks.isEmpty, "Empty playback source repopulated")
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
        chromeBottomPadding: BottomChromeLayout(phone: phone).bottomPadding, phone: phone,
        contentWidth: w - pad * 2, artworkLimit: limit)
      precondition(g.artworkSize > 0)
      precondition(g.actionsY + 22 <= g.chromeTop - 10, "Actions collide with bottom bar at \(w)x\(h)")
      precondition(g.transportY + (phone ? 29 : 34) + 4 <= g.actionsY - 22, "Transport/actions overlap")
      precondition(g.progressY + 24 + 8 <= g.transportY - (phone ? 29 : 34), "Progress/transport overlap")
      precondition(g.metadataY - 30 >= top + 49, "Metadata overlaps top bar")
      precondition(g.chromeTop == h + top - 62 - (phone ? 9 : 0), "Bottom navigation left its safe-area anchor")
      precondition(g.controlsX - g.controlsWidth / 2 >= 0)
      precondition(g.controlsX + g.controlsWidth / 2 <= w)
      print("PASS: geometry \(Int(w))x\(Int(h))")
    }

    checkSubtitleGeometry()
  }

  private static func checkSubtitleGeometry() {
    // Point-space inputs cover the native 1320x2868 Pro Max framebuffer,
    // compact phones, both notch sides, and resizable iPad windows. Assertions
    // use rendered bounds rather than repeating the layout's scale/shift formula.
    let cases: [(name: String, width: CGFloat, height: CGFloat,
                 top: CGFloat, bottom: CGFloat, leading: CGFloat,
                 trailing: CGFloat, phone: Bool, padding: CGFloat,
                 contentLimit: CGFloat, artworkLimit: CGFloat)] = [
      ("iPhone 18 Pro Max portrait", 440, 956, 62, 34, 0, 0, true, 5, 430, 299),
      ("small iPhone portrait", 320, 548, 20, 0, 0, 0, true, 5, 310, 210),
      ("notched iPhone landscape left", 956, 440, 0, 21, 62, 0, true, 5, 946, 238),
      ("notched iPhone landscape right", 956, 440, 0, 21, 0, 62, true, 5, 946, 238),
      ("small iPhone landscape", 667, 355, 0, 0, 0, 0, true, 5, 657, 191),
      ("iPad narrow portrait window", 375, 724, 24, 20, 0, 0, false, 18, 339, 255),
      ("iPad narrow landscape window", 680, 400, 24, 20, 0, 0, false, 28, 624, 192),
      ("iPad Pro 13 landscape", 1376, 1032, 24, 20, 0, 0, false, 40, 1180, 420),
      ("iPad mini landscape", 1133, 744, 24, 20, 0, 0, false, 40, 1053, 357),
    ]
    let tolerance: CGFloat = 0.001
    for c in cases {
      let side = max(c.padding, max(c.leading, c.trailing))
      let g = PlayerGeometry(width: c.width, height: c.height, safeTop: c.top,
        chromeBottomPadding: BottomChromeLayout(phone: c.phone).bottomPadding, phone: c.phone,
        contentWidth: min(c.contentLimit, c.width - side * 2), artworkLimit: c.artworkLimit)
      let originalCover = CGRect(x: g.artworkX - g.artworkSize / 2,
        y: g.artworkY - g.artworkSize / 2, width: g.artworkSize, height: g.artworkSize)
      let controlsLeft = g.controlsX - g.controlsWidth / 2
      let columnRight = g.controlsX > c.width / 2 + 1 ? controlsLeft - 12 : c.width - side
      let column = CGRect(x: side, y: originalCover.minY,
        width: columnRight - side, height: originalCover.height)
      precondition(column.width > 0 && originalCover.width > 0, "Invalid artwork column: \(c.name)")

      let active = PlayerSubtitleLayout(size: g.artworkSize,
        leftSpace: g.artworkX - column.minX, rightSpace: column.maxX - g.artworkX, active: true)
      let coverWidth = g.artworkSize * active.coverScale
      let cover = CGRect(x: g.artworkX + active.coverShift - coverWidth / 2,
        y: g.artworkY - coverWidth / 2, width: coverWidth, height: coverWidth)
      let railHeight = min(220, max(120, g.artworkSize * 0.78))
      let rail = CGRect(x: g.artworkX + active.railOffset - active.railWidth / 2,
        y: g.artworkY - railHeight / 2, width: active.railWidth, height: railHeight)
      precondition([active.coverScale, active.coverShift, active.railWidth, active.railOffset]
        .allSatisfy { $0.isFinite }, "Non-finite subtitle geometry: \(c.name)")
      precondition(active.coverScale > 0 && active.coverScale < 1,
        "Captions must leave a visible, reduced cover: \(c.name)")
      precondition(coverWidth >= g.artworkSize * 0.60,
        "Caption layout shrank the cover excessively: \(c.name)")
      precondition(active.railWidth >= 80 && active.railWidth <= 164,
        "Caption rail is unreadably narrow or exceeds its width budget: \(c.name)")
      precondition(column.insetBy(dx: -tolerance, dy: -tolerance).contains(cover),
        "Reduced artwork escaped its safe column: \(c.name)")
      precondition(column.insetBy(dx: -tolerance, dy: -tolerance).contains(rail),
        "Subtitle rail escaped its safe column: \(c.name)")
      precondition(rail.minX >= cover.maxX + 1,
        "Subtitle rail overlaps the artwork: \(c.name)")
      if g.controlsX > c.width / 2 + 1 {
        precondition(rail.maxX <= controlsLeft - 12 + tolerance,
          "Subtitle rail entered landscape transport controls: \(c.name)")
      }

      // The same inactive layout applies when captions are hidden, the player
      // is collapsed, or no text exists: preserve the original artwork frame.
      let inactive = PlayerSubtitleLayout(size: g.artworkSize,
        leftSpace: g.artworkX - column.minX, rightSpace: column.maxX - g.artworkX, active: false)
      let unchangedCover = CGRect(x: g.artworkX + inactive.coverShift - g.artworkSize * inactive.coverScale / 2,
        y: g.artworkY - g.artworkSize * inactive.coverScale / 2,
        width: g.artworkSize * inactive.coverScale, height: g.artworkSize * inactive.coverScale)
      precondition(unchangedCover == originalCover,
        "Hidden or unavailable captions changed original artwork geometry: \(c.name)")
      print("PASS: subtitle safe bounds, separation and unchanged inactive artwork · \(c.name)")
    }
  }
}
