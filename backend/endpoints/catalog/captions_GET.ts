import { db } from "../../helpers/db";
import { schema } from "./captions_GET.schema";
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
      .select(["captions", "captionsRevision"])
      .where("id", "=", parsed.data.trackId)
      .where("status", "=", "published")
      .executeTakeFirst();
    if (!row)
      return Response.json({ error: "Нашид не найден." }, { status: 404 });
    return Response.json(
      {
        segments: row.captions,
        source: "manual",
        revision: row.captionsRevision,
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
