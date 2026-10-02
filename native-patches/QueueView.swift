import SwiftUI

struct QueueView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @State private var dropTarget: String?

  var body: some View {
    ZStack {
      AppBackground().ignoresSafeArea()
      VStack(spacing: 18) {
        queueHeader
        if library.queueTracks.isEmpty {
          ContentUnavailableView("Очередь пуста", systemImage: "text.line.first.and.arrowtriangle.forward",
                                 description: Text("Добавьте нашиды через меню ⋮."))
            .foregroundStyle(MuwaPalette.secondary)
        } else {
          ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8) {
              ForEach(library.queueTracks) { track in
                QueueTrackRow(
                  track: track,
                  isCurrent: player.currentTrack?.id == track.id,
                  isPlaying: player.isPlaying,
                  isDropTarget: dropTarget == track.id,
                  play: { player.play(track); dismiss() },
                  remove: {
                    withAnimation(reduceMotion ? nil : MuwaMotion.reorder) {
                      library.removeFromQueue(track)
                    }
                  },
                  move: { delta in moveBy(track.id, delta: delta) }
                )
                .dropDestination(for: String.self) { items, _ in
                  guard let draggedID = items.first else { return false }
                  return moveQueueItem(draggedID, to: track.id)
                } isTargeted: { targeted in
                  if targeted { dropTarget = track.id }
                  else if dropTarget == track.id { dropTarget = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
              }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
            .animation(reduceMotion ? nil : MuwaMotion.reorder, value: library.queueIDs)
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.hidden)
    .presentationBackground(.clear)
    .sensoryFeedback(.selection, trigger: library.queueIDs)
  }

  private var queueHeader: some View {
    VStack(spacing: 16) {
      Capsule().fill(.white.opacity(0.25)).frame(width: 34, height: 4)
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Очередь").font(MuwaTypography.section)
          Text("\(MuwaText.trackCount(library.queueTracks.count)) · \(totalDuration)")
            .font(MuwaTypography.caption)
            .foregroundStyle(MuwaPalette.secondary)
        }
        Spacer(minLength: 8)
        Button { dismiss() } label: {
          Image(systemName: "xmark")
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(MuwaPalette.secondary)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.065), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.75))
        }
        .buttonStyle(MuwaPressStyle(scale: 0.91))
        .accessibilityLabel("Закрыть очередь")
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 12)
  }

  private var totalDuration: String {
    let minutes = Int(library.queueTracks.reduce(0) { $0 + $1.duration } / 60)
    return minutes >= 60 ? "\(minutes / 60) ч \(minutes % 60) мин" : "\(minutes) мин"
  }

  private func moveBy(_ id: String, delta: Int) {
    let ids = library.queueTracks.map(\.id)
    guard let index = ids.firstIndex(of: id), ids.indices.contains(index + delta) else { return }
    _ = moveQueueItem(id, to: ids[index + delta])
  }

  @discardableResult
  private func moveQueueItem(_ draggedID: String, to targetID: String) -> Bool {
    let ids = library.queueIDs
    guard draggedID != targetID,
          let sourceIndex = ids.firstIndex(of: draggedID),
          let targetIndex = ids.firstIndex(of: targetID) else { return false }
    withAnimation(reduceMotion ? nil : MuwaMotion.reorder) {
      library.moveQueue(fromOffsets: IndexSet(integer: sourceIndex),
                        toOffset: sourceIndex < targetIndex ? targetIndex + 1 : targetIndex)
    }
    return true
  }
}
