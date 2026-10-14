import SwiftUI

struct PlaylistCreateSheet: View {
  @Environment(\.dismiss) private var dismiss
  @FocusState private var nameFocused: Bool
  @State private var name = ""
  let onCreate: (String) -> Void
  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    ZStack {
      AppBackground().ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Новый плейлист").font(MuwaTypography.section)
              Text("Дайте подборке своё имя").font(MuwaTypography.detail).foregroundStyle(MuwaPalette.secondary)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
              Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(MuwaPressStyle()).accessibilityLabel("Закрыть")
          }
          VStack(alignment: .leading, spacing: 10) {
            Text("НАЗВАНИЕ").font(MuwaTypography.label).foregroundStyle(MuwaPalette.secondary)
            TextField("Например, для дороги", text: $name)
              .font(MuwaTypography.body).focused($nameFocused).submitLabel(.done)
              .textInputAutocapitalization(.sentences).onSubmit(create)
              .padding(16).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MuwaRadius.control))
              .overlay(RoundedRectangle(cornerRadius: MuwaRadius.control).strokeBorder(MuwaPalette.ice.opacity(nameFocused ? 0.4 : 0.1), lineWidth: 1))
              .accessibilityIdentifier("playlist-name")
          }
          Button(action: create) {
            Text("Создать плейлист").font(MuwaTypography.title).foregroundStyle(MuwaPalette.background)
              .frame(maxWidth: .infinity).padding(.vertical, 17)
              .background(MuwaPalette.ice, in: RoundedRectangle(cornerRadius: MuwaRadius.control))
          }
          .buttonStyle(MuwaPressStyle()).disabled(trimmedName.isEmpty).opacity(trimmedName.isEmpty ? 0.45 : 1)
          .accessibilityIdentifier("playlist-create")
        }
        .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .presentationDetents([.height(340), .medium, .large])
    .presentationDragIndicator(.hidden)
    .presentationBackground(.clear)
  }

  private func create() {
    guard !trimmedName.isEmpty else { return }
    onCreate(trimmedName)
    dismiss()
  }
}
