import { adminValidation } from "./adminValidation";
describe("Muwa control panel input boundaries", () => {
  it("keeps Telegram imports as drafts with bounded stable source IDs and SHA-256", () => {
    const input = {
      action: "import-telegram-track",
      uploadId: "9234fbc1-c4e5-4554-a728-48ca6e0a5a97",
      title: "نص",
      artist: "Muwa",
      language: "ar",
      duration: 12,
      status: "draft",
      source: {
        channelId: "-1001234567890",
        messageId: 5,
        audioSha256: "a".repeat(64),
      },
    };
    expect(adminValidation.action.safeParse(input).success).toBeTrue();
    expect(
      adminValidation.action.safeParse({ ...input, status: "published" })
        .success,
    ).toBeFalse();
    expect(
      adminValidation.action.safeParse({
        ...input,
        source: { ...input.source, channelId: "https://example.com" },
      }).success,
    ).toBeFalse();
    expect(
      adminValidation.action.safeParse({
        ...input,
        source: { ...input.source, messageId: 2147483648 },
      }).success,
    ).toBeFalse();
    expect(
      adminValidation.action.safeParse({
        ...input,
        source: { ...input.source, audioSha256: "bad" },
      }).success,
    ).toBeFalse();
  });
  it("rejects intersecting or reversed captions and accepts touching boundaries", () => {
    const row = { start: 0, end: 2, ar: "نص", ru: "", en: "" };
    expect(
      adminValidation.captions.safeParse([row, { ...row, start: 1, end: 3 }])
        .success,
    ).toBeFalse();
    expect(
      adminValidation.captions.safeParse([{ ...row, start: 2, end: 1 }])
        .success,
    ).toBeFalse();
    expect(
      adminValidation.captions.safeParse([row, { ...row, start: 2, end: 3 }])
        .success,
    ).toBeTrue();
  });
  it("rejects empty text, infinite time and excessive files", () => {
    expect(
      adminValidation.captions.safeParse([
        { start: 0, end: 1, ar: " ", ru: "", en: "" },
      ]).success,
    ).toBeFalse();
    expect(
      adminValidation.captions.safeParse([{ start: 0, end: Infinity, ar: "a" }])
        .success,
    ).toBeFalse();
    expect(
      adminValidation.action.safeParse({
        action: "prepare-upload",
        files: [{ part: "cover", contentType: "audio/mpeg", sizeBytes: 10 }],
      }).success,
    ).toBeFalse();
    expect(
      adminValidation.action.safeParse({
        action: "prepare-upload",
        files: [
          {
            part: "cover",
            contentType: "image/jpeg",
            sizeBytes: 11 * 1024 * 1024,
          },
        ],
      }).success,
    ).toBeFalse();
  });
  it("requires a revision for mutations and excludes filesystem paths as track IDs", () => {
    expect(
      adminValidation.action.safeParse({
        action: "set-status",
        trackId: "muwa-01",
        status: "published",
      }).success,
    ).toBeFalse();
    expect(
      adminValidation.action.safeParse({
        action: "set-status",
        trackId: "../bad",
        revision: 1,
        status: "published",
      }).success,
    ).toBeFalse();
  });
});
