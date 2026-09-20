import SwiftUI

struct TrackRow: View {
  let track: Track
  var isPlaying = false
  var trailingSystemImage: String? = nil
  var action: () -> Void
  var trailingAction: (() -> Void)? = nil

  var isInPlaylist = false
  var togglePlaylistAction: (() -> Void)? = nil

  var playlists: [UserPlaylist] = []
  var isTrackInPlaylist: ((UUID) -> Bool)? = nil
  var toggleTrackInPlaylistAction: ((UUID) -> Void)? = nil
  var createPlaylistAction: (() -> Void)? = nil

  var playNextAction: (() -> Void)? = nil
  var addToQueueAction: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 8) {
      Button(action: action) {
        HStack(spacing: 11) {
          ArtworkView(url: track.artworkURL, cornerRadius: 13, placeholderSystemImage: "music.note")
            .frame(width: 44, height: 44)

          VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
              .font(.system(size: 14, weight: .semibold))
              .lineLimit(1)

            HStack(spacing: 6) {
              Text(track.artist)
              Text("•")
              Text(track.durationText)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
          }

          Spacer(minLength: 8)

          if isPlaying {
            Image(systemName: "waveform")
              .symbolEffect(.variableColor.iterative, options: .repeating)
              .foregroundStyle(.yellow)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)

      if hasContextMenu {
        Menu {
          if !playlists.isEmpty || createPlaylistAction != nil {
            Menu("Добавить в плей-лист") {
              ForEach(playlists) { playlist in
                Button {
                  toggleTrackInPlaylistAction?(playlist.id)
                } label: {
                  Label(
                    playlist.name,
                    systemImage: isTrackInPlaylist?(playlist.id) == true
                      ? "checkmark.circle.fill"
                      : "circle"
                  )
                }
              }

              if !playlists.isEmpty, createPlaylistAction != nil {
                Divider()
              }

              if let createPlaylistAction {
                Button {
                  createPlaylistAction()
                } label: {
                  Label("Новый плей-лист", systemImage: "plus")
                }
              }
            }
          } else if let togglePlaylistAction {
            Button {
              togglePlaylistAction()
            } label: {
              Label(
                isInPlaylist ? "Убрать из плей-листа" : "Добавить в плей-лист",
                systemImage: isInPlaylist ? "music.note.list" : "text.badge.plus"
              )
            }
          }

          if let playNextAction {
            Button {
              playNextAction()
            } label: {
              Label("Воспроизвести следующим", systemImage: "text.insert")
            }
          }

          if let addToQueueAction {
            Button {
              addToQueueAction()
            } label: {
              Label("Добавить в очередь", systemImage: "text.badge.plus")
            }
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .rotationEffect(.degrees(90))
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.72))
        .accessibilityLabel("Действия")
      } else if let trailingSystemImage, let trailingAction {
        Button(action: trailingAction) {
          Image(systemName: trailingSystemImage)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }

  private var hasContextMenu: Bool {
    togglePlaylistAction != nil
      || !playlists.isEmpty
      || createPlaylistAction != nil
      || playNextAction != nil
      || addToQueueAction != nil
  }
}
