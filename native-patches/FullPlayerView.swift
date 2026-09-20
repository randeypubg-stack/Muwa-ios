import SwiftUI

struct MorphingPlayerView: View {
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var premium: PremiumManager
  @EnvironmentObject private var downloads: DownloadManager

  @Binding var selection: AppTab
  @Binding var expansion: CGFloat
  let chromeDrop: CGFloat
  let safeTopInset: CGFloat
  let safeBottomInset: CGFloat
  let safeLeadingInset: CGFloat
  let safeTrailingInset: CGFloat

  @State private var premiumPresented = false
  @State private var queuePresented = false
  @State private var playlistCreatePresented = false
  @State private var subtitlesVisible = false
  @State private var subtitleLanguage: SubtitleLanguage = .arabic
  @State private var downloadError: String?
  @State private var dragStartExpansion: CGFloat?
  @State private var coverDragX: CGFloat = 0
  @State private var coverSwipeTrack: Track?
  @State private var coverSwipeDirection: Int = 0
  @State private var coverPaging = false

  private var track: Track {
    player.currentTrack ?? Track.catalog[0]
  }

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
      let viewportWidth = layout.viewportWidth
      let viewportHeight = layout.viewportHeight
      let p = clamp(expansion)

      let horizontalPadding = layout.horizontalPadding
      let safeSideInset = max(
        horizontalPadding,
        max(safeLeadingInset, safeTrailingInset)
      )
      let usableWidth = max(0, viewportWidth - safeSideInset * 2)
      let miniWidthLimit = layout.bottomChromeMaxWidth.isFinite
        ? layout.bottomChromeMaxWidth
        : usableWidth
      let miniWidth = min(miniWidthLimit, usableWidth)
      let miniHeight: CGFloat = 58

      let bottomBarHeight: CGFloat = 62
      let playerBarGap: CGFloat = 8
      let miniCenterY =
        viewportHeight
        - bottomBarHeight
        - playerBarGap
        - (miniHeight / 2)
        - (layout.isPhone ? 6 : 0)
        + chromeDrop

      let fullSurfaceHeight =
        viewportHeight
        + safeTopInset
        + safeBottomInset
      let fullCenterY =
        (viewportHeight + safeBottomInset - safeTopInset) / 2
      let travel = max(1, miniCenterY - fullCenterY)

      let playerWidth = lerp(miniWidth, viewportWidth, p)
      let playerHeight = lerp(miniHeight, fullSurfaceHeight, p)
      let playerCenterY = lerp(miniCenterY, fullCenterY, p)
      let cornerRadius = lerp(27, 0, p)

      let isShortPhone = layout.isPhone && viewportHeight < 740
      let artworkLimit = isShortPhone ? min(layout.playerArtworkSize, 210) : layout.playerArtworkSize
      let geometry = PlayerGeometry(
        width: viewportWidth, height: viewportHeight,
        safeTop: safeTopInset, chromeDrop: chromeDrop, phone: layout.isPhone,
        contentWidth: min(layout.contentMaxWidth, usableWidth), artworkLimit: artworkLimit
      )
      let fullArtworkSize = geometry.artworkSize
      let fullArtworkY = geometry.artworkY

      let miniArtworkSize: CGFloat = 42
      let miniArtworkX: CGFloat = 7 + (miniArtworkSize / 2)
      let miniArtworkY: CGFloat = miniHeight / 2
      let artworkSize = lerp(miniArtworkSize, fullArtworkSize, p)
      let artworkX = lerp(miniArtworkX, geometry.artworkX, p)
      let artworkY = lerp(miniArtworkY, fullArtworkY, p)

      let miniReservedTrailing: CGFloat = 7 + 34 + 10 + 34 + 10
      let miniMetaLeft: CGFloat = 7 + miniArtworkSize + 10
      let miniMetaWidth = max(
        84,
        miniWidth - miniMetaLeft - miniReservedTrailing
      )

      let fullContentWidth = geometry.controlsWidth
      let fullMetaWidth = max(120, fullContentWidth - 52)
      let fullMetaLeft = geometry.controlsX - fullContentWidth / 2

      let metadataWidth = lerp(miniMetaWidth, fullMetaWidth, p)
      let metadataLeft = lerp(miniMetaLeft, fullMetaLeft, p)
      let fullMetadataY = geometry.metadataY
      let metadataY = lerp(miniHeight / 2, fullMetadataY, p)

      let fullOpacity = smoothStep((p - 0.18) / 0.52)
      let miniOpacity = 1 - smoothStep(p / 0.30)

      ZStack {
        playerSurface(
          width: playerWidth,
          height: playerHeight,
          cornerRadius: cornerRadius,
          progress: p
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
          if expansion < 0.18 {
            settle(to: 1)
          }
        }
        .simultaneousGesture(
          expansionDragGesture(
            travel: travel,
            miniCenterY: miniCenterY,
            miniWidth: miniWidth,
            miniHeight: miniHeight,
            viewportWidth: viewportWidth
          )
        )
        .position(x: viewportWidth / 2, y: playerCenterY)

        sharedArtwork(
          size: artworkSize,
          cornerRadius: lerp(13, 36, p),
          progress: p
        )
        .simultaneousGesture(
          expansionDragGesture(
            travel: travel,
            miniCenterY: miniCenterY,
            miniWidth: miniWidth,
            miniHeight: miniHeight,
            viewportWidth: viewportWidth
          )
        )
        .position(
          x: ((viewportWidth - playerWidth) / 2) + artworkX,
          y: playerCenterY - (playerHeight / 2) + artworkY
        )

        sharedMetadata(
          width: metadataWidth,
          progress: p
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
          expansionDragGesture(
            travel: travel,
            miniCenterY: miniCenterY,
            miniWidth: miniWidth,
            miniHeight: miniHeight,
            viewportWidth: viewportWidth
          )
        )
        .position(
          x: ((viewportWidth - playerWidth) / 2) + metadataLeft + (metadataWidth / 2),
          y: playerCenterY - (playerHeight / 2) + metadataY
        )

        miniControls(
          playerWidth: playerWidth,
          playerHeight: playerHeight,
          centerY: playerCenterY,
          opacity: miniOpacity,
          viewportWidth: viewportWidth
        )

        miniProgressLine(
          playerWidth: playerWidth,
          playerHeight: playerHeight,
          centerY: playerCenterY,
          opacity: miniOpacity,
          viewportWidth: viewportWidth
        )

        fullControls(
          layout: layout,
          playerWidth: playerWidth,
          playerHeight: playerHeight,
          centerY: playerCenterY,
          contentWidth: fullContentWidth,
          artworkY: fullArtworkY,
          artworkSize: fullArtworkSize,
          metadataY: fullMetadataY,
          opacity: fullOpacity,
          isShortPhone: isShortPhone,
          chromeDrop: chromeDrop,
          safeTopInset: safeTopInset,
          geometry: geometry
        )
      }
      .frame(width: viewportWidth, height: viewportHeight)
    }
    .sheet(isPresented: $premiumPresented) {
      PremiumView(compact: true)
        .presentationDetents([.fraction(0.60), .large])
        .presentationDragIndicator(.hidden)
    }
    .sheet(isPresented: $queuePresented) {
      QueueView()
    }
    .sheet(isPresented: $playlistCreatePresented) {
      PlaylistCreateSheet { name in
        let playlistID = library.createPlaylist(name: name)
        library.addTrack(track, to: playlistID)
      }
    }
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

  private func playerSurface(
    width: CGFloat,
    height: CGFloat,
    cornerRadius: CGFloat,
    progress: CGFloat
  ) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)

      ArtworkBackdrop(url: track.artworkURL)
        .frame(width: width, height: height)
        .clipped()
        .opacity(Double(smoothStep((progress - 0.08) / 0.72)))

      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
          Color.black.opacity(
            Double(lerp(0.12, 0.42, progress))
          )
        )

      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(
          Color.white.opacity(
            Double(lerp(0.14, 0.02, progress))
          ),
          lineWidth: 1
        )
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .shadow(
      color: .black.opacity(Double(lerp(0.16, 0.08, progress))),
      radius: lerp(24, 8, progress),
      y: lerp(10, 2, progress)
    )
  }

  private func sharedArtwork(
    size: CGFloat,
    cornerRadius: CGFloat,
    progress: CGFloat
  ) -> some View {
    let pageGap = max(14, size * 0.055)
    let pageDistance = size + pageGap
    let drag = progress > 0.74 ? coverDragX : 0
    let normalized = min(1, abs(drag) / max(1, pageDistance))

    return ZStack {
      if let coverSwipeTrack, coverSwipeDirection != 0 {
        artworkPage(
          track: coverSwipeTrack,
          size: size,
          cornerRadius: cornerRadius,
          showSubtitle: false,
          progress: progress
        )
        .offset(
          x: coverSwipeDirection < 0
            ? pageDistance + drag
            : -pageDistance + drag
        )
        .scaleEffect(0.985 + (normalized * 0.015))
        .opacity(0.72 + (normalized * 0.28))
      }

      artworkPage(
        track: track,
        size: size,
        cornerRadius: cornerRadius,
        showSubtitle: true,
        progress: progress
      )
      .offset(x: drag)
      .scaleEffect(1 - (normalized * 0.018))
      .opacity(1 - (normalized * 0.08))
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .shadow(
      color: .black.opacity(Double(0.34 * smoothStep(progress))),
      radius: 28 * smoothStep(progress),
      y: 16 * smoothStep(progress)
    )
    .contentShape(Rectangle())
    .allowsHitTesting(progress > 0.74 && !coverPaging)
    .simultaneousGesture(
      DragGesture(minimumDistance: 10)
        .onChanged { value in
          guard expansion > 0.74, !coverPaging else { return }

          let horizontal = value.translation.width
          let vertical = value.translation.height
          guard abs(horizontal) > abs(vertical) * 1.08 else { return }

          let direction = horizontal < 0 ? -1 : 1
          if coverSwipeDirection != direction || coverSwipeTrack == nil {
            coverSwipeDirection = direction
            coverSwipeTrack = swipeNeighbor(direction: direction)
          }

          let hasNeighbor = coverSwipeTrack != nil
          if hasNeighbor {
            coverDragX = min(pageDistance, max(-pageDistance, horizontal))
          } else {
            coverDragX = rubberBand(horizontal, limit: size * 0.12)
          }
        }
        .onEnded { value in
          guard expansion > 0.74, !coverPaging else { return }

          let horizontal = value.translation.width
          let vertical = value.translation.height
          guard abs(horizontal) > abs(vertical) * 1.08 else {
            resetCoverPaging()
            return
          }

          let projected = value.predictedEndTranslation.width
          let threshold = max(46, size * 0.17)
          let shouldPage =
            abs(horizontal) >= threshold
            || abs(projected) >= threshold * 1.35

          guard shouldPage, let destination = coverSwipeTrack else {
            resetCoverPaging()
            return
          }

          coverPaging = true
          let target: CGFloat = coverSwipeDirection < 0 ? -pageDistance : pageDistance

          withAnimation(
            .spring(response: 0.30, dampingFraction: 0.90, blendDuration: 0.10)
          ) {
            coverDragX = target
          }

          DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            player.play(destination)

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
              coverDragX = 0
              coverSwipeTrack = nil
              coverSwipeDirection = 0
            }

            coverPaging = false
          }
        }
    )
  }

  private func artworkPage(
    track pageTrack: Track,
    size: CGFloat,
    cornerRadius: CGFloat,
    showSubtitle: Bool,
    progress: CGFloat
  ) -> some View {
    ArtworkView(
      url: pageTrack.artworkURL,
      cornerRadius: cornerRadius,
      placeholderSystemImage: "music.note"
    )
    .frame(width: size, height: size)
    .overlay(alignment: .trailing) {
      if showSubtitle, subtitlesVisible, progress > 0.74 {
        PlayerSubtitleOverlay(
          track: pageTrack,
          currentTime: player.currentTime,
          language: subtitleLanguage
        )
        .offset(x: min(46, size * 0.14))
        .transition(.opacity)
      }
    }
  }

  private func swipeNeighbor(direction: Int) -> Track? {
    let queue = library.queueTracks.isEmpty ? Track.catalog : library.queueTracks
    guard !queue.isEmpty else { return nil }

    guard let currentIndex = queue.firstIndex(where: { $0.id == track.id }) else {
      return nil
    }

    if direction < 0 {
      if player.shuffleOn {
        return queue
          .filter { $0.id != track.id }
          .randomElement()
      }

      let nextIndex = currentIndex + 1
      if nextIndex < queue.count {
        return queue[nextIndex]
      }

      return player.repeatOn ? queue.first : nil
    }

    if currentIndex > 0 {
      return queue[currentIndex - 1]
    }

    return player.repeatOn ? queue.last : nil
  }

  private func rubberBand(
    _ translation: CGFloat,
    limit: CGFloat
  ) -> CGFloat {
    let sign: CGFloat = translation < 0 ? -1 : 1
    let magnitude = abs(translation)
    let resisted = limit * (1 - (1 / ((magnitude / max(1, limit)) + 1)))
    return sign * resisted
  }

  private func resetCoverPaging() {
    withAnimation(
      .spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.08)
    ) {
      coverDragX = 0
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
      guard abs(coverDragX) < 1 else { return }
      coverSwipeTrack = nil
      coverSwipeDirection = 0
    }
  }

  private func sharedMetadata(
    width: CGFloat,
    progress: CGFloat
  ) -> some View {
    let titleSize = lerp(13, 27, smoothStep(progress))
    let artistSize = lerp(10, 13, smoothStep(progress))

    return VStack(alignment: .leading, spacing: lerp(2, 4, progress)) {
      Text(track.title)
        .font(
          .system(
            size: titleSize,
            weight: progress > 0.48 ? .bold : .semibold,
            design: progress > 0.48 ? .rounded : .default
          )
        )
        .lineLimit(progress > 0.64 ? 2 : 1)
        .minimumScaleFactor(0.78)

      Text(track.artist)
        .font(.system(size: artistSize))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(width: width, alignment: .leading)
  }

  private func miniControls(
    playerWidth: CGFloat,
    playerHeight: CGFloat,
    centerY: CGFloat,
    opacity: CGFloat,
    viewportWidth: CGFloat
  ) -> some View {
    let left = (viewportWidth - playerWidth) / 2
    let nextX = left + playerWidth - 7 - 17
    let playX = nextX - 34 - 10

    return ZStack {
      Button(action: player.toggle) {
        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 15, weight: .bold))
          .frame(width: 34, height: 34)
          .background(.white.opacity(0.055), in: Circle())
      }
      .buttonStyle(.plain)
      .position(x: playX, y: centerY)

      Button(action: player.next) {
        Image(systemName: "forward.fill")
          .font(.system(size: 14, weight: .semibold))
          .frame(width: 34, height: 34)
          .background(.white.opacity(0.085), in: Circle())
      }
      .buttonStyle(.plain)
      .position(x: nextX, y: centerY)
    }
    .opacity(Double(opacity))
    .allowsHitTesting(opacity > 0.58)
  }

  private func miniProgressLine(
    playerWidth: CGFloat,
    playerHeight: CGFloat,
    centerY: CGFloat,
    opacity: CGFloat,
    viewportWidth: CGFloat
  ) -> some View {
    let lineWidth = max(10, playerWidth - 32)
    let y = centerY + (playerHeight / 2) - 2

    return Capsule()
      .fill(.white.opacity(0.12))
      .frame(width: lineWidth, height: 2)
      .overlay(alignment: .leading) {
        Capsule()
          .fill(.white.opacity(0.72))
          .scaleEffect(
            x: max(0, min(1, player.progress)),
            y: 1,
            anchor: .leading
          )
      }
      .position(x: viewportWidth / 2, y: y)
      .opacity(Double(opacity))
      .allowsHitTesting(false)
  }

  private func fullControls(
    layout: AdaptiveLayout,
    playerWidth: CGFloat,
    playerHeight: CGFloat,
    centerY: CGFloat,
    contentWidth: CGFloat,
    artworkY: CGFloat,
    artworkSize: CGFloat,
    metadataY: CGFloat,
    opacity: CGFloat,
    isShortPhone: Bool,
    chromeDrop: CGFloat,
    safeTopInset: CGFloat,
    geometry: PlayerGeometry
  ) -> some View {
    let containerTop = centerY - (playerHeight / 2)
    let localCenterX = geometry.controlsX
    let progressY = containerTop + geometry.progressY
    let transportY = containerTop + geometry.transportY
    let actionsY = containerTop + geometry.actionsY

    return ZStack {
      fullTopBar(width: min(layout.contentMaxWidth, layout.viewportWidth - layout.horizontalPadding * 2))
        .position(
          x: layout.viewportWidth / 2,
          y: containerTop + safeTopInset + 28
        )

      Button {
        library.toggleLike(track)
      } label: {
        Image(systemName: library.isLiked(track) ? "heart.fill" : "heart")
          .foregroundStyle(library.isLiked(track) ? .pink : .white)
          .frame(width: 42, height: 42)
          .background(.white.opacity(0.055), in: Circle())
      }
      .buttonStyle(.plain)
      .position(
        x: localCenterX + (contentWidth / 2) - 21,
        y: containerTop + metadataY
      )

      fullProgress(width: contentWidth)
        .position(x: localCenterX, y: progressY)

      transport(compact: layout.isPhone || layout.viewportWidth < 390)
        .frame(width: contentWidth)
        .position(x: localCenterX, y: transportY)

      smallActions
        .position(x: localCenterX, y: actionsY)
    }
    .opacity(Double(opacity))
    .allowsHitTesting(opacity > 0.60)
    .zIndex(30)
  }

  private func fullTopBar(width: CGFloat) -> some View {
    HStack {
      Button {
        settle(to: 0)
      } label: {
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

        Menu("Добавить в плей-лист") {
          if library.playlists.isEmpty {
            Button {
              playlistCreatePresented = true
            } label: {
              Label("Создать первый плей-лист", systemImage: "plus")
            }
          } else {
            ForEach(library.playlists) { playlist in
              Button {
                library.toggleTrack(track, in: playlist.id)
              } label: {
                Label(
                  playlist.name,
                  systemImage: library.contains(track, in: playlist.id)
                    ? "checkmark.circle.fill"
                    : "circle"
                )
              }
            }

            Divider()

            Button {
              playlistCreatePresented = true
            } label: {
              Label("Новый плей-лист", systemImage: "plus")
            }
          }
        }

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

        Menu {
          Button {
            player.startSleepTimer(minutes: 15)
          } label: {
            Label("15 минут", systemImage: "timer")
          }

          Button {
            player.startSleepTimer(minutes: 30)
          } label: {
            Label("30 минут", systemImage: "timer")
          }

          Button {
            player.startSleepTimer(minutes: 45)
          } label: {
            Label("45 минут", systemImage: "timer")
          }

          Button {
            player.startSleepTimer(minutes: 60)
          } label: {
            Label("60 минут", systemImage: "timer")
          }

          Button {
            player.sleepAfterCurrentTrackEnds()
          } label: {
            Label("После текущего нашида", systemImage: "moon.zzz")
          }

          if player.sleepTimerSummary != nil {
            Divider()

            Button(role: .destructive) {
              player.cancelSleepTimer()
            } label: {
              Label("Выключить таймер", systemImage: "xmark.circle")
            }
          }
        } label: {
          Label(
            player.sleepTimerSummary.map { "Таймер сна · \($0)" } ?? "Таймер сна",
            systemImage: "moon.zzz"
          )
        }

        Divider()

        Button {
          handleDownload()
        } label: {
          Label(
            downloads.isDownloaded(track) ? "Сохранено офлайн" : "Скачать MP3",
            systemImage: downloads.isDownloaded(track)
              ? "checkmark.circle"
              : "arrow.down.circle"
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
    .frame(width: width)
  }

  private func fullProgress(width: CGFloat) -> some View {
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
    .frame(width: width)
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

        withAnimation(.easeInOut(duration: 0.18)) {
          subtitlesVisible.toggle()
        }
      } label: {
        ZStack(alignment: .topTrailing) {
          Image(
            systemName: subtitlesVisible
              ? "captions.bubble.fill"
              : "captions.bubble"
          )
          .frame(width: 44, height: 44)
          .background(
            .white.opacity(subtitlesVisible ? 0.14 : 0.055),
            in: RoundedRectangle(cornerRadius: 16)
          )

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
          .background(
            .white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 16)
          )
      }
      .buttonStyle(.plain)

      if premium.isPremium {
        AirPlayButton()
          .frame(width: 44, height: 44)
          .background(
            .white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 16)
          )
      } else {
        Button {
          premiumPresented = true
        } label: {
          ZStack(alignment: .topTrailing) {
            Image(systemName: "airplayaudio")
              .frame(width: 44, height: 44)
              .background(
                .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 16)
              )

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

  private func expansionDragGesture(
    travel: CGFloat,
    miniCenterY: CGFloat,
    miniWidth: CGFloat,
    miniHeight: CGFloat,
    viewportWidth: CGFloat
  ) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .named("playerContainer"))
      .onChanged { value in
        let vertical = value.translation.height
        let horizontal = abs(value.translation.width)

        guard abs(vertical) > horizontal * 1.08 else { return }

        if dragStartExpansion == nil && expansion < 0.20 {
          let miniMinX = (viewportWidth - miniWidth) / 2
          let miniMaxX = miniMinX + miniWidth
          let miniMinY = miniCenterY - (miniHeight / 2) - 8
          let miniMaxY = miniCenterY + (miniHeight / 2) + 8

          guard
            value.startLocation.x >= miniMinX,
            value.startLocation.x <= miniMaxX,
            value.startLocation.y >= miniMinY,
            value.startLocation.y <= miniMaxY
          else { return }
        }

        if dragStartExpansion == nil {
          dragStartExpansion = expansion
        }

        let start = dragStartExpansion ?? expansion
        let next = start - (vertical / max(1, travel))
        expansion = clamp(next)
      }
      .onEnded { value in
        defer { dragStartExpansion = nil }

        guard dragStartExpansion != nil else { return }

        let projectedDelta =
          (value.predictedEndTranslation.height - value.translation.height)
          / max(1, travel)
        let projected = clamp(expansion - (projectedDelta * 0.34))
        let target: CGFloat = projected >= 0.52 ? 1 : 0

        withAnimation(
          .spring(response: 0.52, dampingFraction: 0.96, blendDuration: 0.16)
        ) {
          expansion = target
        }
      }
  }

  private func settle(to target: CGFloat) {
    withAnimation(
      .spring(response: 0.48, dampingFraction: 0.94, blendDuration: 0.14)
    ) {
      expansion = clamp(target)
    }
  }

  private func handleDownload() {
    guard !downloads.isDownloaded(track) else { return }

    guard premium.isPremium else {
      premiumPresented = true
      return
    }

    Task {
      do {
        try await downloads.download(track)
      } catch {
        downloadError = error.localizedDescription
      }
    }
  }

  private func time(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    return String(
      format: "%d:%02d",
      Int(seconds) / 60,
      Int(seconds) % 60
    )
  }

  private func clamp(_ value: CGFloat) -> CGFloat {
    min(1, max(0, value))
  }

  private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + ((b - a) * clamp(t))
  }

  private func smoothStep(_ value: CGFloat) -> CGFloat {
    let x = clamp(value)
    return x * x * (3 - (2 * x))
  }
}


// Pure geometry shared with regression checks; coordinates are local to the full surface.
struct PlayerGeometry {
  let artworkSize: CGFloat
  let artworkX: CGFloat
  let artworkY: CGFloat
  let controlsWidth: CGFloat
  let controlsX: CGFloat
  let metadataY: CGFloat
  let progressY: CGFloat
  let transportY: CGFloat
  let actionsY: CGFloat
  let chromeTop: CGFloat

  init(width: CGFloat, height: CGFloat, safeTop: CGFloat, chromeDrop: CGFloat,
       phone: Bool, contentWidth: CGFloat, artworkLimit: CGFloat) {
    chromeTop = height + safeTop - 62 - (phone ? 9 : 0) + chromeDrop
    let landscape = width > height * 1.2 && height < 520
    let short = phone && height < 740
    if landscape {
      controlsWidth = min(420, contentWidth * 0.56)
      controlsX = (width + contentWidth) / 2 - controlsWidth / 2
      artworkSize = min(artworkLimit, contentWidth - controlsWidth - 24, chromeTop - safeTop - 76)
      artworkX = (width - contentWidth) / 2 + (contentWidth - controlsWidth - 16) / 2
      artworkY = safeTop + 56 + artworkSize / 2
      actionsY = chromeTop - 34
      transportY = actionsY - 58
      progressY = transportY - 66
      metadataY = progressY - 58
    } else {
      controlsWidth = contentWidth
      controlsX = width / 2
      artworkX = width / 2
      let top = safeTop + (short ? 44 : 58)
      let metaGap: CGFloat = short ? 34 : 44
      let progressGap: CGFloat = short ? 68 : 84
      let transportGap: CGFloat = short ? 76 : 88
      let actionGap: CGFloat = short ? 62 : 74
      let available = chromeTop - 34 - actionGap - transportGap - progressGap - metaGap - top
      artworkSize = min(artworkLimit, max(60, available))
      artworkY = top + artworkSize / 2
      metadataY = top + artworkSize + metaGap
      progressY = metadataY + progressGap
      transportY = progressY + transportGap
      actionsY = transportY + actionGap
    }
  }
}
