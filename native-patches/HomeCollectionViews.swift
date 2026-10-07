import SwiftUI

struct HomeCollections: View {
  let tracks: [Track]
  let contentWidth: CGFloat
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Text("В вашем ритме").font(MuwaTypography.section)
        Spacer(minLength: 8)
        NavigationLink {
          CollectionTrackList(title: "Вся коллекция", tracks: tracks)
        } label: {
          HStack(spacing: 4) {
            Text("Все")
            Image(systemName: "arrow.up.right")
          }
          .font(MuwaTypography.caption.weight(.semibold))
          .foregroundStyle(MuwaPalette.ice)
          .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(MuwaPressStyle())
        .accessibilityLabel("Вся коллекция")
      }

      // Card titles have wide ideal sizes. ViewThatFits measures those before
      // wrapping and would choose a tall column even on a regular iPhone.
      if typeSize.isAccessibilitySize || contentWidth < 300 {
        VStack(spacing: 12) { cards }
      } else {
        HStack(alignment: .top, spacing: 12) { cards }
      }
    }
  }

  @ViewBuilder private var cards: some View {
    collection(title: "На несколько минут", detail: "До 3 минут", symbol: "clock",
               tint: MuwaPalette.blue, tracks: tracks.filter { $0.duration <= 180 })
    collection(title: "Слушать подольше", detail: "Больше 3 минут", symbol: "headphones",
               tint: MuwaPalette.teal, tracks: tracks.filter { $0.duration > 180 })
  }

  @ViewBuilder
  private func collection(title: String, detail: String, symbol: String, tint: Color, tracks: [Track]) -> some View {
    if !tracks.isEmpty {
      NavigationLink {
        CollectionTrackList(title: title, tracks: tracks)
      } label: {
        HomeCollectionCard(title: title, detail: detail, symbol: symbol, tint: tint, tracks: tracks)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(MuwaPressStyle())
      .accessibilityLabel("\(title), \(detail), \(MuwaText.trackCount(tracks.count))")
    }
  }
}

private struct HomeCollectionCard: View {
  let title: String
  let detail: String
  let symbol: String
  let tint: Color
  let tracks: [Track]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        Image(systemName: symbol)
          .font(.system(.body, design: .rounded).weight(.medium))
          .foregroundStyle(MuwaPalette.ice)
          .padding(10)
          .background(.white.opacity(0.08), in: Circle())
        Spacer(minLength: 0)
        ZStack {
          if let second = tracks.dropFirst().first {
            ArtworkView(url: second.artworkURL, cornerRadius: 13)
              .frame(width: 56, height: 56)
              .rotationEffect(.degrees(12))
              .offset(x: 7, y: 6)
              .opacity(0.55)
          }
          if let first = tracks.first {
            ArtworkView(url: first.artworkURL, cornerRadius: 13)
              .frame(width: 56, height: 56)
              .rotationEffect(.degrees(-8))
          }
        }
        .frame(width: 62, height: 66)
        .accessibilityHidden(true)
      }
      Text(title)
        .font(MuwaTypography.title)
        .foregroundStyle(MuwaPalette.text)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 60, alignment: .topLeading)
      HStack(alignment: .bottom, spacing: 4) {
        VStack(alignment: .leading, spacing: 3) {
          Text(detail).font(MuwaTypography.caption)
          Text(MuwaText.trackCount(tracks.count)).font(MuwaTypography.label)
        }
        .foregroundStyle(MuwaPalette.secondary)
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right")
          .font(MuwaTypography.caption.weight(.semibold))
          .foregroundStyle(MuwaPalette.ice.opacity(0.85))
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: MuwaRadius.card, style: .continuous)
        .fill(LinearGradient(colors: [tint.opacity(0.18), MuwaPalette.surface.opacity(0.85)],
                             startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    .overlay {
      RoundedRectangle(cornerRadius: MuwaRadius.card, style: .continuous)
        .strokeBorder(LinearGradient(colors: [.white.opacity(0.19), .white.opacity(0.025)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
    }
    .contentShape(RoundedRectangle(cornerRadius: MuwaRadius.card))
  }
}

private struct CollectionTrackList: View {
  let title: String
  let tracks: [Track]
  @EnvironmentObject private var player: PlayerManager
  @EnvironmentObject private var library: LibraryStore

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(tracks) { track in
          TrackRow(track: track, isPlaying: player.currentTrack?.id == track.id && player.isPlaying,
                   action: { player.play(track, in: tracks) },
                   playNextAction: { library.addNext(track, after: player.currentTrack) },
                   addToQueueAction: { library.ensureQueueContains(track) })
        }
      }
      .padding(.horizontal, MuwaSpacing.screen)
      .padding(.top, 12)
      .padding(.bottom, 170)
    }
    .background(AppBackground().ignoresSafeArea())
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
  }
}
