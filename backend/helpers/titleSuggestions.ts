import type { SubtitleDocument } from "../endpoints/subtitles/original_POST.schema";

export type TitleSuggestion = {
  title: string;
  excerpt: string;
  start: number;
  method: "opening" | "refrain";
  needsReview: boolean;
};

// A title suggestion quotes the recording; it never claims to identify its
// official title and never changes catalog metadata without an owner's save.
export function needsTitleSuggestion(title: string): boolean {
  const value = title.trim();
  const letters = value.match(/\p{L}/gu) ?? [];
  return (
    letters.length < 3 ||
    /^https?:\/\/|^t\.me\//i.test(value) ||
    /\.(mp3|m4a|wav)$/i.test(value) ||
    /^[a-f\d-]{20,}$/i.test(value) ||
    /^(?:muwa[\s_|-]*)?(?:nasheeds?|audio|track|нашид|аудио|без названия)(?:[\s_|-]*\d*)?$/i.test(
      value,
    )
  );
}

export function suggestTitle(
  title: string,
  document: SubtitleDocument | null,
  needsReview = true,
): TitleSuggestion | null {
  if (!document || !needsTitleSuggestion(title)) return null;
  const phrases = document.segments.filter((segment) => {
    const words = segment.original.trim().split(/\s+/u);
    return (
      words.length >= 3 &&
      (segment.original.match(/\p{L}/gu)?.length ?? 0) >= 8 &&
      !/https?:\/\/|t\.me\/|اشترك.*القناة|subscribe.*channel/i.test(
        segment.original,
      )
    );
  });
  if (!phrases.length) return null;
  const occurrences = new Map<string, number>();
  for (const phrase of phrases) {
    const key = phrase.original.trim().replace(/\s+/gu, " ");
    occurrences.set(key, (occurrences.get(key) ?? 0) + 1);
  }
  const repeated = phrases.find(
    (phrase) =>
      (occurrences.get(phrase.original.trim().replace(/\s+/gu, " ")) ?? 0) >= 2,
  );
  const phrase = repeated ?? phrases[0];
  const words: string[] = [];
  for (const word of phrase.original.trim().split(/\s+/u)) {
    if (words.length >= 9 || [...words, word].join(" ").length > 70) break;
    words.push(word);
  }
  if (words.length < 3) return null;
  return {
    title: words.join(" "),
    excerpt: phrase.original,
    start: phrase.start,
    method: repeated ? "refrain" : "opening",
    needsReview,
  };
}
