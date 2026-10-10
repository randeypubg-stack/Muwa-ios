import {
  adminValidation,
  type AdminQuery,
  type AdminState,
} from "../../helpers/adminValidation";
export const schema = adminValidation.query;
export type InputType = AdminQuery;
export type OutputType = AdminState;
export async function getAdminState(
  input: InputType,
  init?: RequestInit,
): Promise<OutputType> {
  const parsed = schema.parse(input);
  const params = new URLSearchParams(
    Object.entries(parsed).map(([k, v]) => [k, String(v)]),
  );
  const response = await fetch("/_api/admin/state?" + params, {
    ...init,
    credentials: "same-origin",
    cache: "no-store",
  });
  const data = await response.json();
  if (!response.ok)
    throw new Error(data.error ?? "Не удалось загрузить данные.");
  return data;
}
