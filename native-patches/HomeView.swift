import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore

  let openPlayer: () -> Void
  let openSearch: () -> Void


  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: layout.isWide ? 34 : 28) {
            if
              !player.hasStartedPlaybackThisSession,
              let candidate = player.resumeCandidate,
              let track = player.resumeTrack
            {
              resumeListening(
                track: track,
                candidate: candidate,
                layout: layout
              )
            }

            discoverySections

            if layout.isWide {
              recommendationsGrid(layout: layout)
              popularGrid(layout: layout)
            } else {
              recommendationsCarousel
              popularList
            }
          }
          .padding(.horizontal, layout.horizontalPadding)
          .padding(.top, layout.isCompactLandscapePhone ? 4 : 8)
          .padding(.bottom, layout.isCompactLandscapePhone ? 132 : 170)
          .adaptiveFrame(maxWidth: layout.contentMaxWidth)
        }
        .scrollContentBackground(.hidden)
      }
      .navigationTitle("Главная")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: openSearch) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 20, weight: .semibold))
              .frame(width: 42, height: 42)
              .background(
                .white.opacity(0.065),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                  .stroke(.white.opacity(0.08), lineWidth: 1)
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Поиск")
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
  }

  private var discoverySections: some View {
    VStack(alignment: .leading, spacing: 28) {
      VStack(alignment: .leading, spacing: 14) {
        Text("Подборки").font(.title2.bold())
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 14) {
            collectionLink("На несколько минут", subtitle: "До 3 минут", icon: "clock", tracks: Track.catalog.filter { $0.duration <= 180 })
            collectionLink("Слушать подольше", subtitle: "От 3 минут", icon: "headphones", tracks: Track.catalog.filter { $0.duration > 180 })
            collectionLink("Вся коллекция", subtitle: "Все нашиды Muwa", icon: "square.stack", tracks: Track.catalog)
          }
        }
      }
      VStack(alignment: .leading, spacing: 12) {
        Text("Исполнители").font(.title2.bold())
        // Channel handles in the legacy catalog are not verified artist names.
        discoveryPlaceholder("person.2", title: "Знакомство с голосами", detail: "Страницы исполнителей появятся здесь вместе с их нашидами.")
      }
      VStack(alignment: .leading, spacing: 12) {
        Text("Новые релизы").font(.title2.bold())
        // Do not label legacy tracks as new without a verified release date.
        discoveryPlaceholder("sparkles", title: "Здесь будут новые нашиды", detail: "А пока откройте подборки и найдите то, что хочется послушать.")
      }
    }
  }

  private func collectionLink(_ title: String, subtitle: String, icon: String, tracks: [Track]) -> some View {
    NavigationLink {
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(tracks) { track in popularRow(track) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 170)
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 27, weight: .light))
          .foregroundStyle(Color(red: 0.72, green: 0.82, blue: 0.98))
        Spacer(minLength: 8)
        Text(title).font(.headline).lineLimit(2)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      .frame(width: 170, height: 136, alignment: .leading)
      .padding(18)
      .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func discoveryPlaceholder(_ icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon).font(.title2).foregroundStyle(.secondary).frame(width: 30)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
  }

  private func resumeListening(
    track: Track,
    candidate: PlaybackResumeCandidate,
    layout: AdaptiveLayout
  ) -> some View {
    let coverSize: CGFloat = layout.isPad ? 92 : (layout.isLandscape ? 72 : 82)
    let progress = candidate.duration > 0
      ? min(1, max(0, candidate.position / candidate.duration))
      : 0

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text("ПРОДОЛЖИТЬ СЛУШАТЬ")
          .font(.system(size: 10, weight: .bold))
          .tracking(2)
          .foregroundStyle(.secondary)

        Spacer()

        Button {
          withAnimation(.easeOut(duration: 0.18)) {
            player.dismissResumeCandidate()
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .bold))
            .frame(width: 28, height: 28)
            .background(.white.opacity(0.055), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.72))
        .accessibilityLabel("Скрыть предложение продолжить")
      }

      HStack(spacing: 12) {
        Button {
          player.resumeSavedPlayback(autoplay: false)
          openPlayer()
        } label: {
          ArtworkView(
            url: track.artworkURL,
            cornerRadius: layout.isPad ? 22 : 19,
            placeholderSystemImage: "music.note"
          )
          .frame(width: coverSize, height: coverSize)
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 7) {
          Text(track.title)
            .font(.system(size: layout.isPad ? 20 : 18, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.82)

          Text(track.artist)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)

          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(.white.opacity(0.10))
                .frame(height: 3)

              Capsule()
                .fill(.white.opacity(0.82))
                .frame(width: proxy.size.width * progress, height: 3)
            }
          }
          .frame(height: 3)

          HStack(spacing: 8) {
            Text(format(candidate.position))
              .font(.caption2)
              .foregroundStyle(.secondary)

            Spacer()

            Button {
              player.resumeSavedPlayback(autoplay: true)
            } label: {
              Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
              player.resumeSavedPlayback(autoplay: false)
              openPlayer()
            } label: {
              HStack(spacing: 4) {
                Text("Открыть")
                Image(systemName: "chevron.right")
              }
              .font(.system(size: 11, weight: .semibold))
              .padding(.horizontal, 11)
              .frame(height: 36)
              .background(
                .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
              )
            }
            .buttonStyle(.plain)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(12)
    .background(
      .white.opacity(0.025),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(.white.opacity(0.05), lineWidth: 1)
    }
    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
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
      isInPlaylist: library.isInPlaylist(track),
      togglePlaylistAction: {
        library.togglePlaylist(track)
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


