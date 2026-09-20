import SwiftUI

struct MiniPlayerView: View {
  @EnvironmentObject private var player: PlayerManager

  let openPlayer: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Button(action: openPlayer) {
          HStack(spacing: 10) {
            ArtworkView(
              url: player.currentTrack?.artworkURL,
              cornerRadius: 13,
              placeholderSystemImage: "waveform"
            )
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
              Text(player.currentTrack?.title ?? "")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

              Text(player.currentTrack?.artist ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)

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
      .padding(.horizontal, 7)
      .padding(.top, 7)
      .padding(.bottom, 5)

      Capsule()
        .fill(.white.opacity(0.12))
        .frame(height: 2)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.72))
            .scaleEffect(
              x: max(0, min(1, player.progress)),
              y: 1,
              anchor: .leading
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 1)
        .allowsHitTesting(false)
    }
    .frame(height: 58)
    .background(
      .ultraThinMaterial,
      in: RoundedRectangle(cornerRadius: 27, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 27, style: .continuous)
        .stroke(.white.opacity(0.14), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.15), radius: 24, y: 10)
    .contentShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    .simultaneousGesture(
      DragGesture(minimumDistance: 12)
        .onEnded { value in
          if value.translation.height < -24,
             abs(value.translation.height) > abs(value.translation.width) * 1.2 {
            openPlayer()
          }
        }
    )
  }
}

