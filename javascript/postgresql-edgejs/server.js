const http = require("node:http");
const { Pool } = require("pg");

const settings = ["DB_HOST", "DB_PORT", "DB_NAME", "DB_USERNAME", "DB_PASSWORD"];
let db;

function send(response, status, data) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(data));
}

async function readName(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  try {
    const { name } = JSON.parse(Buffer.concat(chunks)) ?? {};
    return typeof name === "string" && name.trim() ? name.trim() : null;
  } catch (error) {
    if (error instanceof SyntaxError) return null;
    throw error;
  }
}

const server = http.createServer(async (request, response) => {
  const path = new URL(request.url, "http://localhost").pathname;
  const method = request.method;
  try {
    if (path === "/" && method === "GET") {
      const configured = settings.every((name) => Boolean(process.env[name]));
      return send(response, configured ? 200 : 503, { database: "postgresql", configured });
    }
    const item = /^\/items\/([1-9][0-9]*)$/.exec(path);
    const id = item ? Number(item[1]) : null;
    if (!(path === "/items" && method === "POST") &&
        !(id && id <= 2147483647 && ["GET", "PATCH", "DELETE"].includes(method))) {
      return send(response, 404, { error: "Route not found" });
    }
    if (!db) return send(response, 503, { error: "Database unavailable" });

    let row;
    if (method === "GET") {
      [row] = (await db.query("SELECT id, name FROM items WHERE id = $1", [id])).rows;
    } else if (method === "DELETE") {
      [row] = (await db.query("DELETE FROM items WHERE id = $1 RETURNING id, name", [id])).rows;
    } else {
      const name = await readName(request);
      if (!name) return send(response, 400, { error: "Name is required" });
      if (method === "POST") {
        [row] = (await db.query("INSERT INTO items (name) VALUES ($1) RETURNING id, name", [name])).rows;
      } else {
        [row] = (await db.query("UPDATE items SET name = $1 WHERE id = $2 RETURNING id, name", [name, id])).rows;
      }
    }
    return row ? send(response, method === "POST" ? 201 : 200, row)
      : send(response, 404, { error: "Item not found" });
  } catch (error) {
    console.error("PostgreSQL request failed", error);
    send(response, 500, { error: "Database request failed" });
  }
});

async function start() {
  if (settings.every((name) => Boolean(process.env[name]))) {
    const { DB_HOST, DB_PORT, DB_NAME, DB_USERNAME, DB_PASSWORD, DB_SSL } = process.env;
    db = new Pool({
      host: DB_HOST,
      port: Number(DB_PORT),
      database: DB_NAME,
      user: DB_USERNAME,
      password: DB_PASSWORD,
      ssl: DB_SSL === "false" ? false : { rejectUnauthorized: false },
    });
    await db.query("CREATE TABLE IF NOT EXISTS items (id serial PRIMARY KEY, name text NOT NULL)");
  }
  server.listen(Number(process.env.PORT || 8080), process.env.HOST || "127.0.0.1");
}

if (require.main === module) {
  start().catch((error) => { console.error(error); process.exitCode = 1; });
}
module.exports = server;
