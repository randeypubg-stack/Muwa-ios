import SwiftUI

struct PlaylistDetailView: View {
  let playlistID: UUID

  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var premium: PremiumManager

  @State private var premiumPresented = false
  @State private var actionError: String?
  @State private var addTracksPresented = false

  private var playlist: UserPlaylist? {
    library.playlist(id: playlistID)
  }

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .center, spacing: 20) {
            PlaylistArtwork(tracks: library.tracks(in: playlistID)).frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 8) {
              Text(playlist?.name ?? "Плейлист").font(MuwaTypography.section)
                .fixedSize(horizontal: false, vertical: true)
              Text(PlaylistSummary.text(for: library.tracks(in: playlistID)))
                .font(MuwaTypography.caption).foregroundStyle(MuwaPalette.secondary)
            }
            Spacer(minLength: 0)
          }
          .padding(.vertical, 12)
          if let first = library.tracks(in: playlistID).first {
            Button {
              library.replaceQueue(with: library.tracks(in: playlistID))
              player.play(first)
            } label: {
              Label("Слушать подборку", systemImage: "play.fill").font(MuwaTypography.title)
                .foregroundStyle(MuwaPalette.background).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(MuwaPalette.ice, in: RoundedRectangle(cornerRadius: MuwaRadius.control))
            }
            .buttonStyle(MuwaPressStyle())
          }

          if let playlist, playlist.trackIDs.isEmpty {
            EmptyStateView(
              icon: "music.note.list",
              title: "Добавьте первые нашиды",
              message: "Выберите из коллекции Muwa то, что хотите слушать вместе.",
              actionTitle: "Выбрать нашиды",
              action: { addTracksPresented = true }
            )
          } else {
            LazyVStack(spacing: 0) {
              ForEach(library.tracks(in: playlistID)) { track in
                playlistTrackRow(track)
                Divider()
                  .overlay(.white.opacity(0.05))
                  .padding(.leading, 58)
              }
            }
          }
        }
        .padding(.horizontal, max(20, layout.horizontalPadding))
        .padding(.top, 10)
        .padding(.bottom, player.hasStartedPlaybackThisSession ? 170 : 90)
        .adaptiveFrame(maxWidth: min(layout.contentMaxWidth, 920))
      }
      .background(AppBackground().ignoresSafeArea())
    }
    .libraryNavigation(title: playlist?.name ?? "Плейлист")
    .toolbar {
      if !library.tracks(in: playlistID).isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button { addTracksPresented = true } label: { Image(systemName: "plus") }
            .accessibilityLabel("Добавить нашиды в плейлист")
        }
      }
    }
    .sheet(isPresented: $addTracksPresented) { PlaylistTrackPicker(playlistID: playlistID) }
    .sheet(isPresented: $premiumPresented) {
      PremiumView()
    }
    .alert(
      "Не удалось выполнить действие",
      isPresented: Binding(
        get: { actionError != nil },
        set: { if !$0 { actionError = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(actionError ?? "Неизвестная ошибка")
    }
  }

  private func playlistTrackRow(_ track: Track) -> some View {
    HStack(spacing: 8) {
      Button {
        library.replaceQueue(with: library.tracks(in: playlistID))
        player.play(track)
      } label: {
        HStack(spacing: 11) {
          ArtworkView(
            url: track.artworkURL,
            cornerRadius: 12,
            placeholderSystemImage: "music.note"
          )
          .frame(width: 44, height: 44)

          VStack(alignment: .leading, spacing: 3) {
            Text(track.title)
              .font(.system(size: 14, weight: .semibold))
              .lineLimit(1)

            Text(track.artist)
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 8)

          if player.currentTrack?.id == track.id && player.isPlaying {
            Image(systemName: "waveform")
              .symbolEffect(.variableColor.iterative, options: .repeating)
              .foregroundStyle(.yellow)
          }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(MuwaPressStyle(scale: 0.99))
      .frame(maxWidth: .infinity)

      Menu {
        Button {
          library.addNext(track, after: player.currentTrack)
        } label: {
          Label("Воспроизвести следующим", systemImage: "text.insert")
        }

        Button {
          library.ensureQueueContains(track)
        } label: {
          Label("Добавить в очередь", systemImage: "text.badge.plus")
        }

        if downloads.isDownloaded(track) {
          Button(role: .destructive) {
            do {
              try downloads.remove(track)
            } catch {
              actionError = error.localizedDescription
            }
          } label: {
            Label("Удалить загрузку", systemImage: "trash")
          }
        } else {
          Button {
            guard FeatureAccess.allowsPremiumFeature(isPremium: premium.isPremium) else {
              premiumPresented = true
              return
            }

            Task {
              do {
                try await downloads.download(track)
              } catch {
                actionError = error.localizedDescription
              }
            }
          } label: {
            Label("Скачать", systemImage: "arrow.down.circle")
          }
        }

        Divider()

        Button(role: .destructive) {
          library.removeTrack(track, from: playlistID)
        } label: {
          Label("Удалить из плей-листа", systemImage: "minus.circle")
        }
      } label: {
        Image(systemName: "ellipsis")
          .rotationEffect(.degrees(90))
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 40, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Действия с нашидом")
    }
    .padding(.vertical, 7)
    .contentShape(Rectangle())
  }
}
