import { needsTitleSuggestion, suggestTitle } from "./titleSuggestions";
const phrase = "يا رب إن القلب يرجو رحمتك";
const document = {
  version: 2 as const,
  id: "fixture",
  language: "ar",
  segments: [
    {
      id: "s0",
      start: 2,
      end: 8,
      original: phrase,
      words: [],
      timing: "phrase" as const,
    },
  ],
};
describe("Verbatim title suggestions", () => {
  it("suggests an original phrase for generic, emoji, URL and file titles", () => {
    for (const title of [
      "Muwa Nasheed",
      "س",
      "😍",
      "t.me/muwa144",
      "audio.mp3",
    ]) {
      const result = suggestTitle(title, document, true)!;
      expect(result.title).toBe(phrase);
      expect(result.excerpt).toBe(phrase);
      expect(result.start).toBe(2);
      expect(result.needsReview).toBeTrue();
    }
  });
  it("preserves meaningful existing Arabic and Latin titles", () => {
    for (const title of [
      "نبضات شعري",
      "يا رب",
      "Ummati | Muwa Nasheed",
      "AlQaflh | Muwa",
    ]) {
      expect(needsTitleSuggestion(title)).toBeFalse();
      expect(suggestTitle(title, document)).toBeNull();
    }
  });
  it("offers a repeated phrase without modifying its words or the document", () => {
    const doc = {
      ...document,
      segments: [
        { ...document.segments[0], original: "هذا هو مطلع آخر", start: 0 },
        document.segments[0],
        { ...document.segments[0], id: "s2", start: 20, end: 28 },
      ],
    };
    const before = JSON.stringify(doc);
    expect(suggestTitle("Nasheed", doc, false)?.method).toBe("refrain");
    expect(suggestTitle("Nasheed", doc, false)?.title).toBe(phrase);
    expect(JSON.stringify(doc)).toBe(before);
  });
  it("does not invent titles for missing text, short noise or promotional hallucinations", () => {
    expect(suggestTitle("Nasheed", null)).toBeNull();
    const doc = {
      ...document,
      segments: [{ ...document.segments[0], original: "اشترك في القناة" }],
    };
    expect(suggestTitle("Nasheed", doc)).toBeNull();
  });
});
