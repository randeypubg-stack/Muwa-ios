import { upload, getInfo } from "@floot/storage";
import superjson from "superjson";
import { NotAuthenticatedError } from "../helpers/getSetServerSession";
import { getServerUserSession } from "../helpers/getServerUserSession";
import { schema, type OutputType } from "./publicationUpload_POST.schema";
import {
  guardMutation,
  readTextLimited,
  SecurityError,
} from "../helpers/requestSecurity";
import { reservePublication } from "../helpers/uploadSecurity";
import { inspectStoredMedia } from "../helpers/mediaSecurity";

const response = (body: unknown, status = 200) =>
  new Response(superjson.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
export async function handle(request: Request) {
  try {
    guardMutation(request);
    const { user } = await getServerUserSession(request);
    let raw: unknown;
    try {
      raw = superjson.parse(await readTextLimited(request, 16 * 1024));
    } catch (error) {
      if (error instanceof SecurityError) throw error;
      throw new SecurityError("Некорректный запрос.");
    }
    const parsed = schema.safeParse(raw);
    if (!parsed.success)
      throw new SecurityError("Неверный формат или размер файла.");
    const input = parsed.data;
    const reservation = await reservePublication(
      user.id,
      user.role === "admin",
      input,
    );
    if (reservation.reused) {
      const info = await getInfo({
        visibility: "private",
        filename: reservation.filename,
      });
      if (info.ok && info.exists) {
        const actual = await inspectStoredMedia(
          "private",
          reservation.filename,
          input.part,
          input.sizeBytes,
          input.contentType,
        );
        if (actual.fingerprint.sha256 !== input.sha256)
          throw new SecurityError(
            "Содержимое уже отправленной публикации отличается.",
            409,
          );
        return response({
          storageKey: reservation.filename,
          presignedUrl: "",
          headers: {},
          alreadyUploaded: true,
        } satisfies OutputType);
      }
    }
    const result = await upload({
      visibility: "private",
      filename: reservation.filename,
      contentType: input.contentType,
      sizeBytes: input.sizeBytes,
      expiresInSeconds: 900,
      ifAbsent: true,
    });
    if (!result.ok)
      throw new SecurityError("Хранилище временно недоступно.", 503);
    return response({
      storageKey: reservation.filename,
      presignedUrl: result.presignedUrl,
      headers: result.headers,
      alreadyUploaded: false,
    } satisfies OutputType);
  } catch (error) {
    if (error instanceof NotAuthenticatedError)
      return response({ error: "Войдите в аккаунт Muwa." }, 401);
    if (error instanceof SecurityError)
      return response({ error: error.message }, error.status);
    console.error(
      "Muwa publication request failed",
      error instanceof Error ? error.name : "unknown",
    );
    return response(
      { error: "Не удалось подготовить загрузку. Повторите позже." },
      503,
    );
  }
}
