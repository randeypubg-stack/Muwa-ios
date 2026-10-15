import SwiftUI

extension View {
  func libraryNavigation(title: String) -> some View {
    modifier(LibraryNavigationStyle(title: title))
  }
}

// Keep the system back button and interactive edge swipe. The parent screen's
// Russian navigation title supplies the back label without a competing handler.
private struct LibraryNavigationStyle: ViewModifier {
  let title: String
  func body(content: Content) -> some View {
    content
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbarBackground(.hidden, for: .navigationBar)
      .tint(MuwaPalette.ice)
      .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
  }
}

struct PlaylistArtwork: View {
  let tracks: [Track]

  var body: some View {
    GeometryReader { proxy in
      let side = proxy.size.width
      ZStack {
        LinearGradient(colors: [MuwaPalette.blue.opacity(0.28), MuwaPalette.violet.opacity(0.14)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        if tracks.count >= 4 {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
            ForEach(Array(tracks.prefix(4))) { track in
              ArtworkView(url: track.artworkURL, cornerRadius: 0, placeholderSystemImage: "music.note")
                .frame(width: (side - 2) / 2, height: (side - 2) / 2)
            }
          }
        } else if let track = tracks.first {
          ArtworkView(url: track.artworkURL, cornerRadius: 0, placeholderSystemImage: "music.note")
        } else {
          Image(systemName: "music.note.list")
            .font(.system(size: side * 0.34, weight: .medium))
            .foregroundStyle(MuwaPalette.ice)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: side * 0.23, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: side * 0.23).strokeBorder(.white.opacity(0.1), lineWidth: 0.75))
    }
    .accessibilityHidden(true)
  }
}

enum PlaylistSummary {
  static func text(for tracks: [Track]) -> String {
    guard !tracks.isEmpty else { return "Добавьте первые нашиды" }
    let minutes = max(1, Int(tracks.reduce(0) { $0 + $1.duration } / 60))
    return "\(MuwaText.trackCount(tracks.count)) · \(minutes) мин"
  }
}
