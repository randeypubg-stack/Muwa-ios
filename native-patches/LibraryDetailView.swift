import SwiftUI

struct LibraryDetailView: View {
  let destination: LibraryDestination
  let startPublication: () -> Void

  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var premium: PremiumManager

  @State private var premiumPresented = false
  @State private var createPlaylistPresented = false
  @State private var removeError: String?

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 18) {
          heading
          content(layout: layout)
        }
        .padding(.horizontal, max(20, layout.horizontalPadding))
        .padding(.top, 10)
        .padding(.bottom, player.hasStartedPlaybackThisSession ? 170 : 90)
        .adaptiveFrame(maxWidth: min(layout.contentMaxWidth, 980))
      }
      .background(AppBackground().ignoresSafeArea())
    }
    .libraryNavigation(title: title)
    .toolbar {
      if destination == .playlist && !library.playlists.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button { createPlaylistPresented = true } label: { Image(systemName: "plus") }
            .accessibilityLabel("Создать плейлист")
        }
      }
    }
    .sheet(isPresented: $premiumPresented) {
      PremiumView()
    }
    .sheet(isPresented: $createPlaylistPresented) {
      PlaylistCreateSheet { name in
        _ = library.createPlaylist(name: name)
      }
    }
    .alert(
      "Не удалось выполнить действие",
      isPresented: Binding(
        get: { removeError != nil },
        set: { if !$0 { removeError = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(removeError ?? "Неизвестная ошибка")
    }
  }

  @ViewBuilder
  private func content(layout: AdaptiveLayout) -> some View {
    switch destination {
    case .favorites:
      trackCollection(
        library.favoriteTracks,
        layout: layout,
        emptyIcon: "heart",
        emptyTitle: "Избранное пусто",
        emptyMessage: "Добавляйте нашиды в избранное из меню большого плеера."
      )

    case .history:
      trackCollection(
        library.historyTracks,
        layout: layout,
        emptyIcon: "clock",
        emptyTitle: "История пока пустая",
        emptyMessage: "Прослушанные нашиды будут появляться здесь автоматически."
      )

    case .playlist:
      playlistsContent(layout: layout)

    case .publications:
      publicationList(
        library.publications,
        emptyTitle: "Публикаций пока нет",
        draftsOnly: false
      )

    case .drafts:
      publicationList(
        library.drafts,
        emptyTitle: "Черновиков нет",
        draftsOnly: true
      )

    case .downloads:
      downloadsList(layout: layout)
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(MuwaTypography.display)

      Text(subtitle)
        .font(MuwaTypography.detail)
        .foregroundStyle(MuwaPalette.secondary)
    }
  }

  private var title: String {
    switch destination {
    case .favorites: return "Избранные"
    case .history: return "Недавно прослушано"
    case .playlist: return "Плейлисты"
    case .publications: return "Мои публикации"
    case .drafts: return "Черновики публикаций"
    case .downloads: return "Загрузки"
    }
  }

  private var subtitle: String {
    switch destination {
    case .favorites: return "Сохранённые любимые нашиды"
    case .history: return "Последние прослушивания"
    case .playlist: return "Ваши нашиды, собранные по настроению"
    case .publications: return "Статусы отправленных публикаций"
    case .drafts: return "Незавершённые публикации"
    case .downloads: return "Нашиды, сохранённые для офлайн-прослушивания"
    }
  }

  @ViewBuilder
  private func playlistsContent(layout: AdaptiveLayout) -> some View {
    if library.playlists.isEmpty {
      EmptyStateView(
        icon: "rectangle.stack.fill",
        title: "Соберите свою подборку",
        message: "Для дороги, спокойного вечера или любимых нашидов — всё в одном плейлисте.",
        actionTitle: "Создать плейлист",
        action: { createPlaylistPresented = true }
      )
      .padding(.top, 18)
    } else {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: layout.listColumns), spacing: 14) {
        ForEach(library.playlists) { playlist in playlistCard(playlist) }
      }
    }
  }

  private func playlistCard(_ playlist: UserPlaylist) -> some View {
    let tracks = library.tracks(in: playlist.id)
    return HStack(spacing: 4) {
      NavigationLink {
        PlaylistDetailView(playlistID: playlist.id)
      } label: {
        HStack(spacing: 16) {
          PlaylistArtwork(tracks: tracks).frame(width: 72, height: 72)
          VStack(alignment: .leading, spacing: 6) {
            Text(playlist.name).font(MuwaTypography.title).foregroundStyle(MuwaPalette.text).lineLimit(2)
            Text(PlaylistSummary.text(for: tracks)).font(MuwaTypography.caption).foregroundStyle(MuwaPalette.secondary)
          }
          Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(MuwaPressStyle(scale: 0.99))
      Menu {
        if let first = tracks.first {
          Button {
            library.replaceQueue(with: tracks)
            player.play(first)
          } label: { Label("Воспроизвести", systemImage: "play.fill") }
          Button {
            for track in tracks { library.ensureQueueContains(track) }
          } label: { Label("Добавить в очередь", systemImage: "text.badge.plus") }
          Divider()
        }
        Button(role: .destructive) { library.deletePlaylist(playlist.id) }
          label: { Label("Удалить плейлист", systemImage: "trash") }
      } label: {
        Image(systemName: "ellipsis").rotationEffect(.degrees(90))
          .font(.system(.body).weight(.semibold)).foregroundStyle(MuwaPalette.secondary)
          .frame(width: 44, height: 52).contentShape(Rectangle())
      }
      .accessibilityLabel("Действия с плейлистом \(playlist.name)")
    }
    .padding(14)
    .nativeCard(cornerRadius: MuwaRadius.card)
    .overlay(RoundedRectangle(cornerRadius: MuwaRadius.card).strokeBorder(.white.opacity(0.08), lineWidth: 0.75))
  }

  @ViewBuilder
  private func trackCollection(
    _ tracks: [Track],
    layout: AdaptiveLayout,
    emptyIcon: String,
    emptyTitle: String,
    emptyMessage: String
  ) -> some View {
    if tracks.isEmpty {
      EmptyStateView(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage
      )
    } else {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: 20),
          count: layout.listColumns
        ),
        spacing: 0
      ) {
        ForEach(tracks) { track in
          TrackRow(
            track: track,
            isPlaying: player.currentTrack?.id == track.id && player.isPlaying,
            trailingSystemImage: "play.circle",
            action: { player.play(track) },
            trailingAction: { player.play(track) }
          )
          .overlay(alignment: .bottom) {
            Divider().overlay(.white.opacity(0.05))
          }
        }
      }
    }
  }

  @ViewBuilder
  private func publicationList(
    _ items: [PublicationDraft],
    emptyTitle: String,
    draftsOnly: Bool
  ) -> some View {
    if items.isEmpty {
      EmptyStateView(
        icon: draftsOnly ? "doc.text" : "square.and.arrow.up",
        title: emptyTitle,
        message: draftsOnly
          ? "Начните новую публикацию и сохраните её как черновик."
          : "Здесь будут появляться отправленные на модерацию нашиды.",
        actionTitle: "Начать публикацию",
        action: startPublication
      )
    } else {
      VStack(spacing: 0) {
        ForEach(items) { item in
          HStack(spacing: 12) {
            Image(systemName: item.status == .draft ? "doc.text" : "waveform")
              .frame(width: 42, height: 42)
              .background(
                .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14)
              )

            VStack(alignment: .leading, spacing: 4) {
              Text(item.title.isEmpty ? "Без названия" : item.title)
                .font(.subheadline.bold())
                .lineLimit(1)

              Text(item.artist.isEmpty ? item.audioName : item.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

              if let serverKey = item.submissionStorageKey {
                Text("Отправлено на сервер")
                  .font(.caption2)
                  .foregroundStyle(.green.opacity(0.82))
                  .accessibilityHint(serverKey)
              }
            }

            Spacer()

            Text(item.status.title)
              .font(.caption2.bold())
              .foregroundStyle(statusColor(item.status))
              .padding(.horizontal, 9)
              .padding(.vertical, 6)
              .background(
                statusColor(item.status).opacity(0.10),
                in: Capsule()
              )
          }
          .padding(.vertical, 11)

          Divider().overlay(.white.opacity(0.05))
        }
      }
    }
  }

  @ViewBuilder
  private func downloadsList(layout: AdaptiveLayout) -> some View {
    let items = library.tracks(for: Array(downloads.downloadedIDs)).filter(downloads.isDownloaded)

    if items.isEmpty {
      if FeatureAccess.allowsPremiumFeature(isPremium: premium.isPremium) {
        EmptyStateView(
          icon: "arrow.down.circle",
          title: "Загрузок пока нет",
          message: "Скачайте нашид из меню плеера, чтобы слушать без интернета."
        )
      } else {
        EmptyStateView(
          icon: "arrow.down.circle",
          title: "Загрузок пока нет",
          message: "Скачайте нашид из меню плеера, чтобы слушать без интернета.",
          actionTitle: "Открыть Premium",
          action: { premiumPresented = true }
        )
      }
    } else {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: 20),
          count: layout.listColumns
        ),
        spacing: 0
      ) {
        ForEach(items) { track in
          TrackRow(
            track: track,
            isPlaying: player.currentTrack?.id == track.id && player.isPlaying,
            trailingSystemImage: "trash",
            action: {
              if FeatureAccess.allowsPremiumFeature(isPremium: premium.isPremium) {
                player.play(track)
              } else {
                premiumPresented = true
              }
            },
            trailingAction: {
              do {
                try downloads.remove(track)
              } catch {
                removeError = error.localizedDescription
              }
            }
          )
          .overlay(alignment: .bottom) {
            Divider().overlay(.white.opacity(0.05))
          }
        }
      }
    }
  }

  private func statusColor(_ status: PublicationStatus) -> Color {
    switch status {
    case .draft: return .secondary
    case .moderation: return .yellow
    case .changes, .rejected: return .red
    case .approved: return .green
    }
  }
}

