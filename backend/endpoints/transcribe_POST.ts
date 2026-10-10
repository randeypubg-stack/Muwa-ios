import superjson from "superjson";
import { schema } from "./transcribe_POST.schema";
import { guardMutation, readTextLimited, SecurityError } from "../helpers/requestSecurity";

// Preserve the legacy contract while recognition is deferred. The original-first
// provider integration lives in subtitleV2Service; uploads never wait for ASR.
export async function handle(request: Request) {
  try {
    guardMutation(request);
    schema.parse(superjson.parse(await readTextLimited(request, 32 * 1024)));
    return new Response(superjson.stringify({ error: "Автоматическое распознавание пока приостановлено. Сохранённые субтитры доступны.", code: "SERVICE_PAUSED" }), {
      status: 503, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  } catch (error) {
    return new Response(superjson.stringify({ error: error instanceof SecurityError ? error.message : "Некорректный запрос." }), {
      status: error instanceof SecurityError ? error.status : 400,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  }
}
