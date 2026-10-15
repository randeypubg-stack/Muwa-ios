import { schema } from "./translate_POST.schema";
import { subtitleV2Service } from "../../helpers/subtitleV2Service";
import {
  guardMutation,
  readJSONLimited,
  secureJSON,
  SecurityError,
} from "../../helpers/requestSecurity";
export async function handle(request: Request) {
  try {
    guardMutation(request);
    const parsed = schema.safeParse(await readJSONLimited(request, 16 * 1024));
    if (!parsed.success)
      return secureJSON(
        { error: "Неверный язык или документ.", code: "INVALID_INPUT" },
        400,
      );
    return subtitleV2Service.execute(request, "translation", parsed.data);
  } catch (error) {
    if (error instanceof SecurityError)
      return secureJSON(
        { error: error.message, code: "INVALID_INPUT" },
        error.status,
      );
    return secureJSON({ error: "Сервис временно недоступен." }, 503);
  }
}
