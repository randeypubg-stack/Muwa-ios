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
    .allowsHitTesting(false)
    .preference(key: PlayerSubtitleRailAvailabilityKey.self, value: segments.isEmpty ? [] : [track.id])
    .task(id: track.id) { subtitles.load(for: track) }
  }
}

struct AISubtitleExperience: View {
  @StateObject private var manager = AISubtitleManager()
  @EnvironmentObject private var legacySubtitles: SubtitleManager
  @ObservedObject var timeline: PlaybackTimeline
  let track: Track
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
              if active {
                AISubtitleLine(segment: segment, time: timeline.snapshot.time, rtl: document.isRTL)
                  .font(.system(size: 18, weight: .semibold))
                  .lineLimit(compactHeight >= 130 ? 2 : 1)
                if let translated = manager.translations[language.rawValue]?.segments[segment.id] {
                  Text(translated)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(compactHeight >= 130 ? 2 : 1)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
                }
              } else {
                Text(segment.original)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(.white)
                  .lineLimit(1)
                  .multilineTextAlignment(document.isRTL ? .trailing : .leading)
                  .environment(\.layoutDirection, document.isRTL ? .rightToLeft : .leftToRight)
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
          } else {
            statusView
          }
        }
      }
      .frame(width: compactWidth, height: compactHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("AI-субтитры. Открыть полный текст")
    .accessibilityValue(manager.document != nil ? "Оригинальный текст доступен"
      : hasContent ? "Обычные субтитры доступны"
      : manager.isRecognizing ? "Загрузка текста" : "Текст пока недоступен")
    .preference(key: PlayerSubtitleRailAvailabilityKey.self, value: hasContent ? [track.id] : [])
    .task(id: track.id) { legacySubtitles.load(for: track) }
    .task(id: track.audioURL) { await manager.load(track) }
    .sheet(isPresented: $expanded) {
      AISubtitleReader(manager: manager, timeline: timeline, track: track, language: $language)
    }
  }

  private var statusView: some View {
    HStack(spacing: 7) {
      if manager.isRecognizing { ProgressView().tint(.white) }
      else { Image(systemName: "captions.bubble") }
      Text(manager.isRecognizing ? "Обработка" : "Текст")
        .font(.caption.weight(.semibold))
    }
    .foregroundStyle(.white.opacity(0.66))
    .frame(minHeight: 44)
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
          .font(.system(size: active ? 18 : 12, weight: active ? .semibold : .medium))
          .foregroundStyle(.white)
          .lineLimit(active && height >= 130 ? 2 : 1)
          .multilineTextAlignment(.trailing)
          .environment(\.layoutDirection, .rightToLeft)
        if active, language != .arabic {
          Text(segment.text(for: language))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(height >= 130 ? 2 : 1)
            .multilineTextAlignment(.leading)
            .environment(\.layoutDirection, .leftToRight)
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
        line(index, delta == 0)
          .scaleEffect(delta == 0 ? 1 : 0.88)
          .opacity(delta == 0 ? 1 : 0.28)
          .offset(y: CGFloat(delta) * min(62, height * 0.38))
          .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 28)),
            removal: .opacity.combined(with: .offset(y: -28))
          ))
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92), value: activeIndex)
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
  @State private var followsPlayback = true
  private var activeID: String? {
    guard let doc = manager.document, let i = doc.activeIndex(at: timeline.snapshot.time) else { return nil }
    return doc.segments[i].id
  }
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        HStack {
          Menu {
            Picker("Перевод", selection: $language) {
              ForEach(AITranslationLanguage.allCases) { value in Text(value.title).tag(value) }
            }
          } label: { Label(language.title, systemImage: "globe").font(.subheadline.weight(.medium)) }
          Spacer()
          Toggle("Следить", isOn: $followsPlayback).font(.caption).fixedSize()
        }.padding(.horizontal, 20)
        if manager.isRecognizing {
          ProgressView("Распознаём оригинал…").padding()
        }
        if let message = manager.error {
          VStack(spacing: 10) {
            Text(message).font(.callout).foregroundStyle(.secondary)
            Button("Повторить") {
              Task {
                if manager.document == nil { await manager.load(track, retry: true) }
                else { await manager.translate(language) }
              }
            }
          }.padding(.horizontal, 20)
        }
        if manager.translatingLanguage != nil { ProgressView("Переводим. Оригинал уже доступен.").font(.caption) }
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
              if let doc = manager.document {
                ForEach(doc.segments) { segment in
                  Button {
                    guard player.currentTrack?.id == track.id else { return }
                    player.seek(to: segment.start / max(player.duration, 1))
                  } label: {
                    VStack(alignment: .leading, spacing: 8) {
                      AISubtitleLine(segment: segment, time: timeline.snapshot.time, rtl: doc.isRTL)
                        .font(.system(size: 23, weight: activeID == segment.id ? .semibold : .regular))
                      if let translation = manager.translations[language.rawValue]?.segments[segment.id] {
                        Text(translation).font(.body).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.leading)
                      }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(activeID == segment.id ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 18))
                    .opacity(activeID == segment.id ? 1 : 0.55)
                  }
                  .buttonStyle(.plain).id(segment.id)
                  .accessibilityHint("Перейти к этой фразе")
                }
              }
            }.padding(.horizontal, 8).padding(.vertical, 20)
          }
          .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in followsPlayback = false })
          .onChange(of: activeID) { _, id in
            guard followsPlayback, let id else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { proxy.scrollTo(id, anchor: .center) }
          }
          .onChange(of: followsPlayback) { _, follows in
            if follows, let id = activeID { proxy.scrollTo(id, anchor: .center) }
          }
        }
        Text("Распознано автоматически. Текст и время слов могут содержать ошибки.")
          .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)
      }
      .background(Color.black)
      .navigationTitle("Оригинал и перевод")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
      .task(id: (manager.document?.id ?? "") + "|" + language.rawValue) { await manager.translate(language) }
    }.preferredColorScheme(.dark)
  }
}
