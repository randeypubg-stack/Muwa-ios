import { sql } from "kysely";
import { db } from "../../helpers/db";
import { getServerUserSession } from "../../helpers/getServerUserSession";
import { NotAuthenticatedError } from "../../helpers/getSetServerSession";
import {
  guardMutation,
  readJSONLimited,
  secureJSON,
  SecurityError,
} from "../../helpers/requestSecurity";
import { takeRateLimit } from "../../helpers/uploadSecurity";
import { schema } from "./events_POST.schema";
export async function handle(request: Request) {
  try {
    guardMutation(request);
    const { user } = await getServerUserSession(request);
    const parsed = schema.safeParse(await readJSONLimited(request, 16 * 1024));
    if (!parsed.success) throw new SecurityError("Неверный формат отчёта.");
    await takeRateLimit(`diagnostics:${user.id}`, 15, 86400);
    await takeRateLimit("diagnostics:global", 1000, 86400);
    const input = parsed.data;
    await db.transaction().execute(async (tx) => {
      for (const e of input.events) {
        const date = new Date(e.occurredAt);
        if (
          date.getTime() > Date.now() + 300000 ||
          date.getTime() < Date.now() - 14 * 86400000
        )
          continue;
        await sql`insert into muwa_diagnostics(id,user_id,platform,version,build,area,error_type,error_code,occurred_at)
          values(${e.id},${user.id},${input.platform},${input.version},${input.build},${e.area},${e.errorType},${e.errorCode},${date}) on conflict(id) do nothing`.execute(
          tx,
        );
      }
      await sql`delete from muwa_diagnostics where received_at<now()-interval '14 days'`.execute(
        tx,
      );
    });
    return secureJSON({ ok: true });
  } catch (error) {
    if (error instanceof NotAuthenticatedError)
      return secureJSON({ error: "Войдите в Muwa." }, 401);
    if (error instanceof SecurityError)
      return secureJSON({ error: error.message }, error.status);
    return secureJSON({ error: "Сервис временно недоступен." }, 503);
  }
}
