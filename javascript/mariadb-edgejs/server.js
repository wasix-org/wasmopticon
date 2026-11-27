const http = require("node:http");
const mysql = require("mysql2/promise");

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  connectionLimit: 2,
  connectTimeout: 5000,
});

function send(response, status, data) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(data));
}

async function readInput(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  try {
    const { name, commit } = JSON.parse(Buffer.concat(chunks)) ?? {};
    if (typeof name === "string" && name.trim() && name.length <= 150 &&
        typeof commit === "boolean") {
      return { name: name.trim(), commit };
    }
  } catch (error) {
    if (!(error instanceof SyntaxError)) throw error;
  }
  return null;
}

async function writeEntry({ name, commit }) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [result] = await connection.execute("INSERT INTO entries (name) VALUES (?)", [name]);

    const [[entry]] = await connection.execute(
      "SELECT id, name FROM entries WHERE id = ?", [result.insertId],
    );
    if (commit) await connection.commit();
    else await connection.rollback();
    return { entry, committed: commit };
  } catch (error) {
    try {
      await connection.rollback();
    } catch {
      connection.destroy();
    }
    throw error;
  } finally {
    connection.release();
  }
}

const server = http.createServer(async (request, response) => {
  try {
    if (request.url === "/" && request.method === "GET") {
      const [[row]] = await pool.query("SELECT VERSION() AS version");
      return send(response, 200, { database: "mariadb", version: row.version });
    }
    if (request.url === "/entries" && request.method === "GET") {
      const [entries] = await pool.query("SELECT id, name FROM entries ORDER BY id");
      return send(response, 200, entries);
    }
    if (request.url === "/entries" && request.method === "POST") {
      const input = await readInput(request);
      if (!input) return send(response, 400, { error: "Name and commit flag are required" });
      const result = await writeEntry(input);
      return send(response, input.commit ? 201 : 200, result);
    }
    return send(response, 404, { error: "Route not found" });
  } catch (error) {
    console.error("MariaDB request failed", error);
    return send(response, 500, { error: "Database request failed" });
  }
});

async function start() {
  await pool.query(
    "CREATE TABLE IF NOT EXISTS entries (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(150) NOT NULL) ENGINE=InnoDB",
  );
  server.listen(Number(process.env.PORT || 8080), process.env.HOST || "127.0.0.1");
}

start().catch((error) => {
  console.error(error);
  process.exitCode = 1;
  void pool.end();
});
