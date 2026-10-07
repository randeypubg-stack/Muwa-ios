import { z } from "zod";
import type { Caption } from "../../helpers/adminValidation";
export const schema = z.object({
  trackId: z.string().regex(/^[A-Za-z0-9_-]{1,80}$/),
});
export type OutputType = {
  segments: Caption[];
  source: "manual" | "automatic";
  revision: number;
};
export async function getCatalogCaptions(
  trackId: string,
  init?: RequestInit,
): Promise<OutputType> {
  const r = await fetch(
    "/_api/catalog/captions?trackId=" +
      encodeURIComponent(schema.parse({ trackId }).trackId),
    init,
  );
  if (!r.ok) throw new Error("Субтитры недоступны.");
  return r.json();
}
