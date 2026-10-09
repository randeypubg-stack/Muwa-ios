import SwiftUI

// A presenter reports cached/published content, independently of playback gaps.
// The parent only reserves space for a rail that has actual caption content.
struct PlayerSubtitleRailAvailabilityKey: PreferenceKey {
  static let defaultValue: Set<String> = []
  static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
    value.formUnion(nextValue())
  }
}

struct PlayerSubtitleOverlay: View {
  @EnvironmentObject private var subtitles: SubtitleManager
  let track: Track
  let currentTime: TimeInterval
  let language: SubtitleLanguage
  var height: CGFloat = 150

  private var segments: [SubtitleSegment] { subtitles.segments(for: track) }
  private var activeIndex: Int? { subtitles.activeIndex(for: track, time: currentTime) }

  var body: some View {
    ZStack {
      Color.clear
      if let activeIndex, segments.indices.contains(activeIndex) {
        LegacySubtitleRail(
          segments: segments, activeIndex: activeIndex, language: language, height: height
        )
      }
    }
    .frame(height: height)
    .preference(key: PlayerSubtitleRailAvailabilityKey.self, value: segments.isEmpty ? [] : [track.id])
    .task(id: track.id) { subtitles.load(for: track) }
  }
}

struct AISubtitleExperience: View {
  @StateObject private var manager = AISubtitleManager()
  @EnvironmentObject private var legacySubtitles: SubtitleManager
  @ObservedObject var timeline: PlaybackTimeline
  let track: Track
  @Binding var isVisible: Bool
  var compactWidth: CGFloat = 112
  var compactHeight: CGFloat = 150
  @State private var language: AITranslationLanguage = .original
  @State private var expanded = false

  private var hasContent: Bool {
    !(manager.document?.segments.isEmpty ?? true) || !legacySubtitles.segments(for: track).isEmpty
  }

  var body: some View {
    Button { expanded = true } label: {
      Group {
        if let document = manager.document,
           let activeIndex = document.activeIndex(at: timeline.snapshot.time) {
          SubtitleRail(count: document.segments.count, activeIndex: activeIndex, height: compactHeight) { index, active in
            let segment = document.segments[index]
            VStack(alignment: document.isRTL ? .trailing : .leading, spacing: 5) {
                AISubtitleLine(segment: segment,
                  time: active ? timeline.snapshot.time : segment.start - 1, rtl: document.isRTL)
                  .font(.system(size: 18, weight: .semibold))
                  .lineLimit(nil)
                  .fixedSize(horizontal: false, vertical: true)
                if let translated = manager.translations[language.rawValue]?.segments[segment.id] {
                  Text(translated)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .opacity(active ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: document.isRTL ? .trailing : .leading)
          }
        } else if manager.document == nil {
          if hasContent {
            PlayerSubtitleOverlay(
              track: track, currentTime: timeline.snapshot.time,
              language: SubtitleLanguage(rawValue: language.rawValue.uppercased()) ?? .arabic,
              height: compactHeight
            )
          }
        }
      }
      .frame(width: compactWidth, height: compactHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHidden(!hasContent)
    .accessibilityLabel("Субтитры. Открыть полный текст")
    .accessibilityValue(manager.document != nil ? "Оригинальный текст доступен"
      : hasContent ? "Обычные субтитры доступны"
      : manager.isRecognizing ? "Загрузка текста" : "Текст пока недоступен")
    .preference(key: PlayerSubtitleRailAvailabilityKey.self, value: hasContent ? [track.id] : [])
    .task(id: track.id) { legacySubtitles.load(for: track) }
    .task(id: "\(track.id)|\(track.audioURL)|\(track.captionsRevision ?? 0)") {
      await manager.load(track)
      manager.usePublishedFallback(track, captions: legacySubtitles.segments(for: track))
      if isVisible && !hasContent { expanded = true }
    }
    .onChange(of: legacySubtitles.segments(for: track)) { _, captions in
      manager.usePublishedFallback(track, captions: captions)
    }
    .onChange(of: isVisible) { _, visible in
      if visible && !hasContent && !manager.isRecognizing { expanded = true }
    }
    .sheet(isPresented: $expanded, onDismiss: {
      if !hasContent { isVisible = false }
    }) {
      AISubtitleReader(manager: manager, timeline: timeline, track: track, language: $language)
    }
  }

}

private struct LegacySubtitleRail: View {
  let segments: [SubtitleSegment]
  let activeIndex: Int
  let language: SubtitleLanguage
  let height: CGFloat

  var body: some View {
    SubtitleRail(count: segments.count, activeIndex: activeIndex, height: height) { index, active in
      let segment = segments[index]
      VStack(alignment: .trailing, spacing: 5) {
        Text(segment.ar)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.trailing)
          .environment(\.layoutDirection, .rightToLeft)
        if language != .arabic {
          Text(segment.text(for: language))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .environment(\.layoutDirection, .leftToRight)
            .opacity(active ? 1 : 0)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

// Both existing subtitle sources use the same transparent, vertically moving
// rail. No material/card is painted over the artwork or player background.
private struct SubtitleRail<Line: View>: View {
  let count: Int
  let activeIndex: Int
  let height: CGFloat
  let line: (Int, Bool) -> Line
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private var animationsAllowed: Bool {
    !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
  }

  init(count: Int, activeIndex: Int, height: CGFloat,
       @ViewBuilder line: @escaping (Int, Bool) -> Line) {
    self.count = count
    self.activeIndex = activeIndex
    self.height = height
    self.line = line
  }

  private var window: [Int] {
    let lower = max(0, activeIndex - 1)
    let upper = min(count - 1, activeIndex + 1)
    return lower <= upper ? Array(lower...upper) : []
  }

  var body: some View {
    ZStack {
      ForEach(window, id: \.self) { index in
        let delta = index - activeIndex
        // Keep the same text/scroll identity and typography while its role
        // changes. Only drawing transforms animate; Arabic wrapping is stable.
        ScrollView(.vertical) {
          line(index, delta == 0)
            .accessibilityIdentifier(delta == 0 ? "subtitle-current-text" : "subtitle-context-text-\(index)")
            .frame(minHeight: height * 0.64 - 8, alignment: .center)
            .padding(.vertical, 4)
        }
          .scrollIndicators(.hidden)
          .scrollDisabled(delta != 0)
          .frame(height: height * 0.64)
          .mask {
            Rectangle().scaleEffect(x: 1, y: delta == 0 ? 1 : 0.15 / 0.64)
          }
          .scaleEffect(delta == 0 || !animationsAllowed ? 1 : 0.96)
          .opacity(delta == 0 ? 1 : 0.32)
          .blur(radius: delta == 0 || !animationsAllowed ? 0 : 1.2)
          .offset(y: CGFloat(delta) * height * 0.43)
          .transition(!animationsAllowed ? .identity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity
          ))
          .allowsHitTesting(delta == 0)
          .accessibilityHidden(delta != 0)
          .accessibilityIdentifier(delta == 0 ? "subtitle-current-scroll" : "subtitle-context-scroll-\(index)")
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .animation(animationsAllowed ? MuwaMotion.subtitleFocus : nil, value: activeIndex)
    .transaction { if !animationsAllowed { $0.animation = nil } }
  }
}

private struct AISubtitleLine: View {
  let segment: AISubtitleSegment
  let time: Double
  let rtl: Bool
  private var text: Text {
    guard !segment.words.isEmpty else { return Text(segment.original).foregroundColor(.white) }
    return segment.words.enumerated().reduce(Text("")) { result, item in
      let word = item.element
      let active = time >= word.start && time < word.end
      return result + Text((item.offset == 0 ? "" : " ") + word.text)
        .foregroundColor(active ? Color(red: 0.73, green: 0.83, blue: 1) : .white.opacity(time >= word.end ? 0.7 : 0.95))
    }
  }
  var body: some View {
    text.multilineTextAlignment(rtl ? .trailing : .leading)
      .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
      .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
      .accessibilityLabel(segment.original)
  }
}

private struct AISubtitleReader: View {
  @ObservedObject var manager: AISubtitleManager
  @ObservedObject var timeline: PlaybackTimeline
  @EnvironmentObject private var player: PlayerManager
  let track: Track
  @Binding var language: AITranslationLanguage
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var followsPlayback = true
  private var animationsAllowed: Bool {
    !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
  }
  private var activeID: String? {
    guard let doc = manager.document, let i = doc.activeIndex(at: timeline.snapshot.time) else { return nil }
    return doc.segments[i].id
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        if manager.document != nil {
          HStack {
            Menu {
              Picker("Перевод", selection: $language) {
                ForEach(manager.availableLanguages) { value in Text(value.title).tag(value) }
              }
            } label: { Label(language.title, systemImage: "globe").font(.subheadline.weight(.medium)) }
            Spacer()
            Toggle("Следить", isOn: $followsPlayback).font(.caption).fixedSize()
          }.padding(.horizontal, 20)
          if let message = manager.error {
            Text(message).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20)
          }
          if manager.translatingLanguage != nil {
            ProgressView("Переводим. Оригинал уже доступен.").font(.caption)
          }
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 22) {
                if let doc = manager.document {
                  ForEach(doc.segments) { segment in segmentRow(segment, rtl: doc.isRTL) }
                }
              }.padding(.horizontal, 8).padding(.vertical, 20)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in followsPlayback = false })
            .onChange(of: activeID) { _, id in
              guard followsPlayback, let id else { return }
              withAnimation(animationsAllowed ? MuwaMotion.subtitleFollow : nil) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: followsPlayback) { _, follows in
              if follows, let id = activeID {
                withAnimation(animationsAllowed ? MuwaMotion.subtitleFollow : nil) { proxy.scrollTo(id, anchor: .center) }
              }
            }
            .onAppear { if let id = activeID { proxy.scrollTo(id, anchor: .center) } }
          }
          Text(manager.isVerifiedByOwner ? "Текст проверен владельцем."
            : "Арабский оригинал сохраняется без перевода. Автоматический текст может содержать ошибки.")
            .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)
        } else {
          emptyContent
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { AppBackground().ignoresSafeArea() }
      .navigationTitle(manager.document == nil ? "Текст нашида" : "Оригинал и перевод")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if manager.document != nil {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              Task { await manager.load(track, retry: true) }
            } label: { Image(systemName: "arrow.clockwise") }
            .disabled(manager.isRecognizing)
            .accessibilityLabel("Обновить субтитры")
          }
        }
        ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
      }
      .task(id: (manager.document?.id ?? "") + "|" + language.rawValue) { await manager.translate(language) }
      .onChange(of: manager.availableLanguages) { _, available in
        if !available.contains(language) { language = .original }
      }
    }.preferredColorScheme(.dark)
  }

  private var emptyContent: some View {
    ScrollView {
      VStack(spacing: 18) {
        ArtworkView(url: track.artworkURL, cornerRadius: 24,
                    placeholderSystemImage: "music.note", contentMode: .fill)
          .frame(width: 112, height: 112)
          .accessibilityHidden(true)
        Text(track.title).font(.title3.weight(.semibold))
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        if manager.isRecognizing {
          ProgressView("Загружаем текст…").padding(.top, 12)
        } else {
          Label(manager.error == nil ? manager.availability.title : "Не удалось загрузить текст",
                systemImage: "captions.bubble")
            .font(.headline).padding(.top, 12)
            .accessibilityIdentifier("subtitle-empty-state")
          Text(manager.error ?? manager.availability.message)
            .font(.callout).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          Button("Проверить снова") {
            Task { await manager.load(track, retry: true) }
          }
          .buttonStyle(.bordered).controlSize(.large)
          .accessibilityIdentifier("subtitle-retry")
        }
      }
      .frame(maxWidth: 440).padding(24).padding(.top, 36)
      .frame(maxWidth: .infinity)
    }
  }

  private func segmentRow(_ segment: AISubtitleSegment, rtl: Bool) -> some View {
    let isActive = activeID == segment.id
    let translation = manager.translations[language.rawValue]?.segments[segment.id]
    return Button {
      guard player.currentTrack?.id == track.id else { return }
      player.seek(to: segment.start / max(player.duration, 1))
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        AISubtitleLine(segment: segment, time: timeline.snapshot.time, rtl: rtl)
          .font(.system(size: 23, weight: .semibold))
          .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        if let translation {
          Text(translation).font(.body).foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.leading)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(isActive ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 18))
      .opacity(isActive ? 1 : 0.48)
      .animation(animationsAllowed ? MuwaMotion.subtitleFocus : nil, value: isActive)
    }
    .buttonStyle(.plain).id(segment.id)
    .accessibilityHint("Перейти к этой фразе")
  }
}
