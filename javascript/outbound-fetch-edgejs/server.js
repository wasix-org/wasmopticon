const http = require("node:http");

const origin = process.env.UPSTREAM_ORIGIN;
if (!origin) throw new Error("UPSTREAM_ORIGIN is required");

const upstreamPaths = new Map([
  ["/json", "/json"],
  ["/missing", "/missing"],
  ["/timeout", "/slow"],
]);

function send(response, status, payload) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
}

const server = http.createServer(async (request, response) => {
  if (request.url === "/") {
    send(response, 200, { fixture: "outbound-fetch" });
    return;
  }

  const path = upstreamPaths.get(request.url);
  if (!path) {
    send(response, 404, { error: "unknown fixture route" });
    return;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 1500);
  try {
    const upstream = await fetch(new URL(path, origin), {
      headers: { "X-Edgejs-Probe": "from-guest" },
      signal: controller.signal,
    });
    send(response, upstream.status, await upstream.json());
  } catch (error) {
    if (controller.signal.aborted) {
      send(response, 504, { error: "upstream timeout" });
    } else {
      console.error(error);
      send(response, 502, { error: "upstream fetch failed" });
    }
  } finally {
    clearTimeout(timer);
  }
});

server.listen(Number(process.env.PORT || 8080), process.env.HOST || "127.0.0.1");
