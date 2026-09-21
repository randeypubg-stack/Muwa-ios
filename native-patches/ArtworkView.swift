import SwiftUI
import ImageIO
import CoreImage

struct ArtworkView: View {
  let url: URL?
  var cornerRadius: CGFloat = 24
  var placeholderSystemImage = "waveform"

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.white.opacity(0.045))

      if let url {
        CachedArtworkImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .transition(.opacity.combined(with: .scale(scale: 0.985)))

          case .failure:
            placeholder

          case .empty:
            MuwaArtworkLoader()

          @unknown default:
            placeholder
          }
        }
      } else {
        placeholder
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(.white.opacity(0.065), lineWidth: 1)
    )
  }

  private var placeholder: some View {
    Image(systemName: placeholderSystemImage)
      .font(.system(size: 30, weight: .medium))
      .foregroundStyle(.white.opacity(0.72))
  }
}

private struct MuwaArtworkLoader: View {
  @State private var active = false

  var body: some View {
    ZStack {
      Circle()
        .stroke(.white.opacity(0.075), lineWidth: 1)
        .frame(width: 42, height: 42)
        .scaleEffect(active ? 1.12 : 0.86)
        .opacity(active ? 0.12 : 0.55)

      Image(systemName: "waveform")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
        .scaleEffect(active ? 1.04 : 0.94)
        .opacity(active ? 0.92 : 0.50)
    }
    .onAppear {
      guard !active else { return }
      withAnimation(
        .easeOut(duration: 0.22)
      ) {
        active = true
      }
    }
    .accessibilityLabel("Загрузка обложки")
  }
}

struct ArtworkBackdrop: View {
  let url: URL?

  var body: some View {
    ZStack {
      Color(red: 0.003, green: 0.004, blue: 0.006)

      if let url {
        CachedArtworkImage(url: url, backdrop: true) { phase in
          if case .success(let image) = phase {
            image
              .resizable()
              .scaledToFill()
              .saturation(1.18)
              .opacity(0.54)
              .scaleEffect(1.22)
          }
        }
      }

      LinearGradient(
        colors: [.black.opacity(0.08), .black.opacity(0.50), .black.opacity(0.90)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .clipped()
  }
}


private struct CachedArtworkImage<Content: View>: View {
  let url: URL
  var backdrop = false
  @ViewBuilder let content: (AsyncImagePhase) -> Content
  @State private var loadedURL: URL?
  @State private var phase: AsyncImagePhase = .empty

  var body: some View {
    content(loadedURL == url ? phase : .empty)
      .task(id: url) {
        let image = await ArtworkImageStore.shared.image(for: url, backdrop: backdrop)
        guard !Task.isCancelled else { return }
        loadedURL = url
        phase = image.map { .success(Image(uiImage: $0)) }
          ?? .failure(URLError(.cannotDecodeContentData))
      }
  }
}

// Downloads, downsampling and blur preparation execute on this background actor,
// once per URL, rather than during scrolling or the cover transition.
actor ArtworkImageStore {
  static let shared = ArtworkImageStore()
  private let cache = NSCache<NSString, UIImage>()
  private var pending: [String: Task<UIImage?, Never>] = [:]
  private var failures: [String: Date] = [:]
  private let context = CIContext(options: [.cacheIntermediates: false])

  init() {
    cache.totalCostLimit = 24 * 1024 * 1024
    cache.countLimit = 48
  }

  func image(for url: URL, backdrop: Bool = false) async -> UIImage? {
    let key = url.absoluteString + (backdrop ? "#backdrop" : "#cover")
    if let hit = cache.object(forKey: key as NSString) { return hit }
    if let failure = failures[key], Date().timeIntervalSince(failure) < 20 { return nil }
    if let task = pending[key] { return await task.value }
    let task = Task<UIImage?, Never> {
      if backdrop {
        guard let original = await self.image(for: url), let cg = original.cgImage else { return nil }
        let scale = 96 / CGFloat(max(cg.width, cg.height))
        let small = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 7])
        guard let result = self.context.createCGImage(blurred, from: small.extent) else { return nil }
        return UIImage(cgImage: result)
      }
      do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
          let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
      } catch { return nil }
    }
    pending[key] = task
    let result = await task.value
    pending[key] = nil
    if let result {
      let cost = (result.cgImage?.bytesPerRow ?? 0) * (result.cgImage?.height ?? 0)
      cache.setObject(result, forKey: key as NSString, cost: cost)
      failures[key] = nil
    } else {
      failures[key] = Date()
    }
    return result
  }
}
