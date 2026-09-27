import StoreKit
import SwiftUI

struct PremiumView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var premium: PremiumManager
  @State private var selectedID = "app.muwa.nasheeds.premium.yearly"
  @State private var busy = false
  @State private var promoPresented = false
  var compact = false
  private let tint = Color(red: 0.85, green: 0.91, blue: 1)
  private let benefits = [("Слушайте в фоне", "headphones"), ("Сохраняйте офлайн", "arrow.down.circle"), ("Выводите на AirPlay", "airplayaudio"), ("Управляйте с экрана блокировки", "iphone")]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 10) {
            Image(systemName: premium.isPremium ? "checkmark.seal.fill" : "crown.fill")
              .font(.system(size: 32, weight: .light)).foregroundStyle(tint)
              .padding(.bottom, 6)
            Text(premium.isPremium ? "Ваш Muwa Premium" : "Больше свободы\nс Muwa Premium")
              .font(.system(.largeTitle, design: .rounded, weight: .bold))
              .fixedSize(horizontal: false, vertical: true)
            Text(premium.isPremium ? "Все возможности уже доступны." : "Любимые нашиды — в вашем ритме.")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 20) {
            ForEach(benefits, id: \.0) { benefit in
              VStack(alignment: .leading, spacing: 10) {
                Image(systemName: benefit.1).font(.title2).foregroundStyle(tint)
                Text(benefit.0).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
              }.frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            }
          }.padding(20).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
          if premium.isPremium {
            Label("Premium активен", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            if premium.hasAccountPremium {
              Text(premium.accountExpiresAt.map { "Доступ по аккаунту до \($0.formatted(date: .long, time: .omitted))" } ?? "Бессрочный доступ по аккаунту Muwa")
                .font(.subheadline).foregroundStyle(.secondary)
            }
          } else if premium.isLoading {
            ProgressView("Загружаем предложения…").frame(maxWidth: .infinity)
          } else if premium.products.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Подписка появится позже").font(.headline)
              Text("Сейчас можно активировать подарочный промокод Muwa.").font(.subheadline).foregroundStyle(.secondary)
            }
          } else {
            VStack(spacing: 10) {
              ForEach(premium.products) { product in
                Button { selectedID = product.id } label: {
                  HStack(spacing: 12) {
                    Image(systemName: selectedID == product.id ? "checkmark.circle.fill" : "circle").foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 4) {
                      Text(product.displayName).font(.headline)
                      Text(product.description).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(product.displayPrice).font(.headline)
                  }.padding(16).frame(maxWidth: .infinity).background(.white.opacity(selectedID == product.id ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
                }.buttonStyle(.plain)
              }
            }
          }
          Button { promoPresented = true } label: {
            HStack { Label("Активировать промокод", systemImage: "gift"); Spacer(); Image(systemName: "chevron.right") }
              .font(.subheadline.weight(.semibold)).padding(.vertical, 12).contentShape(Rectangle())
          }.buttonStyle(.plain)
          Text("Ваша поддержка помогает развивать Muwa. Субтитры доступны бесплатно.")
            .font(.caption).foregroundStyle(.secondary)
          if let error = premium.lastError { Text(error).font(.caption).foregroundStyle(.red) }
          Button("Восстановить покупки Apple") { Task { await premium.restore() } }.font(.caption)
        }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
      }
      .background(Color(red: 0.012, green: 0.018, blue: 0.028))
      .safeAreaInset(edge: .bottom) {
        if !premium.isPremium && !premium.products.isEmpty {
          VStack(spacing: 8) {
            Button {
              guard let product = premium.products.first(where: { $0.id == selectedID }) else { return }
              busy = true
              Task { defer { busy = false }; do { try await premium.purchase(product) } catch { premium.lastError = error.localizedDescription } }
            } label: {
              HStack { if busy { ProgressView().tint(.black) }; Text("Оформить Premium").bold() }
                .frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(.black).background(tint, in: Capsule())
            }.disabled(busy)
            Text("Подписка продлевается автоматически. Управление — в настройках Apple.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
          }.padding(.horizontal, 24).padding(.vertical, 12).background(.ultraThinMaterial)
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Text("Muwa").font(.headline).foregroundStyle(.secondary) }
        ToolbarItem(placement: .topBarTrailing) {
          Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Закрыть")
        }
      }
    }
    .task {
      await premium.load()
      if !premium.products.contains(where: { $0.id == selectedID }), let first = premium.products.first { selectedID = first.id }
    }
    .sheet(isPresented: $promoPresented) { MuwaPromoView() }
  }
}

struct MuwaPromoView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var premium: PremiumManager
  @EnvironmentObject private var auth: AuthManager
  @State private var code = ""
  @State private var busy = false
  @State private var message: String?
  @State private var success = false
  @State private var label = "Подарок"
  @State private var duration = 30
  @State private var uses = 1
  @State private var validity = 30
  @State private var createdCode: String?
  @State private var codes: [MuwaGiftCode] = []
  @State private var pendingDisable: MuwaGiftCode?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Подарите время с Muwa", systemImage: "gift.fill").font(.headline).padding(.vertical, 6)
          Text("Введите код от друга или из розыгрыша. Premium закрепится за вашим аккаунтом Muwa.").font(.subheadline).foregroundStyle(.secondary)
          if auth.isAuthenticated {
            TextField("MUWA-…", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().font(.system(.body, design: .monospaced)).accessibilityIdentifier("promo.code")
            Button("Активировать") { run(["action": "redeem", "code": code]) }
              .disabled(busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          } else {
            Button("Войти в Muwa") { dismiss(); auth.showAuthentication() }
          }
          if busy { ProgressView("Проверяем…") }
          if let message { Text(message).font(.subheadline).foregroundStyle(success ? Color.green : Color.red).accessibilityIdentifier("promo.result") }
        }
        if premium.canManageCodes {
          Section("Создать подарочный код") {
            TextField("Название для себя", text: $label).onChange(of: label) { _, value in if value.count > 60 { label = String(value.prefix(60)) } }
            Picker("Дней Premium", selection: $duration) { ForEach([7, 30, 90, 180, 365], id: \.self) { Text("\($0)").tag($0) } }
            Picker("Получателей", selection: $uses) { ForEach([1, 5, 10, 25, 50, 100, 1000], id: \.self) { Text("\($0)").tag($0) } }
            Picker("Активировать за", selection: $validity) { ForEach([7, 30, 90, 365], id: \.self) { Text("\($0) дн.").tag($0) } }
            Button("Создать код") { run(["action": "create", "label": label, "durationDays": duration, "maxUses": uses, "validDays": validity]) }
              .disabled(busy || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || createdCode != nil)
            Text("Один аккаунт может использовать код один раз. Срок подарка добавляется к действующему подарочному Premium.").font(.caption).foregroundStyle(.secondary)
          }
          .disabled(createdCode != nil)
          if let createdCode {
            Section("Сохраните код перед закрытием") {
              Text(createdCode).font(.system(.body, design: .monospaced)).textSelection(.enabled)
              ShareLink(item: "Подарок: \(duration) дней Muwa Premium. Код: \(createdCode)\nВ приложении: Профиль → ПРОМОКОД.") { Label("Поделиться кодом", systemImage: "square.and.arrow.up") }
              Text("Полный код показывается только сейчас. Скопируйте или отправьте его получателю.").font(.caption).foregroundStyle(.secondary)
              Button("Код сохранён") { self.createdCode = nil }
            }
          }
          Section("Последние коды") {
            if codes.isEmpty { Text("Вы ещё не создавали коды").foregroundStyle(.secondary) }
            ForEach(codes) { item in
              VStack(alignment: .leading, spacing: 6) {
                Text(item.label).font(.headline)
                Text("\(item.durationDays) дней · активировано \(item.uses) из \(item.maxUses)").font(.caption).foregroundStyle(.secondary)
                if let expires = MuwaPremiumAPI.date(item.expiresAt) {
                  Text("Активация до \(expires.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                }
                if item.disabled { Text("Отключён").font(.caption).foregroundStyle(.secondary) }
                else { Button("Отключить новые активации", role: .destructive) { pendingDisable = item }.font(.caption).disabled(busy) }
              }.padding(.vertical, 5)
            }
          }
        }
      }
      .navigationTitle("Промокод").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
      .task {
        await premium.refreshAccount()
        if premium.canManageCodes { run(["action": "list"]) }
      }
      .onChange(of: auth.user?.id) { _, _ in codes = []; createdCode = nil; message = nil; code = "" }
      .confirmationDialog("Отключить код? Уже выданный Premium сохранится.", isPresented: Binding(get: { pendingDisable != nil }, set: { if !$0 { pendingDisable = nil } })) {
        if let item = pendingDisable { Button("Отключить", role: .destructive) { run(["action": "disable", "id": item.id]); pendingDisable = nil } }
      }
    }
  }

  private func run(_ body: [String: Any]) {
    guard !busy else { return }
    busy = true; message = nil
    Task {
      defer { busy = false }
      do {
        let result = try await premium.accountRequest(body)
        if let list = result.codes { codes = list }
        if let value = result.code { createdCode = value }
        success = true
        if body["action"] as? String == "redeem" {
          message = result.alreadyRedeemed == true ? "Этот код уже активирован на вашем аккаунте." : "Готово! Premium активирован."
          code = ""
        }
      } catch is CancellationError {} catch { success = false; message = error.localizedDescription }
    }
  }
}
