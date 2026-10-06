import path from "node:path";
export function publicOrigin() {
  const value = process.env.MUWA_PUBLIC_ORIGIN;
  if (!value) throw new Error("MUWA_PUBLIC_ORIGIN is required");
  const url = new URL(value);
  const testHTTP = process.env.MUWA_RUNTIME_TEST === "1" &&
    url.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
  if ((!testHTTP && url.protocol !== "https:") || url.username || url.password ||
      url.search || url.hash || url.pathname !== "/") throw new Error("Invalid public origin");
  return url.origin;
}
export function storageRoot() {
  const value = process.env.MUWA_STORAGE_ROOT;
  if (!value || !path.isAbsolute(value)) throw new Error("An absolute private storage root is required");
  return value;
}
export function betaUserAllowed(id: number) {
  const ids = (process.env.MUWA_BETA_USER_IDS ?? "1").split(",").map(x => Number(x.trim()));
  return Number.isSafeInteger(id) && ids.includes(id);
}
// A single server-selected account owns Telegram ingestion. The general admin
// role and closed-beta allowlist must not implicitly grant this permission.
export function telegramImportOwnerAllowed(id: number) {
  const configured = process.env.MUWA_TELEGRAM_OWNER_ID ?? "";
  if (!/^[1-9]\d*$/.test(configured)) return false;
  const ownerId = Number(configured);
  return Number.isSafeInteger(ownerId) && Number.isSafeInteger(id) && id === ownerId;
}
