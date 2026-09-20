import SwiftUI

struct MiniPlayerView: View {
  @EnvironmentObject private var player: PlayerManager
  let openPlayer: () -> Void

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      HStack(spacing: 10) {
        ArtworkView(
          url: player.currentTrack?.artworkURL, cornerRadius: 13, placeholderSystemImage: "waveform"
        )
        .frame(width: 42, height: 42)

        Button(action: openPlayer) {
          VStack(alignment: .leading, spacing: 2) {
            Text(player.currentTrack?.title ?? "")
              .font(.system(size: 13, weight: .semibold))
              .lineLimit(1)
            Text(player.currentTrack?.artist ?? "")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Button(action: player.toggle) {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 15, weight: .bold))
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.055), in: Circle())
        }
        .buttonStyle(.plain)

        Button(action: player.next) {
          Image(systemName: "forward.fill")
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.085), in: Circle())
        }
        .buttonStyle(.plain)
      }
      .padding(7)

      GeometryReader { proxy in
        Capsule()
          .fill(.white.opacity(0.72))
          .frame(width: proxy.size.width * max(0, min(1, player.progress)), height: 2)
      }
      .frame(height: 2)
      .padding(.horizontal, 16)
      .padding(.bottom, 1)
      .frame(maxHeight: .infinity, alignment: .bottom)
      .allowsHitTesting(false)
    }
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 27, style: .continuous)
        .stroke(.white.opacity(0.14), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
  }
}
