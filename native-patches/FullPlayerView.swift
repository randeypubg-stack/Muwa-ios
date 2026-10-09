import SwiftUI

private enum ArtworkGestureAxis: Equatable {
  case undetermined
  case horizontal
  case vertical
}

struct MorphingPlayerView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var premium: PremiumManager
  @EnvironmentObject private var downloads: DownloadManager

  @Binding var expansion: CGFloat
  let chromeBottomPadding: CGFloat
  let safeTopInset: CGFloat
  let safeBottomInset: CGFloat
  let safeLeadingInset: CGFloat
  let safeTrailingInset: CGFloat

  @State private var premiumPresented = false
  @State private var queuePresented = false
  @State private var playlistCreatePresented = false
  @State private var subtitlesVisible = false
  @State private var subtitleContentTrackIDs: Set<String> = []
  @State private var downloadError: String?
  @State private var dragStartExpansion: CGFloat?
  @State private var coverDragX: CGFloat = 0
  @State private var coverSwipeTrack: Track?
  @State private var coverSwipeDirection: Int = 0
  @State private var coverPaging = false
  @State private var artworkGestureAxis: ArtworkGestureAxis = .undetermined
  @State private var artworkGestureActive = false
  @State private var artworkVerticalStartExpansion: CGFloat?

  private var track: Track {
    player.currentTrack ?? Track(id: "empty-player", title: "Выберите нашид", artist: "Muwa", duration: 0, artworkURL: nil, audioURL: URL(fileURLWithPath: "/dev/null"))
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

      let bottomBarHeight = BottomChromeLayout.barHeight
      let playerBarGap = BottomChromeLayout.playerGap
      let miniCenterY =
        viewportHeight
        - bottomBarHeight
        - playerBarGap
        - (miniHeight / 2)
        - chromeBottomPadding

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
        safeTop: safeTopInset, chromeBottomPadding: chromeBottomPadding, phone: layout.isPhone,
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
      let artworkScreenX = ((viewportWidth - playerWidth) / 2) + artworkX

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
          progress: p,
          viewportWidth: viewportWidth,
          screenCenterX: artworkScreenX,
          subtitleLeftSpace: max(0, artworkScreenX - safeSideInset),
          subtitleRightSpace: max(0,
            (geometry.controlsX > viewportWidth / 2 + 1
              ? geometry.controlsX - geometry.controlsWidth / 2 - 12
              : viewportWidth - safeSideInset) - artworkScreenX),
          expansionTravel: travel
        )
        .position(
          x: artworkScreenX,
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
          playerHeight: playerHeight,
          centerY: playerCenterY,
          contentWidth: fullContentWidth,
          metadataY: fullMetadataY,
          opacity: fullOpacity,
          safeTopInset: safeTopInset,
          geometry: geometry
        )
      }
      .frame(width: viewportWidth, height: viewportHeight)
    }
    .onChange(of: expansion) { _, value in
      if value <= 0 {
        artworkGestureActive = false
        artworkGestureAxis = .undetermined
        artworkVerticalStartExpansion = nil
        dragStartExpansion = nil
      }
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
    progress: CGFloat,
    viewportWidth: CGFloat,
    screenCenterX: CGFloat,
    subtitleLeftSpace: CGFloat,
    subtitleRightSpace: CGFloat,
    expansionTravel: CGFloat
  ) -> some View {
    let leftEdgeTravel = max(1, screenCenterX + (size * 0.42))
    let rightEdgeTravel = max(1, (viewportWidth - screenCenterX) + (size * 0.42))
    let interactionDistance = max(96, min(size * 0.54, viewportWidth * 0.38))
    let swipeProgress = min(1, abs(coverDragX) / interactionDistance)
    let eased = smoothStep(swipeProgress)

    let outgoingX: CGFloat =
      coverSwipeDirection < 0
      ? -(leftEdgeTravel * eased)
      : rightEdgeTravel * eased

    let incomingX: CGFloat =
      coverSwipeDirection < 0
      ? rightEdgeTravel * (1 - eased)
      : -(leftEdgeTravel * (1 - eased))

    let currentScale = 1 - (0.28 * eased)
    let currentOpacity = 1 - (0.72 * eased)
    let incomingScale = 0.72 + (0.28 * eased)
    let incomingOpacity = 0.18 + (0.82 * eased)

    return ZStack {
      if let coverSwipeTrack, coverSwipeDirection != 0 {
        artworkPage(
          track: coverSwipeTrack,
          size: size,
          cornerRadius: cornerRadius,
          showSubtitle: false,
          progress: progress,
          subtitleLeftSpace: subtitleLeftSpace,
          subtitleRightSpace: subtitleRightSpace,
          interactionDistance: interactionDistance, expansionTravel: expansionTravel
        )
        .offset(x: incomingX)
        .scaleEffect(incomingScale)
        .opacity(Double(incomingOpacity))
      }

      artworkPage(
        track: track,
        size: size,
        cornerRadius: cornerRadius,
        showSubtitle: true,
        progress: progress,
        subtitleLeftSpace: subtitleLeftSpace,
        subtitleRightSpace: subtitleRightSpace,
        interactionDistance: interactionDistance, expansionTravel: expansionTravel
      )
      .offset(x: coverSwipeDirection == 0 ? 0 : outgoingX)
      .scaleEffect(coverSwipeDirection == 0 ? 1 : currentScale)
      .opacity(Double(coverSwipeDirection == 0 ? 1 : currentOpacity))
    }
    .frame(width: size, height: size)
    .onPreferenceChange(PlayerSubtitleRailAvailabilityKey.self) {
      subtitleContentTrackIDs = $0
    }
    .shadow(
      color: .black.opacity(Double(0.34 * smoothStep(progress))),
      radius: 28 * smoothStep(progress),
      y: 16 * smoothStep(progress)
    )
    .allowsHitTesting((progress > 0.74 || artworkGestureActive) && !coverPaging)

  }

  private func artworkDragGesture(
    size: CGFloat,
    interactionDistance: CGFloat,
    expansionTravel: CGFloat
  ) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .named("playerContainer"))
      .onChanged { value in
        guard expansion > 0.74 || artworkGestureActive, !coverPaging else { return }

        artworkGestureActive = true

        let horizontal = value.translation.width
        let vertical = value.translation.height

        if artworkGestureAxis == .undetermined {
          let dominant = max(abs(horizontal), abs(vertical))
          guard dominant >= 7 else { return }

          if abs(horizontal) > abs(vertical) * 1.12 {
            artworkGestureAxis = .horizontal
            coverSwipeDirection = horizontal < 0 ? -1 : 1
            coverSwipeTrack = swipeNeighbor(direction: coverSwipeDirection)
          } else if abs(vertical) > abs(horizontal) * 1.12 {
            artworkGestureAxis = .vertical
            artworkVerticalStartExpansion = expansion
            coverDragX = 0
            coverSwipeTrack = nil
            coverSwipeDirection = 0
          } else {
            return
          }
        }

        switch artworkGestureAxis {
        case .horizontal:
          let lockedTranslation: CGFloat =
            coverSwipeDirection < 0
            ? min(0, horizontal)
            : max(0, horizontal)

          if coverSwipeTrack != nil {
            coverDragX = min(
              interactionDistance,
              max(-interactionDistance, lockedTranslation)
            )
          } else {
            coverDragX = rubberBand(
              lockedTranslation,
              limit: size * 0.10
            )
          }

        case .vertical:
          let start = artworkVerticalStartExpansion ?? expansion
          let next = start - (vertical / max(1, expansionTravel))
          expansion = clamp(next)

        case .undetermined:
          break
        }
      }
      .onEnded { value in
        defer {
          artworkGestureActive = false
          artworkGestureAxis = .undetermined
          artworkVerticalStartExpansion = nil
        }

        switch artworkGestureAxis {
        case .horizontal:
          finishArtworkPaging(
            value: value,
            interactionDistance: interactionDistance
          )

        case .vertical:
          finishArtworkVerticalDrag(
            value: value,
            expansionTravel: expansionTravel
          )

        case .undetermined:
          resetCoverPaging()
        }
      }
  }

  private func finishArtworkPaging(
    value: DragGesture.Value,
    interactionDistance: CGFloat
  ) {
    let horizontal = value.translation.width
    let projected = value.predictedEndTranslation.width
    let threshold = interactionDistance * 0.34

    let directionMatches =
      coverSwipeDirection < 0
      ? horizontal <= 0
      : horizontal >= 0

    let projectedMatches =
      coverSwipeDirection < 0
      ? projected <= 0
      : projected >= 0

    let shouldPage =
      directionMatches
      && (
        abs(horizontal) >= threshold
        || (projectedMatches && abs(projected) >= threshold * 1.45)
      )

    guard shouldPage, let destination = coverSwipeTrack else {
      resetCoverPaging()
      return
    }

    coverPaging = true
    let target: CGFloat =
      coverSwipeDirection < 0
      ? -interactionDistance
      : interactionDistance

    let startingTrackID = track.id
    withAnimation(
      .spring(response: 0.36, dampingFraction: 0.93, blendDuration: 0.10),
      completionCriteria: .removed
    ) {
      coverDragX = target
    } completion: {
      if player.currentTrack?.id == startingTrackID, expansion > 0.74 {
        player.play(destination)
      }

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

  private func finishArtworkVerticalDrag(
    value: DragGesture.Value,
    expansionTravel: CGFloat
  ) {
    let projectedDelta =
      (value.predictedEndTranslation.height - value.translation.height)
      / max(1, expansionTravel)

    let projected = clamp(expansion - (projectedDelta * 0.34))
    let target: CGFloat = projected >= 0.52 ? 1 : 0

    withAnimation(
      .spring(response: 0.52, dampingFraction: 0.96, blendDuration: 0.16)
    ) {
      expansion = target
    }
  }

  private func artworkPage(
    track pageTrack: Track,
    size: CGFloat,
    cornerRadius: CGFloat,
    showSubtitle: Bool,
    progress: CGFloat,
    subtitleLeftSpace: CGFloat,
    subtitleRightSpace: CGFloat,
    interactionDistance: CGFloat,
    expansionTravel: CGFloat
  ) -> some View {
    let subtitleLayoutActive =
      showSubtitle && subtitlesVisible && progress > 0.74
      && subtitleContentTrackIDs.contains(pageTrack.id)
    let subtitleLayout = PlayerSubtitleLayout(
      size: size, leftSpace: subtitleLeftSpace, rightSpace: subtitleRightSpace,
      active: subtitleLayoutActive
    )
    let railHeight = min(220, max(120, size * 0.78))
    let showRail =
      showSubtitle && progress > 0.74 && !coverPaging && abs(coverDragX) < 6

    return ZStack {
      ArtworkView(
        url: pageTrack.artworkURL,
        cornerRadius: cornerRadius,
        placeholderSystemImage: "music.note",
        contentMode: .fill
      )
      .frame(width: size, height: size)
      .highPriorityGesture(
        artworkDragGesture(size: size, interactionDistance: interactionDistance,
                           expansionTravel: expansionTravel),
        including: showSubtitle ? .all : .none
      )
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(pageTrack.id == track.id ? "player-artwork-frame" : "incoming-artwork-frame")
      .accessibilityHidden(pageTrack.id != track.id)
      .scaleEffect(subtitleLayout.coverScale)
      .offset(x: subtitleLayout.coverShift)

      // Keep the presenter mounted while paging so its task/cache survives.
      // Only the current cover owns captions; incoming covers never show stale text.
      if showSubtitle, subtitlesVisible, progress > 0.74 {
        AISubtitleExperience(
          timeline: player.timeline, track: pageTrack, isVisible: $subtitlesVisible,
          compactWidth: subtitleLayout.railWidth, compactHeight: railHeight
        )
        .id("\(pageTrack.id)-r\(pageTrack.captionsRevision ?? 0)")
        .frame(width: subtitleLayout.railWidth, height: railHeight)
        .offset(x: subtitleLayout.railOffset)
        .opacity(showRail ? 1 : 0)
        .allowsHitTesting(showRail)
        .accessibilityHidden(!showRail)
      }
    }
    .frame(width: size, height: size)
    .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.94), value: subtitleLayoutActive)
  }

  private func swipeNeighbor(direction: Int) -> Track? {
    let queue = library.queueTracks
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
    coverPaging = true
    withAnimation(
      .spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.08),
      completionCriteria: .removed
    ) {
      coverDragX = 0
    } completion: {
      coverSwipeTrack = nil
      coverSwipeDirection = 0
      coverPaging = false
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

    return PlaybackProgressLine(timeline: player.timeline)
      .frame(width: lineWidth, height: 2)
      .position(x: viewportWidth / 2, y: y)
      .opacity(Double(opacity))
      .allowsHitTesting(false)
  }

  private func fullControls(
    layout: AdaptiveLayout,
    playerHeight: CGFloat,
    centerY: CGFloat,
    contentWidth: CGFloat,
    metadataY: CGFloat,
    opacity: CGFloat,
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

      VStack(spacing: 6) {
        smallActions
        if player.playbackError != nil {
          Button("Не удалось воспроизвести · Повторить") { player.retryPlayback() }
            .font(.caption2).foregroundStyle(.orange)
        }
        if let progress = downloads.progress[track.id] {
          ProgressView(value: progress).frame(width: 170)
        }
      }.position(x: localCenterX, y: actionsY)
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
          toggleSubtitles()
        } label: {
          Label(subtitlesVisible ? "Скрыть субтитры" : "Показать субтитры", systemImage: subtitleSymbol)
        }
        Divider()
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
          Label(track.id == player.currentTrack?.id ? "Этот нашид уже играет" : "Воспроизвести следующим", systemImage: "text.insert")
        }
        .disabled(track.id == player.currentTrack?.id)

        Button {
          library.ensureQueueContains(track)
        } label: {
          Label(library.queueTracks.contains(where: { $0.id == track.id }) ? "Уже в очереди" : "Добавить в очередь", systemImage: "text.badge.plus")
        }
        .disabled(library.queueTracks.contains(where: { $0.id == track.id }))

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
          TimelineView(.periodic(from: .now, by: 60)) { _ in
            Label(
              player.sleepTimerSummary.map { "Таймер сна · \($0)" } ?? "Таймер сна",
              systemImage: "moon.zzz"
            )
          }
        }

        Divider()

        Button {
          handleDownload()
        } label: {
          Label(
            downloads.isDownloaded(track) ? "Сохранено офлайн" : (downloads.downloadingIDs.contains(track.id) ? "Скачиваем…" : "Скачать офлайн"),
            systemImage: downloads.isDownloaded(track)
              ? "checkmark.circle"
              : "arrow.down.circle"
          )
        }
        .disabled(downloads.isDownloaded(track) || downloads.downloadingIDs.contains(track.id))
        if downloads.downloadingIDs.contains(track.id) {
          Button("Отменить скачивание", role: .destructive) { downloads.cancel(track) }
        }
        if downloads.isDownloaded(track) {
          Button(role: .destructive) {
            do { try downloads.remove(track) } catch { downloadError = DownloadManager.message(for: error) }
          } label: {
            Label("Удалить загрузку", systemImage: "trash")
          }
        }
        if player.playbackError != nil {
          Button("Повторить воспроизведение") { player.retryPlayback() }
        }
        ShareLink(item: track.audioURL) { Label("Поделиться нашидом", systemImage: "square.and.arrow.up") }
      } label: {
        Image(systemName: "ellipsis")
          .rotationEffect(.degrees(90))
          .font(.system(size: 19, weight: .semibold))
          .frame(width: 42, height: 42)
          .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Меню плеера")
      .accessibilityIdentifier("player-menu")
    }
    .frame(width: width)
  }

  private func fullProgress(width: CGFloat) -> some View {
    PlaybackScrubber(timeline: player.timeline, seek: player.seek)
      .frame(width: width)
  }

  private func transport(compact: Bool) -> some View {
    let mainSize: CGFloat = compact ? 58 : 68
    let sideSize: CGFloat = compact ? 46 : 54
    let spacing: CGFloat = compact ? 10 : 22

    return HStack(spacing: spacing) {
      Button {
        player.shuffleOn.toggle()
      } label: {
        Image(systemName: "shuffle")
          .foregroundStyle(player.shuffleOn ? .white : .white.opacity(0.55))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Перемешать")
      .accessibilityValue(player.shuffleOn ? "Включено" : "Выключено")
      .accessibilityIdentifier("player-shuffle")

      Button(action: player.previous) {
        Image(systemName: "backward.fill")
          .font(.title2)
          .frame(width: sideSize, height: sideSize)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Предыдущий нашид")
      .accessibilityIdentifier("player-previous")

      Button(action: player.toggle) {
        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: compact ? 24 : 28, weight: .bold))
          .foregroundStyle(.black)
          .frame(width: mainSize, height: mainSize)
          .background(.white, in: Circle())
          .overlay { if player.isBuffering { PlaybackLoadingRing().padding(-5) } }
      }
      .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
      .accessibilityIdentifier("player-toggle")
      .accessibilityValue(player.isBuffering ? "Загрузка аудио" : player.isPlaying ? "Воспроизводится" : "На паузе")

      Button(action: player.next) {
        Image(systemName: "forward.fill")
          .font(.title2)
          .frame(width: sideSize, height: sideSize)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Следующий нашид")
      .accessibilityIdentifier("player-next")

      Button {
        player.cycleRepeatMode()
      } label: {
        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
          .foregroundStyle(player.repeatOn ? .white : .white.opacity(0.55))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Повтор")
      .accessibilityValue(player.repeatMode == .one ? "Один нашид" : player.repeatOn ? "Вся очередь" : "Выключено")
      .accessibilityIdentifier("player-repeat")
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  private var smallActions: some View {
    HStack(spacing: 14) {
      Button {
        toggleSubtitles()
      } label: {
        ZStack(alignment: .topTrailing) {
          Image(systemName: subtitleSymbol)
          .frame(width: 44, height: 44)
          .background(
            .white.opacity(subtitlesVisible ? 0.14 : 0.055),
            in: RoundedRectangle(cornerRadius: 16)
          )


        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(subtitlesVisible ? "Скрыть субтитры" : "Показать субтитры")
      .accessibilityIdentifier("player-subtitles")

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
      .accessibilityLabel("Открыть очередь")
      .accessibilityIdentifier("player-queue")

      if FeatureAccess.allowsPremiumFeature(isPremium: premium.isPremium) {
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
        guard !artworkGestureActive else {
          dragStartExpansion = nil
          return
        }

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

        guard !artworkGestureActive else { return }
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

  private var subtitleSymbol: String { subtitlesVisible ? "captions.bubble.fill" : "captions.bubble" }

  private func toggleSubtitles() {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { subtitlesVisible.toggle() }
  }

  private func handleDownload() {
    guard !downloads.isDownloaded(track), !downloads.downloadingIDs.contains(track.id) else { return }

    guard FeatureAccess.allowsPremiumFeature(isPremium: premium.isPremium) else {
      premiumPresented = true
      return
    }

    Task {
      do {
        try await downloads.download(track)
      } catch {
        guard !(error is CancellationError), (error as NSError).code != NSURLErrorCancelled else { return }
        downloadError = DownloadManager.message(for: error)
      }
    }
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

  init(width: CGFloat, height: CGFloat, safeTop: CGFloat, chromeBottomPadding: CGFloat,
       phone: Bool, contentWidth: CGFloat, artworkLimit: CGFloat) {
    chromeTop = height + safeTop - BottomChromeLayout.barHeight - chromeBottomPadding
    let landscape = width > height * 1.2 && height < 520
    let short = phone && height < 740
    if landscape {
      controlsWidth = min(420, contentWidth * 0.56)
      controlsX = (width + contentWidth) / 2 - controlsWidth / 2
      artworkSize = min(artworkLimit, contentWidth - controlsWidth - 24, chromeTop - safeTop - 76)
      artworkX = (width - contentWidth) / 2 + (contentWidth - controlsWidth - 16) / 2
      artworkY = safeTop + 56 + artworkSize / 2
      // Keep the title below the top controls on short landscape phones after
      // restoring the bottom safe area. Gaps still include full touch targets.
      actionsY = chromeTop - 32
      transportY = actionsY - (phone ? 56 : 64)
      progressY = transportY - (phone ? 62 : 68)
      metadataY = progressY - 54
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

// One reviewed anchor for navigation and the mini/full-player morph. The root
// is already inside SwiftUI's safe area: never add its bottom inset a second time.
struct BottomChromeLayout {
  static let barHeight: CGFloat = 62
  static let playerGap: CGFloat = 8
  // Owner-approved Build 50: iPhone 17 Pro, 874 pt viewport, 18 pt clearance.
  // Scale the outer gap only; touch targets and typography do not scale.
  static let referenceHeight: CGFloat = 874
  static let referenceClearance: CGFloat = 18
  static let minimumClearance: CGFloat = 12
  static let maximumClearance: CGFloat = 28
  static let maximumSafeAreaUnderlap: CGFloat = 16
  let physicalBottomClearance: CGFloat
  let bottomPadding: CGFloat
  init(viewportHeight: CGFloat, safeBottom: CGFloat, rootBottomInset: CGFloat? = nil) {
    let height = viewportHeight.isFinite && viewportHeight > 0 ? viewportHeight : Self.referenceHeight
    let inset = safeBottom.isFinite ? max(0, safeBottom) : 0
    let proportional = min(Self.maximumClearance, max(Self.minimumClearance,
      height * Self.referenceClearance / Self.referenceHeight))
    physicalBottomClearance = max(proportional, inset - Self.maximumSafeAreaUnderlap)
    // Root coordinates end at the safe area; translate this one physical anchor
    // once. Navigation, mini player and full-player morph must share the result.
    let rootInset = rootBottomInset.flatMap { $0.isFinite ? max(0, $0) : nil } ?? inset
    bottomPadding = physicalBottomClearance - rootInset
  }
}

// Fit the transparent caption rail beside the reduced cover, inside the safe
// artwork column. The right boundary excludes transport controls in landscape.
struct PlayerSubtitleLayout {
  let coverScale: CGFloat
  let coverShift: CGFloat
  let railWidth: CGFloat
  let railOffset: CGFloat

  init(size: CGFloat, leftSpace: CGFloat, rightSpace: CGFloat, active: Bool) {
    let availableWidth = max(0, leftSpace + rightSpace)
    railWidth = min(164, max(104, size * 0.43), availableWidth * 0.44)
    let gap = min(10, availableWidth * 0.04)
    let coverWidth = min(size * 0.82, max(0, availableWidth - gap - railWidth))
    if active {
      coverScale = coverWidth / max(size, 1)
      let leftBound = -leftSpace + coverWidth / 2
      let rightBound = rightSpace - railWidth - gap - coverWidth / 2
      coverShift = min(max(-size * 0.18, leftBound), rightBound)
      railOffset = coverShift + coverWidth / 2 + gap + railWidth / 2
    } else {
      coverScale = 1
      coverShift = 0
      railOffset = min(size * 0.30, max(0, rightSpace - railWidth / 2))
    }
  }
}


private struct PlaybackScrubber: View {
  @ObservedObject var timeline: PlaybackTimeline
  let seek: (Double) -> Void
  @State private var scrubbing = false
  @State private var draft: Double = 0

  var body: some View {
    VStack(spacing: 8) {
      Slider(value: Binding(
        get: { scrubbing ? draft : timeline.snapshot.progress },
        set: { draft = $0; if !scrubbing { seek($0) } }
      ), in: 0...1, onEditingChanged: { editing in
        if editing { draft = timeline.snapshot.progress }
        scrubbing = editing
        if !editing { seek(draft) }
      })
      .tint(.white)
      .accessibilityLabel("Позиция воспроизведения")
      HStack {
        Text(time(scrubbing ? draft * timeline.snapshot.duration : timeline.snapshot.time))
        Spacer()
        Text(time(timeline.snapshot.duration))
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }
  private func time(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
  }
}
