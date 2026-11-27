import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import start from "./dist/server/server.js";

const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";

createServer(async (incoming, outgoing) => {
  try {
    const requestHost = incoming.headers.host || `127.0.0.1:${port}`;
    const url = new URL(incoming.url, `http://${requestHost}`);
    const asset = /^\/assets\/([\w.-]+\.js)$/.exec(url.pathname);
    if (incoming.method === "GET" && asset) {
      const body = await readFile(new URL(`./dist/client/assets/${asset[1]}`, import.meta.url));
      outgoing.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8" });
      outgoing.end(body);
      return;
    }

    const headers = new Headers();
    for (const [name, value] of Object.entries(incoming.headers)) headers.set(name, value);
    const chunks = [];
    if (incoming.method === "POST") {
      for await (const chunk of incoming) chunks.push(chunk);
    }
    const response = await start.fetch(new Request(url, {
      method: incoming.method,
      headers,
      body: chunks.length ? Buffer.concat(chunks) : undefined,
    }));
    const body = Buffer.from(await response.arrayBuffer());
    outgoing.writeHead(response.status, {
      ...Object.fromEntries(response.headers),
      "X-Fixture": "js-tanstack-start",
    });
    outgoing.end(body);
  } catch (error) {
    console.error(error);
    outgoing.writeHead(error.code === "ENOENT" ? 404 : 500);
    outgoing.end(error.code === "ENOENT" ? "Not Found" : "Internal Server Error");
  }
}).listen(port, host, () => {
  console.log(`TanStack Start server listening on http://${host}:${port}`);
});
