const http = require("node:http");

const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";

function json(response, status, value) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(value));
}

const server = http.createServer(async (request, response) => {
  response.setHeader("X-Fixture", "js-node");

  const path = new URL(request.url, "http://localhost").pathname;
  if (request.method === "GET" && path === "/") {
    response.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Hello from Node");
  } else if (request.method === "GET" && path === "/json") {
    json(response, 200, { framework: "node" });
  } else if (request.method === "POST" && path === "/echo") {
    try {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      json(response, 200, {
        body: JSON.parse(Buffer.concat(chunks)),
        probe: request.headers["x-probe"],
      });
    } catch (error) {
      if (error instanceof SyntaxError) {
        json(response, 400, { error: "Invalid JSON" });
      } else {
        response.destroy(error);
      }
    }
  } else {
    json(response, 404, { error: "Not Found" });
  }
});

server.listen(port, host, () => {
  console.log(`Node server listening on http://${host}:${port}`);
});
