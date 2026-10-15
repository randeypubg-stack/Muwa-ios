import SwiftUI
import UIKit

// UITableView owns lifting/moving the entire cell. SwiftUI owns the row's
// appearance and actions; LibraryStore remains the sole persisted queue owner.
struct QueueList: UIViewRepresentable {
  let tracks: [Track]
  let currentID: String?
  let isPlaying: Bool
  let play: (Track) -> Void
  let remove: (Track) -> Void
  let move: (IndexSet, Int) -> Void
  let moveBy: (String, Int) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> UITableView {
    let table = UITableView(frame: .zero, style: .plain)
    table.backgroundColor = .clear
    table.separatorStyle = .none
    table.rowHeight = UITableView.automaticDimension
    table.estimatedRowHeight = 90
    table.contentInset.bottom = 20
    table.contentInsetAdjustmentBehavior = .never
    table.dataSource = context.coordinator
    table.delegate = context.coordinator
    table.register(UITableViewCell.self, forCellReuseIdentifier: "queue-track")
    table.allowsSelection = false
    table.isEditing = true
    return table
  }

  func updateUIView(_ table: UITableView, context: Context) {
    let coordinator = context.coordinator
    let old = coordinator.parent
    coordinator.parent = self
    if coordinator.tracks != tracks {
      coordinator.tracks = tracks
      table.reloadData()
    } else if old.currentID != currentID || old.isPlaying != isPlaying {
      for index in table.indexPathsForVisibleRows ?? [] {
        if let cell = table.cellForRow(at: index) { coordinator.configure(cell, at: index) }
      }
    }
  }

  final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
    var parent: QueueList
    var tracks: [Track]
    init(_ parent: QueueList) { self.parent = parent; tracks = parent.tracks }

    func tableView(_ table: UITableView, numberOfRowsInSection section: Int) -> Int { tracks.count }

    func tableView(_ table: UITableView, cellForRowAt index: IndexPath) -> UITableViewCell {
      let cell = table.dequeueReusableCell(withIdentifier: "queue-track", for: index)
      configure(cell, at: index)
      return cell
    }

    func configure(_ cell: UITableViewCell, at index: IndexPath) {
      guard tracks.indices.contains(index.row) else { return }
      let track = tracks[index.row]
      cell.selectionStyle = .none
      cell.accessibilityIdentifier = "queue-row-" + track.id
      cell.backgroundConfiguration = .clear()
      cell.showsReorderControl = true
      cell.contentConfiguration = UIHostingConfiguration {
        QueueTrackRow(
          track: track,
          isCurrent: parent.currentID == track.id,
          isPlaying: parent.isPlaying,
          play: { [weak self] in self?.parent.play(track) },
          remove: { [weak self] in self?.parent.remove(track) },
          move: { [weak self] delta in self?.parent.moveBy(track.id, delta) }
        )
        .padding(.vertical, 4)
        .padding(.leading, 16)
        .accessibilityIdentifier("queue-row-" + track.id)
      }.margins(.all, 0)
    }

    func tableView(_ table: UITableView, canMoveRowAt index: IndexPath) -> Bool { true }
    func tableView(_ table: UITableView, canEditRowAt index: IndexPath) -> Bool { true }
    func tableView(_ table: UITableView, editingStyleForRowAt index: IndexPath) -> UITableViewCell.EditingStyle { .none }
    func tableView(_ table: UITableView, shouldIndentWhileEditingRowAt index: IndexPath) -> Bool { false }

    func tableView(_ table: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
      guard tracks.indices.contains(source.row), tracks.indices.contains(destination.row),
            source.row != destination.row else { return }
      let item = tracks.remove(at: source.row)
      tracks.insert(item, at: destination.row)
      // UIKit supplies the final row index; Swift's move uses the insertion
      // index before removing the source. Convert exactly once.
      parent.move(IndexSet(integer: source.row), destination.row > source.row ? destination.row + 1 : destination.row)
    }
  }
}
