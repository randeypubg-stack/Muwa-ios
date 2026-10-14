import SwiftUI

struct AppSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var downloads: DownloadManager
  @ObservedObject private var diagnostics = Diagnostics.shared
  @State private var exportURL: URL?
  @State private var error: String?
  @State private var confirmClear = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Офлайн") {
          LabeledContent("Скачано нашидов", value: "\(downloads.downloadedIDs.count)")
          LabeledContent("Занято на устройстве", value: ByteCountFormatter.string(fromByteCount: downloads.storageBytes, countStyle: .file))
          Text("Загрузки хранятся в приложении. Управлять отдельными файлами можно в Библиотеке → Загрузки.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Диагностика") {
          LabeledContent("Ошибки", value: "\(diagnostics.events.count)")
          LabeledContent("Системные отчёты", value: "\(diagnostics.systemReportCount)")
          Text("Ошибки сохраняются на устройстве. Apple передаёт отчёты о сбоях и зависаниях с задержкой. Пароли, промокоды и содержимое запросов не записываются.").font(.caption).foregroundStyle(.secondary)
          Toggle("Отправлять категории ошибок в Muwa", isOn: $diagnostics.remoteEnabled)
          Text("После входа в аккаунт отправляются только категория, код ошибки и версия приложения. Полные системные отчёты остаются на устройстве. Хранение на сервере — 14 дней.").font(.caption).foregroundStyle(.secondary)
          Button("Подготовить отчёт") {
            do { exportURL = try diagnostics.export() } catch { self.error = error.localizedDescription }
          }
          if let exportURL { ShareLink("Поделиться отчётом", item: exportURL) }
          Button("Очистить диагностику", role: .destructive) { confirmClear = true }
        }
        Section("Доступность") {
          Text("Muwa учитывает увеличение текста, уменьшение движения и прозрачности из системных настроек.")
        }
      }
      .navigationTitle("Настройки")
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
      .confirmationDialog("Очистить сохранённые отчёты?", isPresented: $confirmClear) {
        Button("Очистить", role: .destructive) { diagnostics.clear(); exportURL = nil }
      }
      .alert("Не удалось подготовить отчёт", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        Button("OK", role: .cancel) {}
      } message: { Text(error ?? "") }
    }
  }
}
