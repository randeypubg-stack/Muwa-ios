import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore

  let openPlayer: () -> Void
  let openSearch: () -> Void

  @State private var playlistTrackForCreation: Track?

  private var currentTrack: Track? {
    player.currentTrack
  }

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      VStack(spacing: 0) {
        ScreenHeader(title: "Главная", searchAction: openSearch)
          .padding(.horizontal, layout.horizontalPadding)
          .padding(.top, layout.isCompactLandscapePhone ? 6 : 10)
          .padding(.bottom, 10)
          .adaptiveFrame(maxWidth: layout.contentMaxWidth)
          .background(
            Color(red: 0.003, green: 0.004, blue: 0.006)
              .opacity(0.98)
          )
          .zIndex(10)

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: layout.isWide ? 34 : 28) {
            if player.hasStartedPlaybackThisSession, let currentTrack {
              continueListening(track: currentTrack, layout: layout)
            }

            if layout.isWide {
              recommendationsGrid(layout: layout)
              popularGrid(layout: layout)
            } else {
              recommendationsCarousel
              popularList
            }
          }
          .padding(.horizontal, layout.horizontalPadding)
          .padding(.top, layout.isCompactLandscapePhone ? 8 : 14)
          .padding(.bottom, layout.isCompactLandscapePhone ? 132 : 170)
          .adaptiveFrame(maxWidth: layout.contentMaxWidth)
        }
      }
    }
    .sheet(item: $playlistTrackForCreation) { track in
      PlaylistCreateSheet { name in
        let playlistID = library.createPlaylist(name: name)
        library.addTrack(track, to: playlistID)
      }
    }
  }

  private func continueListening(track currentTrack: Track, layout: AdaptiveLayout) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("ПРОДОЛЖИТЬ СЛУШАТЬ")
        .font(.caption2.weight(.bold))
        .tracking(2.3)
        .foregroundStyle(.secondary)

      let coverSize: CGFloat = layout.isPad ? 178 : (layout.isLandscape ? 146 : 126)
      HStack(spacing: layout.isWide ? 22 : 16) {
        Button(action: openPlayer) {
          ArtworkView(url: currentTrack.artworkURL, cornerRadius: layout.isWide ? 36 : 30)
            .frame(width: coverSize, height: coverSize)
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 8) {
          Text(currentTrack.title)
            .font(.system(size: layout.isWide ? 30 : 26, weight: .bold, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.82)

          Text(currentTrack.artist)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)

          HStack(spacing: 10) {
            Button {
              if player.currentTrack?.id == currentTrack.id, player.duration > 0 {
                player.toggle()
              } else {
                player.play(currentTrack)
              }
            } label: {
              Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 50, height: 50)
                .background(.white, in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: openPlayer) {
              HStack(spacing: 5) {
                Text("Открыть")
                Image(systemName: "chevron.right")
              }
              .font(.system(size: 12, weight: .semibold))
              .padding(.horizontal, 13)
              .frame(height: 44)
              .background(
                .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.10)).frame(height: 3)
          Capsule().fill(.white).frame(width: proxy.size.width * player.progress, height: 3)
        }
      }
      .frame(height: 3)

      HStack {
        Text(format(player.currentTime))
        Spacer()
        Text(player.duration > 0 ? format(player.duration) : currentTrack.durationText)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(layout.isWide ? 20 : 0)
    .background {
      if layout.isWide {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
          .fill(.white.opacity(0.025))
      }
    }
  }

  private var recommendationsCarousel: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Рекомендации")
        .font(.title2.bold())

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(Track.catalog) { track in
            recommendationCard(track, width: 154)
          }
        }
      }
      .contentMargins(.trailing, 18, for: .scrollContent)
    }
  }

  private func recommendationsGrid(layout: AdaptiveLayout) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Рекомендации").font(.title2.bold())

      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: 16),
          count: layout.homeRecommendationColumns
        ),
        spacing: 18
      ) {
        ForEach(Track.catalog) { track in
          recommendationCard(track, width: nil)
        }
      }
    }
  }

  private func recommendationCard(_ track: Track, width: CGFloat?) -> some View {
    Button {
      player.play(track)
      openPlayer()
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        ArtworkView(url: track.artworkURL, cornerRadius: 28, placeholderSystemImage: "music.note")
          .aspectRatio(1, contentMode: .fit)

        Text(track.title)
          .font(.subheadline.bold())
          .lineLimit(1)

        Text(track.artist)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(width: width, alignment: .leading)
    }
    .buttonStyle(.plain)
  }

  private var popularList: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Популярное").font(.title2.bold())

      ForEach(Track.catalog.prefix(5)) { track in
        popularRow(track)

        if track.id != Track.catalog.prefix(5).last?.id {
          Divider().overlay(.white.opacity(0.05))
        }
      }
    }
  }

  private func popularGrid(layout: AdaptiveLayout) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Популярное").font(.title2.bold())

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: layout.listColumns),
        spacing: 0
      ) {
        ForEach(Track.catalog.prefix(6)) { track in
          popularRow(track)
            .overlay(alignment: .bottom) {
              Divider().overlay(.white.opacity(0.05))
            }
        }
      }
    }
  }

  private func popularRow(_ track: Track) -> some View {
    TrackRow(
      track: track,
      isPlaying: player.currentTrack?.id == track.id && player.isPlaying,
      action: {
        player.play(track)
      },
      playlists: library.playlists,
      isTrackInPlaylist: { playlistID in
        library.contains(track, in: playlistID)
      },
      toggleTrackInPlaylistAction: { playlistID in
        library.toggleTrack(track, in: playlistID)
      },
      createPlaylistAction: {
        playlistTrackForCreation = track
      },
      playNextAction: {
        library.addNext(track, after: player.currentTrack)
      },
      addToQueueAction: {
        library.ensureQueueContains(track)
      }
    )
  }

  private func format(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
  }
}
