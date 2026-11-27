const http = require("node:http");
const { createElement: h, Suspense } = require("react");
const { renderToPipeableStream } = require("react-dom/server");

const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";

let releaseStream;

function render(response) {
  if (releaseStream) {
    response.writeHead(409).end();
    return;
  }

  let ready = false;
  let finish;
  const suspended = new Promise((resolve) => { finish = resolve; });
  releaseStream = () => {
    ready = true;
    finish();
  };

  function Deferred() {
    if (!ready) throw suspended;
    return h("p", { id: "deferred" }, "React deferred content");
  }

  const page = h("html", { lang: "en" },
    h("head", null, h("title", null, "React streaming fixture")),
    h("body", null,
      h("h1", null, "React stream shell"),
      h(Suspense, { fallback: h("p", { id: "fallback" }, "Waiting for release") },
        h(Deferred),
      ),
    ),
  );

  const stream = renderToPipeableStream(page, {
    onShellReady() {
      response.statusCode = 200;
      response.setHeader("Content-Type", "text/html; charset=utf-8");
      stream.pipe(response);
    },
    onShellError() {
      response.writeHead(500).end("React failed to render");
    },
    onError(error) {
      console.error(error);
    },
  });

  const timer = setTimeout(() => stream.abort(), 25_000);
  function cleanup() {
    clearTimeout(timer);
    releaseStream = undefined;
  }

  response.once("finish", cleanup);
  response.once("close", () => {
    if (!response.writableFinished) {
      cleanup();
      stream.abort();
    }
  });
}

const server = http.createServer((request, response) => {
  if (request.method === "GET" && request.url === "/") {
    response.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("React streaming fixture ready");
    return;
  }
  if (request.method === "GET" && request.url === "/stream") {
    render(response);
    return;
  }
  if (request.method === "POST" && request.url === "/release") {
    if (!releaseStream) {
      response.writeHead(409).end();
      return;
    }
    releaseStream();
    response.writeHead(204).end();
    return;
  }
  response.writeHead(404).end();
});

server.listen(port, host, () => {
  console.log(`React fixture listening on http://${host}:${port}`);
});
