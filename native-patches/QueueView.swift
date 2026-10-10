import SwiftUI

struct QueueView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore

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
          QueueList(
            tracks: library.queueTracks,
            currentID: player.currentTrack?.id,
            isPlaying: player.isPlaying,
            play: { player.play($0); dismiss() },
            remove: { track in
              withAnimation(reduceMotion ? nil : MuwaMotion.reorder) { library.removeFromQueue(track) }
            },
            move: { source, destination in
              library.moveQueue(fromOffsets: source, toOffset: destination)
            },
            moveBy: moveBy
          )
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
    withAnimation(reduceMotion ? nil : MuwaMotion.reorder) {
      library.moveQueue(fromOffsets: IndexSet(integer: index), toOffset: delta > 0 ? index + 2 : index - 1)
    }
  }
}
