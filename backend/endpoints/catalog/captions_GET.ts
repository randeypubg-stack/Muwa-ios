import { db } from "../../helpers/db";
import { sql } from "kysely";
import { schema } from "./captions_GET.schema";
import { recognitionResults } from "../../helpers/localRecognition";
export async function handle(request: Request) {
  const parsed = schema.safeParse(
    Object.fromEntries(new URL(request.url).searchParams),
  );
  if (!parsed.success)
    return Response.json(
      { error: "Некорректный идентификатор." },
      { status: 400 },
    );
  try {
    const row = await db
      .selectFrom("catalogTracks")
      .select(["captions", "captionsRevision", sql<string>`captions_source`.as("source")])
      .where("id", "=", parsed.data.trackId)
      .where("status", "=", "published")
      .executeTakeFirst();
    if (!row)
      return Response.json({ error: "Нашид не найден." }, { status: 404 });
    // Only coarse availability is public. Draft recognition text, quality
    // details and job identifiers remain behind the existing owner endpoint.
    const hasCaptions = Array.isArray(row.captions) && row.captions.length > 0;
    const recognition = hasCaptions ? undefined
      : (await recognitionResults([parsed.data.trackId]))[0];
    const availability = hasCaptions ? "available"
      : recognition?.status === "ready" && recognition.quality?.needsReview !== false ? "review"
      : ["queued", "processing"].includes(recognition?.status ?? "") ? "processing"
      : "unavailable";
    return Response.json(
      {
        segments: row.captions,
        source: row.source,
        revision: row.captionsRevision,
        availability,
      },
      { headers: { "Cache-Control": "public, max-age=30" } },
    );
  } catch {
    return Response.json(
      { error: "Субтитры временно недоступны." },
      { status: 503 },
    );
  }
}
