import SwiftUI

struct QueueView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore

  var body: some View {
    ZStack {
      AppBackground().ignoresSafeArea()

      VStack(spacing: 12) {
        queueHeader

        ScrollView(showsIndicators: false) {
          LazyVStack(spacing: 0) {
            ForEach(library.queueTracks) { track in
              queueRow(track)

              if track.id != library.queueTracks.last?.id {
                Divider()
                  .overlay(.white.opacity(0.06))
                  .padding(.leading, 58)
              }
            }
          }
          .padding(.horizontal, 14)
          .padding(.bottom, 26)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.hidden)
    .presentationBackground(.clear)
  }

  private var queueHeader: some View {
    VStack(spacing: 8) {
      Capsule()
        .fill(.white.opacity(0.30))
        .frame(width: 34, height: 4)

      HStack(spacing: 12) {
        Color.clear
          .frame(width: 42, height: 42)

        Spacer()

        Text("Очередь")
          .font(.system(size: 18, weight: .bold, design: .rounded))

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 42, height: 42)
            .background(.white.opacity(0.065), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Закрыть очередь")
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 10)
    .background(
      .ultraThinMaterial,
      in: RoundedRectangle(cornerRadius: 26, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, 12)
    .padding(.top, 4)
  }

  private func queueRow(_ track: Track) -> some View {
    HStack(spacing: 8) {
      Button {
        player.play(track)
        dismiss()
      } label: {
        HStack(spacing: 10) {
          ArtworkView(
            url: track.artworkURL,
            cornerRadius: 10,
            placeholderSystemImage: "music.note"
          )
          .frame(width: 44, height: 44)

          VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
              .font(.subheadline.bold())
              .lineLimit(1)

            Text(track.artist)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 8)

          if player.currentTrack?.id == track.id {
            Image(systemName: "waveform")
              .symbolEffect(.variableColor.iterative, options: .repeating)
              .foregroundStyle(.yellow)
          } else {
            Text(track.durationText)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)

      Button {
        library.removeFromQueue(track)
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.64))
          .frame(width: 34, height: 38)
          .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Удалить из очереди")

      dragHandle
        .frame(width: 28, height: 40)
        .contentShape(Rectangle())
        .draggable(track.id)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .dropDestination(for: String.self) { items, _ in
      guard let draggedID = items.first else { return false }
      moveQueueItem(draggedID, to: track.id)
      return true
    }
  }

  private var dragHandle: some View {
    VStack(spacing: 3) {
      ForEach(0..<3, id: \.self) { _ in
        Capsule()
          .fill(.white.opacity(0.34))
          .frame(width: 14, height: 1.5)
      }
    }
  }

  private func moveQueueItem(_ draggedID: String, to targetID: String) {
    let ids = library.queueTracks.map(\.id)
    guard
      draggedID != targetID,
      let sourceIndex = ids.firstIndex(of: draggedID),
      let targetIndex = ids.firstIndex(of: targetID)
    else { return }

    let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
    library.moveQueue(
      fromOffsets: IndexSet(integer: sourceIndex),
      toOffset: destination
    )
  }
}
