import SwiftUI

struct QueueTrackRow: View {
  let track: Track
  let isCurrent: Bool
  let isPlaying: Bool
  let play: () -> Void
  let remove: () -> Void
  let move: (Int) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    HStack(spacing: 4) {
      Button(action: play) {
        HStack(spacing: 12) {
          ArtworkView(url: track.artworkURL, cornerRadius: 14, placeholderSystemImage: "music.note")
            .frame(width: 48, height: 48)
          VStack(alignment: .leading, spacing: 4) {
            Text(track.title).font(MuwaTypography.title).lineLimit(2)
            HStack(spacing: 5) {
              Text(track.artist).lineLimit(1).layoutPriority(-1)
              Text("·")
              Text(track.durationText).monospacedDigit()
            }
            .font(MuwaTypography.caption)
            .foregroundStyle(MuwaPalette.secondary)
            if isCurrent {
              HStack(spacing: 5) {
                Image(systemName: isPlaying ? "waveform" : "pause.fill")
                  .symbolEffect(.variableColor.iterative, options: .repeating,
                                isActive: isPlaying && !reduceMotion && scenePhase == .active)
                Text(isPlaying ? "Сейчас играет" : "На паузе")
              }
              .font(MuwaTypography.label)
              .foregroundStyle(MuwaPalette.ice)
            }
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(MuwaPressStyle(scale: 0.99))
      .accessibilityIdentifier("queue-play-" + track.id)
      .accessibilityLabel("\(track.title), \(track.artist), \(track.durationText)")
      .accessibilityAddTraits(isCurrent ? .isSelected : [])

      Button(action: remove) {
        Image(systemName: "minus")
          .font(.system(.body, design: .rounded).weight(.medium))
          .foregroundStyle(MuwaPalette.secondary)
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: MuwaRadius.control))
      }
      .buttonStyle(MuwaPressStyle(scale: 0.90))
      .accessibilityLabel("Удалить \(track.title) из очереди")


    }
    .accessibilityAction(named: Text("Переместить выше")) { move(-1) }
    .accessibilityAction(named: Text("Переместить ниже")) { move(1) }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(isCurrent ? MuwaPalette.ice.opacity(0.075) : .white.opacity(0.025))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(.white.opacity(isCurrent ? 0.12 : 0.055), lineWidth: 0.75)
    }
  }
}
