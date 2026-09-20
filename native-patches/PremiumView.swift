import StoreKit
import SwiftUI

struct PremiumView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var premium: PremiumManager
  @State private var selectedID = "app.muwa.nasheeds.premium.yearly"
  @State private var purchaseInProgress = false

  var compact = false

  private let benefits = [
    ("Фоновое\nпрослушивание", "headphones"),
    ("Офлайн-\nдоступ", "arrow.down.circle"),
    ("Тексты\nи переводы", "captions.bubble"),
    ("AirPlay", "airplayaudio"),
    ("Управление с\nэкрана блокировки", "iphone"),
  ]

  var body: some View {
    Group {
      if compact {
        compactBody
      } else {
        fullBody
      }
    }
    .task { await premium.load() }
  }

  private var compactBody: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        Color(red: 0.006, green: 0.018, blue: 0.032).ignoresSafeArea()

        RadialGradient(
          colors: [
            Color(red: 0.16, green: 0.08, blue: 0.03).opacity(0.72),
            Color.clear
          ],
          center: .topTrailing,
          startRadius: 8,
          endRadius: 260
        )
        .ignoresSafeArea()

        ScrollView(showsIndicators: false) {
          VStack(spacing: 14) {
            Spacer(minLength: 54)
            compactHeader
            compactBenefits
            plans
            purchaseBlock
          }
          .padding(.horizontal, 16)
          .padding(.bottom, max(proxy.safeAreaInsets.bottom, 16))
          .frame(maxWidth: 620)
          .frame(maxWidth: .infinity)
        }

        closeButton
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .zIndex(30)
      }
    }
  }

  private var fullBody: some View {
    GeometryReader { proxy in
      let layout = AdaptiveLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)

      ZStack(alignment: .top) {
        Color(red: 0.006, green: 0.018, blue: 0.032).ignoresSafeArea()
        PremiumNightScene()
          .frame(height: layout.isLandscape ? max(300, proxy.size.height * 0.78) : 420)
          .ignoresSafeArea(edges: .top)

        ScrollView(showsIndicators: false) {
          VStack(spacing: 20) {
            Spacer(minLength: layout.isLandscape ? 80 : 205)

            if layout.isWide {
              HStack(alignment: .top, spacing: layout.isPad ? 28 : 20) {
                VStack(spacing: 18) {
                  heroBlock
                  benefitsGrid
                }
                .frame(maxWidth: 520)

                VStack(spacing: 18) {
                  supportBlock
                  plans
                  purchaseBlock
                }
                .frame(maxWidth: 480)
              }
            } else {
              heroBlock
              benefitsGrid
              supportBlock
              plans
              purchaseBlock
            }
          }
          .padding(.horizontal, layout.horizontalPadding)
          .padding(.bottom, 20)
          .adaptiveFrame(maxWidth: min(layout.contentMaxWidth, 1060))
        }

        closeButton
          .padding(.horizontal, layout.horizontalPadding)
          .padding(.top, 6)
          .zIndex(30)
      }
    }
  }

  private var closeButton: some View {
    HStack {
      Button(action: { dismiss() }) {
        Image(systemName: "xmark")
          .font(.system(size: 19, weight: .semibold))
          .frame(width: 46, height: 46)
          .background(.black.opacity(0.36), in: Circle())
          .overlay(Circle().stroke(.white.opacity(0.16)))
          .shadow(color: .black.opacity(0.24), radius: 12, y: 4)
      }
      .buttonStyle(.plain)

      Spacer()
    }
  }

  private var compactHeader: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color(red: 0.93, green: 0.76, blue: 0.49).opacity(0.15))
        Image(systemName: "moon.stars.fill")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(Color(red: 0.93, green: 0.76, blue: 0.49))
      }
      .frame(width: 46, height: 46)

      VStack(alignment: .leading, spacing: 3) {
        Text("Premium")
          .font(.system(size: 26, weight: .bold, design: .rounded))
        Text("Больше возможностей, не закрывая плеер")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }

  private var compactBenefits: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
          VStack(alignment: .leading, spacing: 8) {
            Image(systemName: benefit.1)
              .font(.system(size: 19, weight: .semibold))
              .foregroundStyle(Color(red: 0.93, green: 0.77, blue: 0.52))
            Text(benefit.0.replacingOccurrences(of: "\n", with: " "))
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.white.opacity(0.88))
              .lineLimit(2)
          }
          .frame(width: 122, height: 72, alignment: .leading)
          .padding(.horizontal, 12)
          .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(.white.opacity(0.08), lineWidth: 1)
          )
        }
      }
      .padding(.vertical, 1)
    }
  }

  private var heroBlock: some View {
    VStack(spacing: 10) {
      Text("СЛУШАЙТЕ БОЛЬШЕ")
        .font(.caption2.weight(.bold))
        .tracking(4)
        .foregroundStyle(.white.opacity(0.56))
      Text("Откройте \(Text("Premium").foregroundStyle(Color(red: 0.93, green: 0.76, blue: 0.49)))")
        .font(.system(size: 37, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.76)
        .lineLimit(1)
      Text("Слушайте нашиды глубже, удобнее\nи без ограничений")
        .font(.system(size: 14))
        .multilineTextAlignment(.center)
        .foregroundStyle(.white.opacity(0.78))
    }
    .frame(maxWidth: .infinity)
  }

  private var supportBlock: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 9) {
        Image(systemName: "heart.fill")
          .foregroundStyle(.red)
        Text("Поддержите нас")
          .font(.title2.bold())
      }
      Text(
        "Ваша подписка помогает развивать Muwa Nasheeds и добавлять больше качественного контента."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineSpacing(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var purchaseBlock: some View {
    VStack(spacing: 12) {
      if premium.isPremium {
        Label("Premium активен", systemImage: "checkmark.seal.fill")
          .foregroundStyle(.green)
          .font(.headline)
          .padding(.vertical, 8)
      } else {
        Button(action: purchaseSelected) {
          HStack(spacing: 8) {
            if purchaseInProgress { ProgressView().tint(.black) }
            Text(premium.products.isEmpty ? "Premium пока недоступен" : "Попробовать Premium")
            Image(systemName: "chevron.right")
          }
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity)
          .frame(height: compact ? 52 : 58)
          .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(premium.products.isEmpty || purchaseInProgress)
        .opacity(premium.products.isEmpty ? 0.58 : 1)
      }

      Button("Восстановить покупки") {
        Task { await premium.restore() }
      }
      .font(.caption)
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)

      if let error = premium.lastError {
        Text(error)
          .font(.caption2)
          .foregroundStyle(.red.opacity(0.88))
          .multilineTextAlignment(.center)
      }

      if !compact {
        Text(
          premium.products.isEmpty
            ? "Подписка временно недоступна. После подключения продуктов в App Store цены загрузятся автоматически."
            : "Оплата и управление подпиской выполняются через Apple StoreKit."
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .lineSpacing(2)
      }
    }
  }

  private var benefitsGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
      ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
        VStack(spacing: 9) {
          Image(systemName: benefit.1)
            .font(.title2)
            .foregroundStyle(Color(red: 0.93, green: 0.77, blue: 0.52))
          Text(benefit.0)
            .font(.caption2)
            .multilineTextAlignment(.center)
            .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 98)
      }
    }
    .padding(8)
    .glassPanel(cornerRadius: 27)
  }

  @ViewBuilder
  private var plans: some View {
    if premium.products.isEmpty {
      HStack(spacing: 10) {
        fallbackPlan("Ежемесячно", "399 ₽", "/мес", id: "app.muwa.nasheeds.premium.monthly")
        fallbackPlan(
          "Годовая", "2 990 ₽", "/год", id: "app.muwa.nasheeds.premium.yearly", badge: "Выгодно")
      }
    } else {
      HStack(spacing: 10) {
        ForEach(premium.products) { product in
          planCard(product)
        }
      }
    }
  }

  private func planCard(_ product: Product) -> some View {
    Button {
      selectedID = product.id
    } label: {
      VStack(alignment: .leading, spacing: compact ? 12 : 20) {
        Text(product.displayName).font(.caption.bold())
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(product.displayPrice).font(.system(size: compact ? 21 : 24, weight: .bold))
        }
        Spacer(minLength: 0)
        HStack {
          Spacer()
          Image(systemName: selectedID == product.id ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(
              selectedID == product.id ? Color(red: 0.94, green: 0.78, blue: 0.53) : .secondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: compact ? 92 : 116, alignment: .leading)
      .padding(compact ? 13 : 16)
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(
            selectedID == product.id
              ? Color(red: 0.94, green: 0.78, blue: 0.53) : .white.opacity(0.08),
            lineWidth: selectedID == product.id ? 1.6 : 1)
      )
    }
    .buttonStyle(.plain)
    .nativeCard(cornerRadius: 22)
  }

  private func fallbackPlan(
    _ title: String, _ price: String, _ suffix: String, id: String, badge: String? = nil
  ) -> some View {
    Button {
      selectedID = id
    } label: {
      VStack(alignment: .leading, spacing: compact ? 12 : 18) {
        HStack {
          Text(title).font(.caption.bold())
          Spacer()
          if let badge {
            Text(badge)
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(.green, in: Capsule())
          }
        }
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(price).font(.system(size: compact ? 21 : 24, weight: .bold))
          Text(suffix).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        HStack {
          Spacer()
          Image(systemName: selectedID == id ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(
              selectedID == id ? Color(red: 0.94, green: 0.78, blue: 0.53) : .secondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: compact ? 92 : 116, alignment: .leading)
      .padding(compact ? 13 : 16)
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(
            selectedID == id ? Color(red: 0.94, green: 0.78, blue: 0.53) : .white.opacity(0.08),
            lineWidth: selectedID == id ? 1.6 : 1)
      )
    }
    .buttonStyle(.plain)
    .nativeCard(cornerRadius: 22)
  }

  private func purchaseSelected() {
    guard let product = premium.products.first(where: { $0.id == selectedID }) else { return }
    purchaseInProgress = true
    Task {
      defer { purchaseInProgress = false }
      do { try await premium.purchase(product) } catch {
        premium.lastError = error.localizedDescription
      }
    }
  }
}

private struct PremiumNightScene: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.02, green: 0.09, blue: 0.16),
            Color(red: 0.01, green: 0.05, blue: 0.10),
            Color(red: 0.005, green: 0.018, blue: 0.032),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        RadialGradient(
          colors: [.blue.opacity(0.34), .clear], center: .topTrailing, startRadius: 10,
          endRadius: 260)

        Circle()
          .fill(Color(red: 1.0, green: 0.88, blue: 0.62).opacity(0.92))
          .frame(width: 42, height: 42)
          .overlay(
            Circle()
              .fill(Color(red: 0.02, green: 0.08, blue: 0.15))
              .offset(x: 12, y: -5)
          )
          .position(x: proxy.size.width * 0.73, y: 88)

        ForEach(0..<16, id: \.self) { index in
          Circle()
            .fill(.white.opacity(index.isMultiple(of: 3) ? 0.72 : 0.38))
            .frame(width: index.isMultiple(of: 4) ? 2.2 : 1.2)
            .position(
              x: CGFloat((index * 43) % 320) + 20,
              y: CGFloat((index * 29) % 145) + 18
            )
        }

        MosqueSilhouette()
          .fill(Color.black.opacity(0.55))
          .frame(width: proxy.size.width * 0.76, height: 180)
          .position(x: proxy.size.width * 0.69, y: min(proxy.size.height * 0.72, 300))

        LinearGradient(
          colors: [
            .clear, Color(red: 0.006, green: 0.018, blue: 0.032).opacity(0.45),
            Color(red: 0.006, green: 0.018, blue: 0.032),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      }
    }
  }
}

private struct MosqueSilhouette: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    let baseY = rect.maxY

    p.addRect(
      CGRect(x: rect.minX, y: rect.height * 0.72, width: rect.width, height: rect.height * 0.28))

    let center = rect.midX
    let domeWidth = rect.width * 0.48
    let domeBaseY = rect.height * 0.73
    p.move(to: CGPoint(x: center - domeWidth / 2, y: domeBaseY))
    p.addQuadCurve(
      to: CGPoint(x: center + domeWidth / 2, y: domeBaseY),
      control: CGPoint(x: center, y: rect.height * 0.28)
    )
    p.closeSubpath()

    let minaretWidth = rect.width * 0.085
    let minaretX = rect.maxX - rect.width * 0.17
    p.addRect(
      CGRect(
        x: minaretX, y: rect.height * 0.20, width: minaretWidth, height: baseY - rect.height * 0.20)
    )
    p.addEllipse(
      in: CGRect(
        x: minaretX - minaretWidth * 0.16, y: rect.height * 0.16, width: minaretWidth * 1.32,
        height: minaretWidth * 0.80))
    p.move(to: CGPoint(x: minaretX + minaretWidth / 2, y: rect.height * 0.08))
    p.addLine(to: CGPoint(x: minaretX + minaretWidth * 0.15, y: rect.height * 0.18))
    p.addLine(to: CGPoint(x: minaretX + minaretWidth * 0.85, y: rect.height * 0.18))
    p.closeSubpath()

    return p
  }
}
