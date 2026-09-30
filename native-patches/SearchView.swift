import SwiftUI

struct SearchView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore
  @State private var query = ""
  @State private var selectedFilter = "Все"

  let openPlayer: () -> Void

  private let filters = ["Все", "Нашиды", "Арабские", "Недавние"]

  private var results: [Track] {
    let base: [Track]
    switch selectedFilter {
    case "Недавние":
      base = library.historyTracks
    case "Арабские":
      base = Track.catalog.filter {
        $0.title.range(of: "[\\u{0600}-\\u{06FF}]", options: .regularExpression) != nil
      }
    default:
      base = Track.catalog
    }
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return base }
    return base.filter {
      $0.title.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
        || $0.artist.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      ZStack {
        AppBackground().ignoresSafeArea()
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 18) {
            HStack {
              Text("Поиск")
                .font(.system(size: 32, weight: .bold, design: .rounded))
              Spacer()
              Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                  .font(.system(size: 17, weight: .semibold))
                  .frame(width: 42, height: 42)
                  .glassPanel(cornerRadius: 16)
              }
              .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
              Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
              TextField("Название или автор", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
              if !query.isEmpty {
                Button(action: { query = "" }) {
                  Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(
              .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 19, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                  Button(filter) { selectedFilter = filter }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(
                      selectedFilter == filter ? .white.opacity(0.14) : .white.opacity(0.05),
                      in: Capsule()
                    )
                }
              }
            }

            if results.isEmpty {
              EmptyStateView(
                icon: "magnifyingglass",
                title: "Ничего не найдено",
                message: "Попробуйте другое название или имя автора."
              )
            } else {
              LazyVGrid(
                columns: Array(
                  repeating: GridItem(.flexible(), spacing: 20), count: layout.listColumns),
                spacing: 0
              ) {
                ForEach(results) { track in
                  TrackRow(
                    track: track,
                    isPlaying: player.currentTrack?.id == track.id && player.isPlaying,
                    trailingSystemImage: "play.circle",
                    action: { player.play(track) },
                    trailingAction: {
                      player.play(track)
                      openPlayer()
                    }
                  )
                  .overlay(alignment: .bottom) {
                    Divider().overlay(.white.opacity(0.05))
                  }
                }
              }
            }
          }
          .padding(.horizontal, layout.horizontalPadding)
          .padding(.top, layout.isCompactLandscapePhone ? 10 : 16)
          .padding(.bottom, 36)
          .adaptiveFrame(maxWidth: min(layout.contentMaxWidth, 980))
        }
      }
    }
  }
}
