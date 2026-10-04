import { db } from "../../helpers/db";
import { getUrl } from "../../helpers/storage";
import { publicOrigin } from "../../helpers/runtimeConfig";
import { getServerUserSession } from "../../helpers/getServerUserSession";
import { NotAuthenticatedError } from "../../helpers/getSetServerSession";
import { catalogueMediaURL } from "../../helpers/mediaSecurity";
import { secureJSON } from "../../helpers/requestSecurity";
import { schema } from "./media_GET.schema";
export async function handle(request: Request) {
  try {
    const parsed = schema.safeParse(
      Object.fromEntries(new URL(request.url).searchParams),
    );
    if (!parsed.success) return secureJSON({ error: "Файл не найден." }, 404);
    const input = parsed.data;
    const track = await db
      .selectFrom("catalogTracks")
      .select(["id", "status", "audioFilename", "coverFilename", "duration"])
      .where("id", "=", input.trackId)
      .executeTakeFirst();
    if (!track) return secureJSON({ error: "Файл не найден." }, 404);
    if (track.status !== "published") {
      try {
        if ((await getServerUserSession(request)).user.role !== "admin")
          return secureJSON({ error: "Файл не найден." }, 404);
      } catch (error) {
        if (error instanceof NotAuthenticatedError)
          return secureJSON({ error: "Файл не найден." }, 404);
        throw error;
      }
    }
    const filename =
      input.part === "audio" ? track.audioFilename : track.coverFilename;
    if (
      !filename ||
      !/^catalog\/[0-9a-f-]{36}\/(audio|cover)\.(mp3|m4a|wav|jpg|png|webp)$/.test(
        filename,
      ) ||
      new URL(
        catalogueMediaURL(track.id, input.part, filename),
      ).searchParams.get("v") !== input.v
    )
      return secureJSON({ error: "Файл не найден." }, 404);
    const source = await getUrl({
      visibility: "private",
      filename,
      expiresInSeconds:
        input.part === "audio"
          ? Math.max(3600, Math.min(86400, Math.ceil(track.duration) + 1800))
          : 300,
    });
    if (!source.ok || (new URL(source.url).protocol !== "https:" && !(process.env.MUWA_RUNTIME_TEST === "1" && new URL(source.url).origin === publicOrigin())))
      return secureJSON({ error: "Файл недоступен." }, 503);
    // S3 serves the bytes and Range requests; the app server never proxies an audio stream.
    return new Response(null, {
      status: 302,
      headers: {
        Location: source.url,
        "Cache-Control": "private, no-store",
        Vary: "Cookie",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch {
    return secureJSON({ error: "Файл временно недоступен." }, 503);
  }
}
