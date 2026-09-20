import SwiftUI

struct LibraryView: View {
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var auth: AuthManager
  @State private var path: [LibraryDestination] = []
  @State private var publicationPresented = false

  @Binding var requestedDestination: LibraryDestination?
  let openSearch: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      NavigationStack(path: $path) {
          VStack(spacing: 0) {
            ScreenHeader(
              title: "Библиотека",
              subtitle: "Сохранённое и ваши публикации",
              searchAction: openSearch
            )
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
              VStack(alignment: .leading, spacing: 18) {
                libraryHero

                Button {
                  startPublication()
                } label: {
                  Label("Добавить нашид", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                      .white,
                      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                LazyVGrid(
                  columns: Array(
                    repeating: GridItem(.flexible(), spacing: 10),
                    count: layout.libraryColumns
                  ),
                  spacing: 10
                ) {
                  libraryCard(
                    .favorites,
                    "Избранные",
                    "heart.fill",
                    library.likedIDs.count,
                    .pink
                  )
                  libraryCard(
                    .history,
                    "Недавно прослушано",
                    "clock.arrow.circlepath",
                    library.historyIDs.count,
                    .blue
                  )
                  libraryCard(
                    .playlist,
                    "Мои плей-листы",
                    "music.note.list",
                    library.playlists.count,
                    .cyan
                  )
                  libraryCard(
                    .publications,
                    "Мои публикации",
                    "square.and.arrow.up",
                    library.publications.count,
                    .mint
                  )
                }

                Text("Быстрый доступ")
                  .font(.headline)
                  .padding(.top, 4)

                if layout.isWide {
                  HStack(spacing: 12) {
                    quickAccess(
                      .drafts,
                      title: "Черновики публикаций",
                      subtitle: library.drafts.isEmpty
                        ? "Нет незавершённых публикаций"
                        : "\(library.drafts.count) черновик(а)",
                      icon: "doc.text"
                    )
                    quickAccess(
                      .downloads,
                      title: "Загрузки",
                      subtitle: downloads.downloadedIDs.isEmpty
                        ? "Офлайн-сохранения появятся здесь"
                        : "\(downloads.downloadedIDs.count) сохранено офлайн",
                      icon: "arrow.down.circle"
                    )
                  }
                } else {
                  quickAccess(
                    .drafts,
                    title: "Черновики публикаций",
                    subtitle: library.drafts.isEmpty
                      ? "Нет незавершённых публикаций"
                      : "\(library.drafts.count) черновик(а)",
                    icon: "doc.text"
                  )
                  quickAccess(
                    .downloads,
                    title: "Загрузки",
                    subtitle: downloads.downloadedIDs.isEmpty
                      ? "Офлайн-сохранения появятся здесь"
                      : "\(downloads.downloadedIDs.count) сохранено офлайн",
                    icon: "arrow.down.circle"
                  )
                }
              }
              .padding(.horizontal, layout.horizontalPadding)
              .padding(.top, layout.isCompactLandscapePhone ? 8 : 14)
              .padding(.bottom, layout.isCompactLandscapePhone ? 132 : 170)
              .adaptiveFrame(maxWidth: layout.contentMaxWidth)
            }
            .background(Color.clear)
          }
          .background(Color.clear)
          .navigationBarHidden(true)
          .toolbarBackground(.hidden, for: .navigationBar)
          .navigationDestination(for: LibraryDestination.self) { destination in
            LibraryDetailView(
              destination: destination,
              startPublication: startPublication
            )
          }
      }
      .background(Color.clear)
      .sheet(isPresented: $publicationPresented) {
        PublicationFlowView()
      }
      .onAppear { consumeRequestedDestination() }
      .onChange(of: requestedDestination) { _, _ in
        consumeRequestedDestination()
      }
    }
  }

  private func startPublication() {
    guard auth.isAuthenticated else {
      auth.showAuthentication()
      return
    }
    publicationPresented = true
  }

  private func consumeRequestedDestination() {
    guard let destination = requestedDestination else { return }
    if path.last != destination {
      path.append(destination)
    }
    requestedDestination = nil
  }

  private var libraryHero: some View {
    HStack(spacing: 14) {
      Image(systemName: "books.vertical.fill")
        .font(.title2)
        .frame(width: 54, height: 54)
        .background(
          .white.opacity(0.07),
          in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )

      VStack(alignment: .leading, spacing: 4) {
        Text("Ваша библиотека")
          .font(.title3.bold())

        Text("Всё сохранённое в одном месте")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "sparkles")
        .foregroundStyle(.white.opacity(0.28))
    }
    .padding(17)
    .glassPanel()
  }

  private func libraryCard(
    _ destination: LibraryDestination,
    _ title: String,
    _ icon: String,
    _ count: Int,
    _ tint: Color
  ) -> some View {
    Button {
      path.append(destination)
    } label: {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Image(systemName: icon)
            .foregroundStyle(tint)

          Spacer()

          Text("\(count)")
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(.white.opacity(0.06), in: Capsule())
        }

        Spacer(minLength: 0)

        Text(title)
          .font(.system(size: 13, weight: .bold))
          .multilineTextAlignment(.leading)

        Text("Открыть раздел")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
      .padding(15)
      .background(
        RadialGradient(
          colors: [tint.opacity(0.18), .clear],
          center: .bottomTrailing,
          startRadius: 0,
          endRadius: 120
        )
      )
    }
    .buttonStyle(.plain)
    .glassPanel(cornerRadius: 23)
  }

  private func quickAccess(
    _ destination: LibraryDestination,
    title: String,
    subtitle: String,
    icon: String
  ) -> some View {
    NavigationLink(value: destination) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.title3)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.subheadline.bold())

          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
      .padding(15)
      .frame(maxWidth: .infinity, minHeight: 62)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .glassPanel(cornerRadius: 20)
  }
}

enum LibraryDestination: String, Hashable {
  case favorites, history, playlist, publications, drafts, downloads
}
