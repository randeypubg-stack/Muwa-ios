export class SecurityError extends Error {
  constructor(
    message: string,
    readonly status = 400,
  ) {
    super(message);
  }
}
export function guardMutation(request: Request) {
  const type = request.headers
    .get("content-type")
    ?.split(";")[0]
    .trim()
    .toLowerCase();
  if (type !== "application/json")
    throw new SecurityError("Нужен JSON-запрос.", 415);
  const origin = request.headers.get("origin");
  const configured = process.env.MUWA_PUBLIC_ORIGIN;
  if (!configured) throw new SecurityError("Сервер не настроен.", 503);
  const allowed = new Set([new URL(configured).origin]);
  if (
    (origin && !allowed.has(origin)) ||
    request.headers.get("sec-fetch-site") === "cross-site"
  )
    throw new SecurityError("Недопустимый источник запроса.", 403);
}
// Enforce bytes while reading, before parsing or full body allocation.
export async function readTextLimited(
  request: Request,
  maxBytes: number,
): Promise<string> {
  const advertised = request.headers.get("content-length");
  if (
    advertised &&
    (!/^\d+$/.test(advertised) || Number(advertised) > maxBytes)
  )
    throw new SecurityError("Запрос слишком большой.", 413);
  if (!request.body) throw new SecurityError("Нужен JSON-запрос.");
  const reader = request.body.getReader(),
    decoder = new TextDecoder("utf-8", { fatal: true });
  let bytes = 0,
    text = "";
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      bytes += next.value.byteLength;
      if (bytes > maxBytes) {
        await reader.cancel();
        throw new SecurityError("Запрос слишком большой.", 413);
      }
      text += decoder.decode(next.value, { stream: true });
    }
    return text + decoder.decode();
  } catch (error) {
    if (error instanceof SecurityError) throw error;
    throw new SecurityError("Некорректный запрос.");
  } finally {
    reader.releaseLock();
  }
}
export async function readJSONLimited(
  request: Request,
  maxBytes: number,
): Promise<unknown> {
  try {
    return JSON.parse(await readTextLimited(request, maxBytes));
  } catch (error) {
    if (error instanceof SecurityError) throw error;
    throw new SecurityError("Некорректный JSON.");
  }
}
export function secureJSON(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      Vary: "Cookie",
    },
  });
}
