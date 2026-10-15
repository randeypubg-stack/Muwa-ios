import { Kysely, CamelCasePlugin } from "kysely";
import { PostgresJSDialect } from "kysely-postgres-js";
import postgres from "postgres";
import type { DB } from "./schema";
const url = process.env.MUWA_DATABASE_URL;
if (!url) throw new Error("MUWA_DATABASE_URL is required");
export const db = new Kysely<DB>({
  plugins: [new CamelCasePlugin()],
  dialect: new PostgresJSDialect({
    postgres: postgres(url, { prepare: false, max: 5, idle_timeout: 20, connect_timeout: 10,
      connection: { statement_timeout: 30000, idle_in_transaction_session_timeout: 30000 } }),
  }),
});
