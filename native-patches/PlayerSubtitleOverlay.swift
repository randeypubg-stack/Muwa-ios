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
        let current = segments[activeIndex]
        let previous = activeIndex > 0 ? segments[activeIndex - 1] : nil
        let next = activeIndex + 1 < segments.count ? segments[activeIndex + 1] : nil

        VStack(alignment: .trailing, spacing: 7) {
          if let previous {
            Text(previous.ar)
              .font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.28))
              .lineLimit(1)
          }

          Text(current.ar)
            .font(.system(size: 20, weight: .semibold))
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.white)
            .lineLimit(2)
            .environment(\.layoutDirection, .rightToLeft)

          if language != .arabic {
            Text(current.text(for: language))
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.white.opacity(0.78))
              .multilineTextAlignment(.trailing)
              .lineLimit(2)
          }

          if let next {
            Text(next.ar)
              .font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.43))
              .lineLimit(1)
          }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .frame(maxWidth: 196, alignment: .trailing)
        .background(
          LinearGradient(
            colors: [.black.opacity(0.05), .black.opacity(0.38)],
            startPoint: .leading,
            endPoint: .trailing
          ),
          in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background(
          .ultraThinMaterial.opacity(0.34),
          in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .transition(.opacity.combined(with: .move(edge: .trailing)))
      }
    }
    .allowsHitTesting(false)
    .animation(.easeInOut(duration: 0.18), value: activeIndex)
  }
}


struct AISubtitleExperience: View {
  @StateObject private var manager = AISubtitleManager()
  @ObservedObject var timeline: PlaybackTimeline
  let track: Track
  var compactWidth: CGFloat = 196
  @State private var language: AITranslationLanguage = .original
  @State private var expanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button { expanded = true } label: {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 5) {
          Image(systemName: "captions.bubble.fill")
          Text("Текст · AI").font(.caption2.weight(.semibold))
          Spacer(minLength: 0)
          Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2)
        }.foregroundStyle(.white.opacity(0.60))
        if let doc = manager.document, let index = doc.activeIndex(at: timeline.snapshot.time) {
          let segment = doc.segments[index]
          AISubtitleLine(segment: segment, time: timeline.snapshot.time, rtl: doc.isRTL)
            .font(.system(size: 19, weight: .semibold))
            .lineLimit(3)
            .id(segment.id)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
          if let translated = manager.translations[language.rawValue]?.segments[segment.id] {
            Text(translated).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
          }
        } else {
          Text(manager.isRecognizing ? "Распознаём оригинал…" : manager.error != nil ? "Открыть субтитры" : "Текст появится вместе с голосом")
            .font(.caption).foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.leading)
        }
      }
      .padding(13)
      .frame(width: compactWidth, alignment: .leading)
      .background(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.86)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
      .overlay(alignment: .leading) { Capsule().fill(Color(red: 0.73, green: 0.83, blue: 1)).frame(width: 2, height: 30).padding(.leading, 2) }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("AI-субтитры. Открыть полный текст")
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: manager.document?.activeIndex(at: timeline.snapshot.time))
    .task(id: track.audioURL) { await manager.load(track) }
    .sheet(isPresented: $expanded) {
      AISubtitleReader(manager: manager, timeline: timeline, track: track, language: $language)
    }
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
