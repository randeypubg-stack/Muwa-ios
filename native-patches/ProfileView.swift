import SwiftUI
import UIKit

struct ProfileView: View {
  @EnvironmentObject private var premium: PremiumManager
  @EnvironmentObject private var auth: AuthManager
  @State private var premiumPresented = false
  @State private var aboutPresented = false

  let openSearch: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 22) {
          ScreenHeader(
            title: "Профиль",
            subtitle: auth.isAuthenticated ? "Аккаунт и настройки" : "Гостевой режим",
            searchAction: openSearch
          )

          if layout.isWide {
            HStack(alignment: .top, spacing: 20) {
              identityCard
                .frame(maxWidth: .infinity)
              settingsBlock
                .frame(maxWidth: .infinity)
            }
          } else {
            identityCard
            settingsBlock
          }

          Text("Muwa · Нашиды без музыки")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.isCompactLandscapePhone ? 10 : 18)
        .padding(.bottom, layout.isCompactLandscapePhone ? 132 : 170)
        .adaptiveFrame(maxWidth: min(layout.contentMaxWidth, 920))
      }
    }
    .sheet(isPresented: $premiumPresented) { PremiumView() }
    .sheet(isPresented: $aboutPresented) {
      AboutMuwaView()
    }
  }

  private var identityCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Group {
          if let avatar = auth.user?.avatarUrl, let url = URL(string: avatar) {
            AsyncImage(url: url) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              Image("AppMark").resizable().scaledToFill()
            }
          } else {
            Image("AppMark").resizable().scaledToFill()
          }
        }
        .frame(width: 62, height: 62)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.10)))

        VStack(alignment: .leading, spacing: 4) {
          Text(auth.user?.displayName ?? "Гость")
            .font(.title3.bold())
          if let email = auth.user?.email {
            Text(email)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          } else {
            Text("Войдите, чтобы управлять аккаунтом")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          Text(premium.isPremium ? "Premium активен" : "Бесплатный доступ")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(premium.isPremium ? .green : .secondary)
        }
        Spacer()
      }

      if auth.isGuest {
        Button {
          auth.showAuthentication()
        } label: {
          HStack {
            Image(systemName: "person.crop.circle.badge.plus")
            Text("Войти или создать аккаунт").fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
          }
          .padding(15)
          .background(
            .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
      }

      Button {
        premiumPresented = true
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "crown.fill")
            .foregroundStyle(Color(red: 0.94, green: 0.78, blue: 0.52))
          VStack(alignment: .leading, spacing: 3) {
            Text("Premium").bold()
            Text(premium.isPremium ? "Управление подпиской" : "Открыть все возможности")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel()
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("profile.premium")
    }
  }

  private var settingsBlock: some View {
    VStack(spacing: 0) {
      profileRow("Настройки приложения", "gearshape") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      Divider().overlay(.white.opacity(0.05))
      profileRow("Восстановить покупки", "arrow.clockwise") {
        Task { await premium.restore() }
      }
      Divider().overlay(.white.opacity(0.05))
      profileRow("О приложении", "info.circle") {
        aboutPresented = true
      }

      if auth.isAuthenticated {
        Divider().overlay(.white.opacity(0.05))
        profileRow("Выйти из аккаунта", "rectangle.portrait.and.arrow.right", destructive: true) {
          Task { await auth.logout() }
        }
      }
    }
    .padding(.horizontal, 4)
    .nativeCard(cornerRadius: 22)
  }

  private func profileRow(
    _ title: String, _ icon: String, destructive: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon).frame(width: 28)
        Text(title).font(.subheadline)
        Spacer()
        if !destructive {
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
      }
      .foregroundStyle(destructive ? Color.red : Color.primary)
      .padding(.horizontal, 14)
      .frame(height: 54)
    }
    .buttonStyle(.plain)
  }
}

private struct AboutMuwaView: View {
  @Environment(\.dismiss) private var dismiss

  private var versionText: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "—"
    let build = info?["CFBundleVersion"] as? String ?? "—"
    return "Версия \(version) (\(build))"
  }

  var body: some View {
    NavigationStack {
      ZStack {
        AppBackground().ignoresSafeArea()
        VStack(spacing: 18) {
          Image("AppMark")
            .resizable()
            .scaledToFit()
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

          Text("Muwa")
            .font(.title2.bold())

          Text("Нативное приложение для прослушивания нашидов без музыки.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)

          Text(versionText)
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(30)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Готово") { dismiss() }
        }
      }
    }
  }
}

