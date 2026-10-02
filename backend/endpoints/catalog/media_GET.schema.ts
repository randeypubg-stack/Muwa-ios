import { z } from "zod";
export const schema = z.object({
  trackId: z.string().regex(/^[A-Za-z0-9_-]{1,80}$/),
  part: z.enum(["audio", "cover"]),
  v: z.string().regex(/^[a-f0-9]{32}$/),
});
export type InputType = z.infer<typeof schema>;
export type OutputType = { error: string };
