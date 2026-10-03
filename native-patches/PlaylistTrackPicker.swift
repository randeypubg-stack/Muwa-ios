import SwiftUI

struct PlaylistTrackPicker: View {
  let playlistID: UUID
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var library: LibraryStore
  @State private var query = ""
  @State private var selectedIDs = Set<String>()

  private var matches: [Track] {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return Track.catalog.filter { text.isEmpty || $0.title.localizedStandardContains(text) || $0.artist.localizedStandardContains(text) }
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(matches) { track in
          let included = library.playlist(id: playlistID)?.trackIDs.contains(track.id) == true
          Button {
            if selectedIDs.contains(track.id) { selectedIDs.remove(track.id) }
            else { selectedIDs.insert(track.id) }
          } label: {
            HStack(spacing: 12) {
              ArtworkView(url: track.artworkURL, cornerRadius: 12, placeholderSystemImage: "music.note")
                .frame(width: 48, height: 48)
              VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(MuwaTypography.title).foregroundStyle(MuwaPalette.text)
                Text(included ? "Уже в плейлисте" : track.artist).font(MuwaTypography.caption).foregroundStyle(MuwaPalette.secondary)
              }
              Spacer(minLength: 8)
              Image(systemName: included || selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(MuwaPalette.ice).font(.title3)
            }
            .padding(.vertical, 6).contentShape(Rectangle())
          }
          .buttonStyle(MuwaPressStyle(scale: 0.99)).disabled(included)
          .accessibilityAddTraits(included || selectedIDs.contains(track.id) ? .isSelected : [])
          .listRowBackground(Color.clear).listRowSeparatorTint(.white.opacity(0.07))
        }
      }
      .listStyle(.plain).scrollContentBackground(.hidden)
      .overlay { if matches.isEmpty { Text("Нашиды не найдены").foregroundStyle(MuwaPalette.secondary) } }
      .background(AppBackground().ignoresSafeArea())
      .navigationTitle("Добавить нашиды").navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: "Название или исполнитель")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Добавить \(selectedIDs.count)") {
            guard library.playlist(id: playlistID) != nil else { dismiss(); return }
            for track in Track.catalog where selectedIDs.contains(track.id) { library.addTrack(track, to: playlistID) }
            dismiss()
          }
          .disabled(selectedIDs.isEmpty)
        }
      }
    }
    .presentationDragIndicator(.visible)
  }
}
