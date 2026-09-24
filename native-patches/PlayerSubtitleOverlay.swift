import SwiftUI

struct PlayerSubtitleOverlay: View {
  @EnvironmentObject private var subtitles: SubtitleManager
  let track: Track
  let currentTime: TimeInterval
  let language: SubtitleLanguage

  private var segments: [SubtitleSegment] { subtitles.segments(for: track) }
  private var activeIndex: Int? { subtitles.activeIndex(for: track, time: currentTime) }

  var body: some View {
    Group {
      if let activeIndex, segments.indices.contains(activeIndex) {
        LegacySubtitleRail(
          segments: segments,
          activeIndex: activeIndex,
          language: language
        )
      }
    }
    .allowsHitTesting(false)
  }
}

// The compact player subtitle experience is intentionally not a card.
// It occupies a narrow rail to the right of the cover while the cover itself
// is slightly reduced/shifted by FullPlayerView. Only this rail animates.
struct AISubtitleExperience: View {
  @StateObject private var manager = AISubtitleManager()
  @EnvironmentObject private var legacySubtitles: SubtitleManager
  @ObservedObject var timeline: PlaybackTimeline
  let track: Track
  var compactWidth: CGFloat = 112

  @State private var language: AITranslationLanguage = .original
  @State private var expanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var legacySegments: [SubtitleSegment] {
    legacySubtitles.segments(for: track)
  }

  private var legacyIndex: Int? {
    legacySubtitles.activeIndex(for: track, time: timeline.snapshot.time)
  }

  var body: some View {
    Group {
      if let document = manager.document,
         let activeIndex = document.activeIndex(at: timeline.snapshot.time) {
        AISubtitleRail(
          document: document,
          activeIndex: activeIndex,
          time: timeline.snapshot.time,
          width: compactWidth
        )
        .contentShape(Rectangle())
        .onTapGesture { expanded = true }
        .accessibilityLabel("Открыть текст и перевод")
      } else if let legacyIndex,
                legacySegments.indices.contains(legacyIndex) {
        LegacySubtitleRail(
          segments: legacySegments,
          activeIndex: legacyIndex,
          language: .arabic
        )
        .frame(width: compactWidth)
      } else {
        statusView
          .frame(width: compactWidth)
      }
    }
    .frame(width: compactWidth, maxHeight: .infinity)
    .task(id: track.id) {
      await manager.load(track)
      if manager.document == nil {
        legacySubtitles.load(for: track)
      }
    }
    .sheet(isPresented: $expanded) {
      AISubtitleReader(
        manager: manager,
        timeline: timeline,
        track: track,
        language: $language
      )
    }
  }

  @ViewBuilder
  private var statusView: some View {
    if manager.isRecognizing {
      VStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Загружаем текст…")
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.46))
      }
    } else {
      Text("Текст появится\nвместе с голосом")
        .font(.caption2)
        .multilineTextAlignment(.center)
        .foregroundStyle(.white.opacity(manager.error == nil ? 0.42 : 0.34))
    }
  }
}

private struct AISubtitleRail: View {
  let document: AISubtitleDocument
  let activeIndex: Int
  let time: Double
  let width: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var window: [Int] {
    let lower = max(0, activeIndex - 1)
    let upper = min(document.segments.count - 1, activeIndex + 1)
    guard lower <= upper else { return [] }
    return Array(lower...upper)
  }

  var body: some View {
    ZStack {
      ForEach(window, id: \.self) { index in
        let delta = index - activeIndex
        let segment = document.segments[index]

        Group {
          if delta == 0 {
            AISubtitleLine(
              segment: segment,
              time: time,
              rtl: document.isRTL
            )
            .font(.system(size: 18, weight: .semibold))
            .lineLimit(3)
          } else {
            Text(segment.original)
              .font(.system(size: 12, weight: .medium))
              .lineLimit(2)
              .multilineTextAlignment(document.isRTL ? .trailing : .leading)
              .frame(maxWidth: .infinity, alignment: document.isRTL ? .trailing : .leading)
              .environment(\.layoutDirection, document.isRTL ? .rightToLeft : .leftToRight)
          }
        }
        .frame(width: width, alignment: document.isRTL ? .trailing : .leading)
        .scaleEffect(delta == 0 ? 1 : 0.88)
        .opacity(delta == 0 ? 1 : 0.28)
        .offset(y: CGFloat(delta) * 58)
        .transition(
          reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 28)),
                removal: .opacity.combined(with: .offset(y: -28))
              )
        )
      }
    }
    .frame(width: width, height: 150)
    .clipped()
    .animation(
      reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92),
      value: activeIndex
    )
  }
}

private struct LegacySubtitleRail: View {
  let segments: [SubtitleSegment]
  let activeIndex: Int
  let language: SubtitleLanguage
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var window: [Int] {
    let lower = max(0, activeIndex - 1)
    let upper = min(segments.count - 1, activeIndex + 1)
    guard lower <= upper else { return [] }
    return Array(lower...upper)
  }

  var body: some View {
    ZStack {
      ForEach(window, id: \.self) { index in
        let delta = index - activeIndex
        let segment = segments[index]
        Text(segment.text(for: language))
          .font(.system(size: delta == 0 ? 18 : 12, weight: delta == 0 ? .semibold : .medium))
          .lineLimit(delta == 0 ? 3 : 2)
          .multilineTextAlignment(language == .arabic ? .trailing : .leading)
          .frame(maxWidth: .infinity, alignment: language == .arabic ? .trailing : .leading)
          .environment(\.layoutDirection, language == .arabic ? .rightToLeft : .leftToRight)
          .scaleEffect(delta == 0 ? 1 : 0.88)
          .opacity(delta == 0 ? 1 : 0.28)
          .offset(y: CGFloat(delta) * 58)
          .transition(
            reduceMotion
              ? .opacity
              : .asymmetric(
                  insertion: .opacity.combined(with: .offset(y: 28)),
                  removal: .opacity.combined(with: .offset(y: -28))
                )
          )
      }
    }
    .frame(height: 150)
    .clipped()
    .animation(
      reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92),
      value: activeIndex
    )
    .allowsHitTesting(false)
  }
}

private struct AISubtitleLine: View {
  let segment: AISubtitleSegment
  let time: Double
  let rtl: Bool

  private var text: Text {
    guard !segment.words.isEmpty else {
      return Text(segment.original).foregroundColor(.white)
    }

    return segment.words.enumerated().reduce(Text("")) { result, item in
      let word = item.element
      let active = time >= word.start && time < word.end
      return result + Text((item.offset == 0 ? "" : " ") + word.text)
        .foregroundColor(
          active
            ? Color(red: 0.73, green: 0.83, blue: 1)
            : .white.opacity(time >= word.end ? 0.70 : 0.96)
        )
    }
  }

  var body: some View {
    text
      .multilineTextAlignment(rtl ? .trailing : .leading)
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
    guard let doc = manager.document,
      let i = doc.activeIndex(at: timeline.snapshot.time)
    else { return nil }
    return doc.segments[i].id
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        HStack {
          Menu {
            Picker("Перевод", selection: $language) {
              ForEach(AITranslationLanguage.allCases) { value in
                Text(value.title).tag(value)
              }
            }
          } label: {
            Label(language.title, systemImage: "globe")
              .font(.subheadline.weight(.medium))
          }

          Spacer()

          Toggle("Следить", isOn: $followsPlayback)
            .font(.caption)
            .fixedSize()
        }
        .padding(.horizontal, 20)

        if manager.isRecognizing {
          ProgressView("Распознаём оригинал…").padding()
        }

        if let message = manager.error {
          VStack(spacing: 10) {
            Text(message)
              .font(.callout)
              .foregroundStyle(.secondary)

            Button("Повторить") {
              Task {
                if manager.document == nil {
                  await manager.load(track, retry: true)
                } else {
                  await manager.translate(language)
                }
              }
            }
          }
          .padding(.horizontal, 20)
        }

        if manager.translatingLanguage != nil {
          ProgressView("Переводим. Оригинал уже доступен.")
            .font(.caption)
        }

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
                      AISubtitleLine(
                        segment: segment,
                        time: timeline.snapshot.time,
                        rtl: doc.isRTL
                      )
                      .font(
                        .system(
                          size: 23,
                          weight: activeID == segment.id ? .semibold : .regular
                        )
                      )

                      if let translation =
                        manager.translations[language.rawValue]?.segments[segment.id]
                      {
                        Text(translation)
                          .font(.body)
                          .foregroundStyle(.white.opacity(0.65))
                          .multilineTextAlignment(.leading)
                      }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                      .white.opacity(activeID == segment.id ? 0.065 : 0),
                      in: RoundedRectangle(cornerRadius: 18)
                    )
                    .opacity(activeID == segment.id ? 1 : 0.55)
                  }
                  .buttonStyle(.plain)
                  .id(segment.id)
                  .accessibilityHint("Перейти к этой фразе")
                }
              }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 20)
          }
          .simultaneousGesture(
            DragGesture(minimumDistance: 10)
              .onChanged { _ in followsPlayback = false }
          )
          .onChange(of: activeID) { _, id in
            guard followsPlayback, let id else { return }
            withAnimation(
              reduceMotion ? nil : .easeInOut(duration: 0.28)
            ) {
              proxy.scrollTo(id, anchor: .center)
            }
          }
          .onChange(of: followsPlayback) { _, follows in
            if follows, let id = activeID {
              proxy.scrollTo(id, anchor: .center)
            }
          }
        }

        Text("Распознано автоматически. Текст и время слов могут содержать ошибки.")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 20)
          .padding(.bottom, 8)
      }
      .background(Color.black)
      .navigationTitle("Текст и перевод")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Готово") { dismiss() }
        }
      }
      .task(id: (manager.document?.id ?? "") + "|" + language.rawValue) {
        await manager.translate(language)
      }
    }
    .preferredColorScheme(.dark)
  }
}
