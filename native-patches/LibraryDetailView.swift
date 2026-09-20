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
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 44)
        .adaptiveFrame(maxWidth: min(layout.contentMaxWidth, 980))
      }
      .background(Color.clear)
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
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
      playlistsContent

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
        .font(.system(size: 28, weight: .bold, design: .rounded))

      Text(subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var title: String {
    switch destination {
    case .favorites: return "Избранные"
    case .history: return "Недавно прослушано"
    case .playlist: return "Мои плей-листы"
    case .publications: return "Мои публикации"
    case .drafts: return "Черновики публикаций"
    case .downloads: return "Загрузки"
    }
  }

  private var subtitle: String {
    switch destination {
    case .favorites: return "Сохранённые любимые нашиды"
    case .history: return "Последние прослушивания"
    case .playlist: return "Создавайте отдельные подборки и добавляйте в них нашиды"
    case .publications: return "Статусы отправленных публикаций"
    case .drafts: return "Незавершённые публикации"
    case .downloads: return "Нашиды, сохранённые для офлайн-прослушивания"
    }
  }

  private var playlistsContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Button {
        createPlaylistPresented = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "plus")
          Text("Создать плей-лист")
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 14, weight: .bold))
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
          RoundedRectangle(cornerRadius: 18)
            .stroke(.white.opacity(0.10), lineWidth: 1)
        )
      }
      .buttonStyle(.plain)

      if library.playlists.isEmpty {
        EmptyStateView(
          icon: "music.note.list",
          title: "Плей-листов пока нет",
          message: "Создайте первый плей-лист, затем добавляйте в него нашиды из меню трека или большого плеера.",
          actionTitle: "Создать плей-лист",
          action: { createPlaylistPresented = true }
        )
      } else {
        VStack(spacing: 10) {
          ForEach(library.playlists) { playlist in
            playlistCard(playlist)
          }
        }
      }
    }
  }

  private func playlistCard(_ playlist: UserPlaylist) -> some View {
    HStack(spacing: 10) {
      NavigationLink {
        PlaylistDetailView(playlistID: playlist.id)
      } label: {
        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 14)
              .fill(.white.opacity(0.06))

            Image(systemName: "music.note.list")
              .font(.system(size: 18, weight: .semibold))
          }
          .frame(width: 46, height: 46)

          VStack(alignment: .leading, spacing: 4) {
            Text(playlist.name)
              .font(.subheadline.bold())
              .lineLimit(1)

            Text("\(playlist.trackIDs.count) нашид(ов)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)

      Menu {
        if let first = library.tracks(in: playlist.id).first {
          Button {
            player.play(first)
          } label: {
            Label("Воспроизвести", systemImage: "play.fill")
          }
        }

        Button {
          for track in library.tracks(in: playlist.id) {
            library.ensureQueueContains(track)
          }
        } label: {
          Label("Добавить в очередь", systemImage: "text.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
          library.deletePlaylist(playlist.id)
        } label: {
          Label("Удалить плей-лист", systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis")
          .rotationEffect(.degrees(90))
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 40, height: 46)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    .overlay(
      RoundedRectangle(cornerRadius: 20)
        .stroke(.white.opacity(0.08), lineWidth: 1)
    )
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
    let items = Track.catalog.filter(downloads.isDownloaded)

    if items.isEmpty {
      if premium.isPremium {
        EmptyStateView(
          icon: "arrow.down.circle",
          title: "Загрузок пока нет",
          message: "Сохранённые Premium-нашиды появятся здесь."
        )
      } else {
        EmptyStateView(
          icon: "arrow.down.circle",
          title: "Загрузок пока нет",
          message: "Сохранённые Premium-нашиды появятся здесь.",
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
              if premium.isPremium {
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

struct PlaylistDetailView: View {
  let playlistID: UUID

  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var premium: PremiumManager

  @State private var premiumPresented = false
  @State private var actionError: String?

  private var playlist: UserPlaylist? {
    library.playlist(id: playlistID)
  }

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(playlist?.name ?? "Плей-лист")
              .font(.system(size: 27, weight: .bold, design: .rounded))

            Text("\(playlist?.trackIDs.count ?? 0) нашид(ов)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let playlist, playlist.trackIDs.isEmpty {
            EmptyStateView(
              icon: "music.note.list",
              title: "Плей-лист пуст",
              message: "Добавляйте нашиды через вертикальное меню ⋮ или из большого плеера."
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
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 44)
        .adaptiveFrame(maxWidth: min(layout.contentMaxWidth, 920))
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
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
      .buttonStyle(.plain)
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
            guard premium.isPremium else {
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

struct PlaylistCreateSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  let onCreate: (String) -> Void

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 18) {
        HStack {
          Text("Новый плей-лист")
            .font(.title3.bold())

          Spacer()

          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .frame(width: 38, height: 38)
              .background(.white.opacity(0.07), in: Circle())
          }
          .buttonStyle(.plain)
        }

        TextField("Название", text: $name)
          .textInputAutocapitalization(.sentences)
          .padding(.horizontal, 14)
          .frame(height: 48)
          .background(
            .white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 15)
          )

        Button {
          let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          onCreate(trimmed)
          dismiss()
        } label: {
          Text("Создать")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.48 : 1)

        Spacer()
      }
      .padding(20)
    }
    .presentationDetents([.height(260)])
    .presentationDragIndicator(.hidden)
  }
}
