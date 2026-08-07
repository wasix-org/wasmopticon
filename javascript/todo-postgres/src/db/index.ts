import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema";

const host = process.env.DB_HOST ?? import.meta.env.DB_HOST;
const portValue = process.env.DB_PORT ?? import.meta.env.DB_PORT;
const database = process.env.DB_NAME ?? import.meta.env.DB_NAME;
const username = process.env.DB_USERNAME ?? import.meta.env.DB_USERNAME;
const password = process.env.DB_PASSWORD ?? import.meta.env.DB_PASSWORD;
const ssl = (process.env.DB_SSL ?? import.meta.env.DB_SSL) !== "false";

if (!host || !portValue || !database || !username || !password) {
  throw new Error(
    "DB_HOST, DB_PORT, DB_NAME, DB_USERNAME, and DB_PASSWORD are required",
  );
}

const port = Number(portValue);
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("DB_PORT must be a valid TCP port");
}

// node-postgres is a pure JavaScript driver unless its optional native package
// is explicitly installed. Wasmer's managed PostgreSQL endpoint requires TLS.
const pool = new Pool({
  host,
  port,
  database,
  user: username,
  password,
  ssl: ssl ? { rejectUnauthorized: false } : false,
  max: 5,
});

export const db = drizzle(pool, { schema });
