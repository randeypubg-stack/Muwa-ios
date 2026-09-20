import SwiftUI

struct FullPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var premium: PremiumManager
  @EnvironmentObject private var downloads: DownloadManager

  @Binding var selection: AppTab
  @State private var premiumPresented = false
  @State private var queuePresented = false
  @State private var subtitlesVisible = false
  @State private var subtitleLanguage: SubtitleLanguage = .arabic
  @State private var downloadError: String?
  @GestureState private var coverDragX: CGFloat = 0

  private var track: Track {
    player.currentTrack ?? Track.catalog[0]
  }

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
      let availableWidth = max(0, proxy.size.width - layout.horizontalPadding * 2)
      let contentWidth = min(layout.contentMaxWidth, availableWidth)
      let chromeLimit = layout.bottomChromeMaxWidth.isFinite
        ? layout.bottomChromeMaxWidth : availableWidth
      let chromeWidth = min(chromeLimit, availableWidth)

      ZStack(alignment: .bottom) {
        ArtworkBackdrop(url: track.artworkURL).ignoresSafeArea()

        ScrollView(.vertical, showsIndicators: false) {
          VStack(spacing: 14) {
            Capsule()
              .fill(.white.opacity(0.34))
              .frame(width: 38, height: 4)
              .padding(.top, layout.isCompactLandscapePhone ? 2 : 8)

            topBar

            if layout.playerUsesSplitLayout {
              splitPlayer(layout: layout)
            } else {
              portraitPlayer(layout: layout)
            }

            Spacer(minLength: layout.isCompactLandscapePhone ? 88 : 128)
          }
          .frame(width: contentWidth)
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: proxy.size.width)

        BottomBar(
          selection: $selection,
          playerActive: true,
          openPlayer: {},
          selectTab: { tab in
            selection = tab
            dismiss()
          }
        )
        .frame(width: chromeWidth)
        .padding(.bottom, max(proxy.safeAreaInsets.bottom, layout.isCompactLandscapePhone ? 4 : 10))
      }
    }
    .sheet(isPresented: $premiumPresented) { PremiumView() }
    .sheet(isPresented: $queuePresented) { QueueView() }
    .alert(
      "Не удалось скачать",
      isPresented: Binding(
        get: { downloadError != nil },
        set: { if !$0 { downloadError = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(downloadError ?? "Неизвестная ошибка")
    }
  }

  private func portraitPlayer(layout: AdaptiveLayout) -> some View {
    VStack(spacing: 17) {
      artwork(size: layout.playerArtworkSize)
      titleBlock

      if subtitlesVisible {
        SubtitlePanel(track: track, currentTime: player.currentTime, language: $subtitleLanguage)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      progress
      transport(compact: false)
      smallActions
    }
    .frame(maxWidth: .infinity)
  }

  private func splitPlayer(layout: AdaptiveLayout) -> some View {
    HStack(alignment: .top, spacing: layout.isPad ? 38 : 28) {
      VStack(spacing: 16) {
        artwork(size: layout.playerArtworkSize)
        if subtitlesVisible && layout.isPad {
          SubtitlePanel(track: track, currentTime: player.currentTime, language: $subtitleLanguage)
            .transition(.opacity)
        }
      }
      .frame(maxWidth: layout.isPad ? 460 : 330)

      VStack(spacing: layout.isCompactLandscapePhone ? 11 : 16) {
        titleBlock

        if subtitlesVisible && !layout.isPad {
          SubtitlePanel(track: track, currentTime: player.currentTime, language: $subtitleLanguage)
            .transition(.opacity)
        }

        progress
        transport(compact: layout.isCompactLandscapePhone)
        smallActions
      }
      .frame(maxWidth: 560)
      .padding(.top, layout.isCompactLandscapePhone ? 2 : 14)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var topBar: some View {
    HStack {
      Button(action: { dismiss() }) {
        Image(systemName: "chevron.down")
          .font(.system(size: 18, weight: .semibold))
          .frame(width: 42, height: 42)
          .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)

      Spacer()
      Text("Сейчас играет")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()

      Menu {
        Button {
          library.toggleLike(track)
        } label: {
          Label(
            library.isLiked(track) ? "Убрать из избранного" : "Добавить в избранное",
            systemImage: library.isLiked(track) ? "heart.slash" : "heart"
          )
        }
        Button {
          library.togglePlaylist(track)
        } label: {
          Label(
            library.isInPlaylist(track) ? "Убрать из плейлиста" : "Добавить в плейлист",
            systemImage: "music.note.list"
          )
        }
        Menu("Добавить следующим") {
          ForEach(Track.catalog.filter { $0.id != track.id }) { candidate in
            Button(candidate.title) { library.addNext(candidate, after: track) }
          }
        }
        Divider()
        Button {
          handleDownload()
        } label: {
          Label(
            downloads.isDownloaded(track) ? "Сохранено офлайн" : "Скачать MP3",
            systemImage: downloads.isDownloaded(track) ? "checkmark.circle" : "arrow.down.circle"
          )
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 19, weight: .semibold))
          .frame(width: 42, height: 42)
          .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)
    }
  }

  private func artwork(size: CGFloat) -> some View {
    ArtworkView(url: track.artworkURL, cornerRadius: 36)
      .frame(width: size, height: size)
      .overlay(alignment: .trailing) {
        if subtitlesVisible {
          PlayerSubtitleOverlay(
            track: track, currentTime: player.currentTime, language: subtitleLanguage
          )
          .offset(x: min(46, size * 0.14))
        }
      }
      .shadow(color: .black.opacity(0.40), radius: 35, y: 20)
      .offset(x: coverDragX)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 12)
          .updating($coverDragX) { value, state, _ in
            if abs(value.translation.width) > abs(value.translation.height) {
              state = value.translation.width
            }
          }
          .onEnded { value in
            guard abs(value.translation.width) > 54,
              abs(value.translation.width) > abs(value.translation.height)
            else { return }
            if value.translation.width < 0 { player.next() } else { player.previous() }
          }
      )
      .animation(.spring(response: 0.34, dampingFraction: 0.82), value: track.id)
  }

  private var titleBlock: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(track.title)
          .font(.system(size: 27, weight: .bold, design: .rounded))
          .lineLimit(2)
          .minimumScaleFactor(0.84)
        Text(track.artist)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        library.toggleLike(track)
      } label: {
        Image(systemName: library.isLiked(track) ? "heart.fill" : "heart")
          .foregroundStyle(library.isLiked(track) ? .pink : .white)
          .frame(width: 42, height: 42)
          .background(.white.opacity(0.055), in: Circle())
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
  }

  private var progress: some View {
    VStack(spacing: 8) {
      Slider(
        value: Binding(
          get: { player.progress },
          set: { player.seek(to: $0) }
        ),
        in: 0...1
      )
      .tint(.white)
      HStack {
        Text(time(player.currentTime))
        Spacer()
        Text(time(player.duration > 0 ? player.duration : track.duration))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func transport(compact: Bool) -> some View {
    let mainSize: CGFloat = compact ? 58 : 68
    let sideSize: CGFloat = compact ? 46 : 54
    let spacing: CGFloat = compact ? 14 : 22

    return HStack(spacing: spacing) {
      Button {
        player.shuffleOn.toggle()
      } label: {
        Image(systemName: "shuffle")
          .foregroundStyle(player.shuffleOn ? .white : .white.opacity(0.55))
          .frame(width: 38, height: 38)
      }
      Button(action: player.previous) {
        Image(systemName: "backward.fill")
          .font(.title2)
          .frame(width: sideSize, height: sideSize)
      }
      Button(action: player.toggle) {
        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: compact ? 24 : 28, weight: .bold))
          .foregroundStyle(.black)
          .frame(width: mainSize, height: mainSize)
          .background(.white, in: Circle())
      }
      Button(action: player.next) {
        Image(systemName: "forward.fill")
          .font(.title2)
          .frame(width: sideSize, height: sideSize)
      }
      Button {
        player.repeatOn.toggle()
      } label: {
        Image(systemName: "repeat")
          .foregroundStyle(player.repeatOn ? .white : .white.opacity(0.55))
          .frame(width: 38, height: 38)
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  private var smallActions: some View {
    HStack(spacing: 14) {
      Button {
        guard premium.isPremium else {
          premiumPresented = true
          return
        }
        withAnimation(.easeInOut(duration: 0.2)) { subtitlesVisible.toggle() }
      } label: {
        ZStack(alignment: .topTrailing) {
          Image(systemName: subtitlesVisible ? "captions.bubble.fill" : "captions.bubble")
            .frame(width: 44, height: 44)
            .background(
              .white.opacity(subtitlesVisible ? 0.14 : 0.055),
              in: RoundedRectangle(cornerRadius: 16))
          if !premium.isPremium {
            Image(systemName: "lock.fill")
              .font(.system(size: 8))
              .padding(5)
              .background(.black.opacity(0.7), in: Circle())
              .offset(x: 4, y: -4)
          }
        }
      }
      .buttonStyle(.plain)

      Button {
        queuePresented = true
      } label: {
        Image(systemName: "list.bullet")
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)

      if premium.isPremium {
        AirPlayButton()
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
      } else {
        Button {
          premiumPresented = true
        } label: {
          ZStack(alignment: .topTrailing) {
            Image(systemName: "airplayaudio")
              .frame(width: 44, height: 44)
              .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            Image(systemName: "lock.fill")
              .font(.system(size: 8))
              .padding(5)
              .background(.black.opacity(0.7), in: Circle())
              .offset(x: 4, y: -4)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func handleDownload() {
    guard !downloads.isDownloaded(track) else { return }
    guard premium.isPremium else {
      premiumPresented = true
      return
    }
    Task {
      do { try await downloads.download(track) } catch {
        downloadError = error.localizedDescription
      }
    }
  }

  private func time(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
  }
}
