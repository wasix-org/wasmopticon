import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/node-postgres";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import pg from "pg";

const { Pool } = pg;

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

const port = Number(required("DB_PORT"));
if (!Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("DB_PORT must be a valid TCP port");
}

const pool = new Pool({
  host: required("DB_HOST"),
  port,
  database: required("DB_NAME"),
  user: required("DB_USERNAME"),
  password: required("DB_PASSWORD"),
  ssl: process.env.DB_SSL === "false" ? false : { rejectUnauthorized: false },
  max: 1,
});

try {
  const db = drizzle(pool);
  const migrationsFolder = fileURLToPath(new URL("../drizzle", import.meta.url));
  await migrate(db, { migrationsFolder });
  console.log("Database migrations completed");
} finally {
  await pool.end();
}
