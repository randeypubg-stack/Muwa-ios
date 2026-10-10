import { z } from "zod";
const event = z
  .object({
    id: z.string().uuid(),
    occurredAt: z.string().datetime(),
    area: z.enum([
      "auth",
      "session",
      "catalog",
      "download",
      "playback",
      "audio-session",
      "premium",
      "subtitles",
      "publication",
      "controller",
      "session-storage",
      "uncaught",
      "other",
    ]),
    errorType: z.enum(["network", "storage", "playback", "state", "unknown"]),
    errorCode: z.number().int().min(-2147483648).max(2147483647),
  })
  .strict();
export const schema = z
  .object({
    platform: z.enum(["iOS", "Android"]),
    version: z.string().regex(/^\d{1,3}(\.\d{1,3}){0,3}$/),
    build: z.string().regex(/^\d{1,8}$/),
    events: z.array(event).min(1).max(20),
  })
  .strict();
export type InputType = z.infer<typeof schema>;
export type OutputType = { ok: true };
