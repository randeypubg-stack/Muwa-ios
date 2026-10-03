import { z } from "zod";
import superjson from "superjson";

export const schema = z.object({
  src: z
    .string()
    .min(1)
    .max(500)
    .refine(
      (value) => value.startsWith("/_cdn/static/"),
      "Unsupported audio source",
    ),
  title: z.string().min(1).max(200),
  durationSeconds: z.number().positive().max(3600),
  embeddedLyrics: z.string().max(20000).nullable().optional(),
});

export type InputType = z.infer<typeof schema>;

export type TranscriptSegment = {
  start: number;
  end: number;
  ar: string;
  ru: string;
  en: string;
  words?: TranscriptWord[];
};

export type TranscriptWord = {
  text: string;
  start: number;
  end: number;
};

export type OutputType = {
  segments: TranscriptSegment[];
  source: "asr";
};

export const postTranscribe = async (
  body: InputType,
  init?: RequestInit,
): Promise<OutputType> => {
  const validatedInput = schema.parse(body);
  const result = await fetch("/_api/transcribe", {
    method: "POST",
    body: superjson.stringify(validatedInput),
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });

  if (!result.ok) {
    const errorObject = superjson.parse<{ error: string; code?: string }>(
      await result.text(),
    );
    const error = new Error(errorObject.error);
    (error as Error & { code?: string }).code = errorObject.code;
    throw error;
  }

  return superjson.parse<OutputType>(await result.text());
};
