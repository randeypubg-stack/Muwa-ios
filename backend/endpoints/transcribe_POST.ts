import { flootAi, FlootAiOutOfCreditsError } from "@floot/ai";
import superjson from "superjson";
import {
  schema,
  type OutputType,
  type TranscriptSegment,
  type TranscriptWord,
} from "./transcribe_POST.schema";
import {
  guardMutation,
  readTextLimited,
  SecurityError,
} from "../helpers/requestSecurity";
import { subtitlePolicy } from "../helpers/subtitlePolicy";

function extractJson(text: string) {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = (fenced?.[1] ?? text).trim();
  const firstBrace = candidate.indexOf("{");
  const lastBrace = candidate.lastIndexOf("}");
  if (firstBrace < 0 || lastBrace <= firstBrace)
    throw new Error("Model returned no JSON");
  return JSON.parse(candidate.slice(firstBrace, lastBrace + 1)) as {
    segments?: unknown;
  };
}

function normalizeSegments(
  raw: unknown,
  durationSeconds: number,
): TranscriptSegment[] {
  if (!Array.isArray(raw)) return [];
  const segments: TranscriptSegment[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    const start = Number(row.start);
    const end = Number(row.end);
    const ar = typeof row.ar === "string" ? row.ar.trim() : "";
    const ru = typeof row.ru === "string" ? row.ru.trim() : "";
    const en = typeof row.en === "string" ? row.en.trim() : "";
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start || !ar)
      continue;
    if (start >= durationSeconds) continue;
    const safeEnd = Math.min(end, durationSeconds);
    if (safeEnd <= start) continue;
    const rawWords = Array.isArray(row.words) ? row.words : [];
    const words: TranscriptWord[] = rawWords
      .flatMap((word) => {
        if (!word || typeof word !== "object") return [];
        const item = word as Record<string, unknown>;
        const text = typeof item.text === "string" ? item.text.trim() : "";
        const wordStart = Number(item.start);
        const wordEnd = Number(item.end);
        if (
          !text ||
          !Number.isFinite(wordStart) ||
          !Number.isFinite(wordEnd) ||
          wordEnd <= wordStart
        )
          return [];
        if (wordStart < start - 0.4 || wordStart >= safeEnd + 0.4) return [];
        return [
          {
            text,
            start: Math.max(start, wordStart),
            end: Math.min(safeEnd, wordEnd),
          },
        ];
      })
      .filter((word) => word.end > word.start)
      .sort((a, b) => a.start - b.start);

    // A model may occasionally return the phrase correctly but omit per-word offsets.
    // Keep the phrase usable and interpolate only as a last-resort display fallback.
    const phraseWords = ar.split(/\s+/).filter(Boolean);
    const timedWords =
      words.length === phraseWords.length
        ? words
        : phraseWords.map((text, index) => {
            const wordStart =
              start + ((safeEnd - start) * index) / phraseWords.length;
            const wordEnd =
              start + ((safeEnd - start) * (index + 1)) / phraseWords.length;
            return { text, start: wordStart, end: wordEnd };
          });

    segments.push({
      start: Math.max(0, start),
      end: safeEnd,
      ar,
      ru,
      en,
      words: timedWords,
    });
  }
  return segments.slice(0, 220);
}

export async function handle(request: Request) {
  try {
    guardMutation(request);
    const input = schema.parse(
      superjson.parse(await readTextLimited(request, 64 * 1024)),
    );
    if (!subtitlePolicy.recognitionEnabled) {
      return new Response(
        superjson.stringify({
          code: "SERVICE_PAUSED",
          error:
            "Автоматическое распознавание пока не подключено. Готовые субтитры остаются доступны.",
        }),
        {
          status: 503,
          headers: {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
          },
        },
      );
    }
    const audioUrl = new URL(input.src, request.url).toString();
    const hint = input.embeddedLyrics?.trim()
      ? `\nAn ID3 lyrics field was found. Treat it only as a spelling hint; verify against the audio and do not invent missing words:\n${input.embeddedLyrics.slice(0, 12000)}`
      : "";

    const response = await flootAi.chat({
      model: "gemini-3.5-flash",
      systemInstruction: {
        parts: [
          {
            text: "You are a precision Arabic speech transcription and forced-alignment engine for nasheed audio. Listen to the supplied recording itself. Transcribe only words clearly audible in the recording and never invent lyrics. Timing accuracy is critical: identify the actual acoustic start and end of every Arabic word, not an even mathematical split. Return short timestamped Arabic phrases plus per-word timestamps and faithful Russian and English translations. Preserve Arabic wording and diacritics only when confidently heard. If a section or word is unclear, omit it rather than guessing.",
          },
        ],
      },
      contents: [
        {
          role: "user",
          parts: [
            { fileData: { mimeType: "audio/mpeg", fileUri: audioUrl } },
            {
              text: `Track: ${input.title}. Exact audio duration: ${input.durationSeconds.toFixed(2)} seconds.${hint}\nReturn JSON only, with this exact shape: {"segments":[{"start":0.00,"end":2.40,"ar":"الكلمة الثانية هنا","ru":"...","en":"...","words":[{"text":"الكلمة","start":0.12,"end":0.64},{"text":"الثانية","start":0.71,"end":1.35},{"text":"هنا","start":1.52,"end":2.18}]}]}. Use seconds with hundredths when possible. No timestamp may exceed ${input.durationSeconds.toFixed(2)}. CRITICAL: every Arabic word in ar must have exactly one matching item in words, in the same textual order. Measure each word's start/end from the audio itself; do NOT divide a phrase duration evenly. Word boundaries are more important than phrase boundaries. Each segment should normally contain only 2–4 audible words, preferably 3 when natural, and its start/end should wrap its first/last word closely. Keep Russian and English translations short and matched to that phrase. Transcribe only words actually audible in the supplied audio. Do not infer lyrics from the title, style, artist, common nasheeds, or the hint. If a word is unclear, omit it instead of guessing. Do not include commentary, labels, markdown, or guessed words.`,
            },
          ],
        },
      ],
      generationConfig: {
        thinkingConfig: { thinkingLevel: "low", includeThoughts: false },
      },
    });

    const text = (response.candidates?.[0]?.content?.parts ?? [])
      .filter((part: any) => typeof part?.text === "string" && !part?.thought)
      .map((part: any) => part.text)
      .join("\n");

    const parsed = extractJson(text);
    const segments = normalizeSegments(parsed.segments, input.durationSeconds);
    if (!segments.length) {
      return new Response(
        superjson.stringify({ error: "Речь не удалось уверенно распознать." }),
        { status: 422 },
      );
    }

    const output: OutputType = { segments, source: "asr" };
    return new Response(superjson.stringify(output), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    if (error instanceof FlootAiOutOfCreditsError) {
      return new Response(
        superjson.stringify({
          error:
            "Распознавание временно недоступно: закончились AI-кредиты проекта.",
          code: "OUT_OF_CREDITS",
        }),
        { status: 503, headers: { "Content-Type": "application/json" } },
      );
    }
    const message =
      error instanceof SecurityError
        ? error.message
        : "Не удалось распознать аудио";
    return new Response(superjson.stringify({ error: message }), {
      status: error instanceof SecurityError ? error.status : 400,
      headers: { "Content-Type": "application/json" },
    });
  }
}
