import SwiftUI

// A presenter reports cached/published content, independently of playback gaps.
// The parent only reserves space for a rail that has actual caption content.
struct PlayerSubtitleRailAvailabilityKey: PreferenceKey {
  static let defaultValue: Set<String> = []
  static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
    value.formUnion(nextValue())
  }
}

// Present from the stable player shell, outside the artwork's frame/offsets.
// Retain the existing manager and language binding; the reader owns no copy.
struct SubtitleReaderPresentation: Identifiable {
  let manager: AISubtitleManager
  let timeline: PlaybackTimeline
  let track: Track
  let language: Binding<AITranslationLanguage>
  let didDismiss: () -> Void
  var id: String { track.id }

  @MainActor var reader: some View {
    AISubtitleReader(manager: manager, timeline: timeline, track: track, language: language)
      .onDisappear(perform: didDismiss)
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
          segments: segments, activeIndex: activeIndex, currentTime: currentTime, language: language, height: height
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
  let presentReader: (SubtitleReaderPresentation) -> Void
  @State private var language: AITranslationLanguage = .original

  private var hasContent: Bool {
    !(manager.document?.segments.isEmpty ?? true) || !legacySubtitles.segments(for: track).isEmpty
  }

  var body: some View {
    Button { openReader() } label: {
      Group {
        if let document = manager.document,
           let activeIndex = document.activeIndex(at: timeline.snapshot.time) {
          SubtitleRail(count: document.segments.count, activeIndex: activeIndex, height: compactHeight) { index, active in
            let segment = document.segments[index]
            VStack(alignment: document.isRTL ? .trailing : .leading, spacing: 5) {
                AISubtitleLine(segment: segment,
                  time: active ? timeline.snapshot.time : segment.start - 1, rtl: document.isRTL)
                  .font(.system(size: 21, weight: .semibold))
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
      if isVisible && !hasContent { openReader() }
    }
    .onChange(of: legacySubtitles.segments(for: track)) { _, captions in
      manager.usePublishedFallback(track, captions: captions)
    }
    .onChange(of: isVisible) { _, visible in
      if visible && !hasContent && !manager.isRecognizing { openReader() }
    }
  }

  private func openReader() {
    presentReader(SubtitleReaderPresentation(
      manager: manager, timeline: timeline, track: track, language: $language,
      didDismiss: { if !hasContent { isVisible = false } }
    ))
  }
}

private struct LegacySubtitleRail: View {
  let segments: [SubtitleSegment]
  let activeIndex: Int
  let currentTime: TimeInterval
  let language: SubtitleLanguage
  let height: CGFloat

  var body: some View {
    SubtitleRail(count: segments.count, activeIndex: activeIndex, height: height) { index, active in
      let segment = segments[index]
      VStack(alignment: .trailing, spacing: 5) {
        AISubtitleLine(segment: AISubtitleSegment(id: segment.id,
          start: segment.start, end: segment.end, original: segment.ar,
          words: segment.words ?? [], timing: segment.words?.isEmpty == false ? "word" : "phrase"),
          time: active ? currentTime : segment.start - 1, rtl: true)
          .font(.system(size: 21, weight: .semibold))
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
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

// A continuous lyric ribbon: stable rows travel through a soft-edged viewport.
// Only the current row scrolls/hits; typography never reflows on focus changes.
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
        ScrollView(.vertical) {
          line(index, delta == 0)
            .accessibilityIdentifier(delta == 0 ? "subtitle-current-text" : "subtitle-context-text-\(index)")
            .frame(minHeight: height * 0.68 - 12, alignment: .center)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(delta != 0)
        .frame(height: height * 0.68)
        .mask {
          // Context can be long; its drawing mask must never shrink the
          // current row's real scroll viewport or steal its gestures.
          Rectangle().scaleEffect(x: 1, y: delta == 0 ? 1 : 0.19 / 0.68)
        }
        .scaleEffect(delta == 0 || !animationsAllowed ? 1 : 0.86, anchor: .trailing)
        .opacity(delta == 0 ? 1 : delta < 0 ? 0.22 : 0.38)
        .offset(x: delta == 0 || !animationsAllowed ? 0 : 3,
                y: CGFloat(delta) * height * 0.42)
        .transition(!animationsAllowed ? .identity : .asymmetric(
          insertion: .opacity.combined(with: .offset(y: height * 0.12)),
          removal: .opacity
        ))
        .allowsHitTesting(delta == 0)
        .accessibilityHidden(delta != 0)
        .accessibilityIdentifier(delta == 0 ? "subtitle-current-scroll" : "subtitle-context-scroll-\(index)")
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .mask {
      // Feather the ribbon's ends, rather than permanently blurring words.
      LinearGradient(stops: [.init(color: .clear, location: 0),
        .init(color: .white, location: 0.12), .init(color: .white, location: 0.88),
        .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
    }
    .animation(animationsAllowed ? MuwaMotion.subtitleFocus : nil, value: activeIndex)
    .transaction { if !animationsAllowed { $0.animation = nil } }
  }
}

// Attribute whole words, never individual Arabic characters. SwiftUI performs
// the normal shaping/wrapping first; the renderer only changes the drawn ink.
private struct SubtitleWordInk: TextAttribute {
  let start: Double
  let end: Double
}

private struct SubtitleInkRenderer: TextRenderer {
  var time: Double
  let sweeps: Bool
  var animatableData: Double {
    get { time }
    set { time = newValue }
  }
  var displayPadding: EdgeInsets { EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5) }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for line in layout {
      for run in line {
        guard let ink = run[SubtitleWordInk.self] else { context.draw(run); continue }
        let active = time >= ink.start && time < ink.end
        var base = context
        base.opacity *= time >= ink.end ? 0.96 : active && !sweeps ? 1 : 0.32
        base.draw(run)
        guard active && sweeps, ink.end > ink.start else { continue }
        let progress = min(1, max(0, (time - ink.start) / (ink.end - ink.start)))
        let bounds = run.typographicBounds.rect
        // The reveal follows the shaped run's own direction, including mixed
        // Arabic/Latin lines, without mirroring text or guessing word timings.
        let rtl = run.layoutDirection == .rightToLeft
        let width = bounds.width * progress
        let reveal = CGRect(x: rtl ? bounds.maxX - width : bounds.minX,
                            y: bounds.minY - 5, width: width, height: bounds.height + 10)
        var light = context
        light.clip(to: Path(reveal))
        light.addFilter(.shadow(color: .white.opacity(0.35), radius: 3))
        light.draw(run)
      }
    }
  }
}

private struct AISubtitleLine: View {
  let segment: AISubtitleSegment
  let time: Double
  let rtl: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  private var animationsAllowed: Bool {
    !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
  }
  private var text: Text {
    let words = segment.words.map(\.text).joined(separator: " ")
    let original = segment.original.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard !segment.words.isEmpty, words == original else {
      return Text(segment.original).foregroundColor(.white)
    }
    return segment.words.enumerated().reduce(Text("")) { result, item in
      let word = item.element
      // Leave separators outside the ink attribute so the word's reveal starts
      // at its glyphs. No per-character layout, synthetic timing or extra clock.
      return result + Text(item.offset == 0 ? "" : " ").foregroundColor(.white.opacity(0.32))
        + Text(word.text).foregroundColor(.white)
          .customAttribute(SubtitleWordInk(start: word.start, end: word.end))
    }
  }
  var body: some View {
    text
      .textRenderer(SubtitleInkRenderer(time: time, sweeps: animationsAllowed))
      .multilineTextAlignment(rtl ? .trailing : .leading)
      .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
      .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
      // Smooth ink between real clock samples. Seeking retargets the same
      // renderer; no animation queue or new playback observer is created.
      .animation(animationsAllowed ? MuwaMotion.subtitleInk : nil, value: time)
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
  var body: some View { reader }

  private var reader: some View {
    NavigationStack {
      Group {
        if manager.document != nil {
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 26) {
                if let doc = manager.document {
                  ForEach(doc.segments) { segment in
                    segmentRow(segment, rtl: doc.isRTL)
                  }
                }
              }
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 16).padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { readerControls }
            .safeAreaInset(edge: .bottom, spacing: 0) {
              Text(manager.isVerifiedByOwner ? "Текст проверен владельцем."
                : "Арабский оригинал сохраняется без перевода. Автоматический текст может содержать ошибки.")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 12)
                .background(.ultraThinMaterial)
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
        } else {
          emptyContent
        }
      }
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
      .onChange(of: player.currentTrack?.id) { _, currentID in
        // The stable presenter outlives a rail. Close its fixed-track reader
        // when playback changes so a new audio clock cannot highlight old text.
        if currentID != track.id { dismiss() }
      }
      .onChange(of: manager.availableLanguages) { _, available in
        if !available.contains(language) { language = .original }
      }
    }.preferredColorScheme(.dark)
  }

  // Insets reserve real space inside the presented page. Scrollable lyrics
  // cannot enlarge a parent stack or push these controls behind the toolbar.
  private var readerControls: some View {
    VStack(spacing: 10) {
      HStack {
        Menu {
          Picker("Перевод", selection: $language) {
            ForEach(manager.availableLanguages) { value in Text(value.title).tag(value) }
          }
        } label: { Label(language.title, systemImage: "globe").font(.subheadline.weight(.medium)) }
        Spacer(minLength: 12)
        Toggle("Следить", isOn: $followsPlayback).font(.caption).fixedSize()
      }
      if let message = manager.error {
        Text(message).font(.callout).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      if manager.translatingLanguage != nil {
        ProgressView("Переводим. Оригинал уже доступен.").font(.caption)
      }
    }
    .padding(.horizontal, 20).padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial)
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
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
        if let translation {
          Text(translation).font(.body).foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.leading)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        // The focus is a soft pool of light, not a rectangular selection card.
        RoundedRectangle(cornerRadius: 22)
          .fill(RadialGradient(colors: [.white.opacity(isActive ? 0.055 : 0), .clear],
                               center: .trailing, startRadius: 0, endRadius: 280))
      }
      .scaleEffect(isActive || !animationsAllowed ? 1 : 0.97, anchor: rtl ? .trailing : .leading)
      .opacity(isActive ? 1 : 0.42)
      .animation(animationsAllowed ? MuwaMotion.subtitleFocus : nil, value: isActive)
    }
    .buttonStyle(.plain).id(segment.id)
    .accessibilityHint("Перейти к этой фразе")
  }
}
