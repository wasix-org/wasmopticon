import http from "node:http";
import { randomUUID } from "node:crypto";

const PORT = Number(process.env.PORT || 8080);

const CACHE_DURATIONS = Object.freeze({
  "30s": 30,
  "5m": 5 * 60,
  "1h": 60 * 60,
  "1d": 24 * 60 * 60
});

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", requestOrigin(request));

    if ((request.method === "GET" || request.method === "HEAD") && url.pathname === "/") {
      return sendHtml(response, renderIndex(), 200, request.method === "HEAD");
    }

    if ((request.method === "GET" || request.method === "HEAD") && url.pathname === "/test") {
      return sendHtml(response, renderTestPage(), 200, request.method === "HEAD", {
        "cache-control": "no-store"
      });
    }

    const duration = matchCurrentTimeRoute(url.pathname);
    if ((request.method === "GET" || request.method === "HEAD") && duration) {
      return sendCurrentTime(response, duration, request.method === "HEAD");
    }

    return sendHtml(response, renderNotFound(), 404, request.method === "HEAD", {
      "cache-control": "no-store"
    });
  } catch (error) {
    console.error(error);
    return sendHtml(response, renderError(error), 500, false, {
      "cache-control": "no-store"
    });
  }
});

server.listen(PORT, () => {
  console.log(`CDN cache tester listening on http://localhost:${PORT}`);
});

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

function shutdown() {
  server.close(() => process.exit(0));
}

function matchCurrentTimeRoute(pathname) {
  const match = pathname.match(/^\/current-time\/([^/]+)$/);
  if (!match || !Object.hasOwn(CACHE_DURATIONS, match[1])) {
    return null;
  }
  return { spec: match[1], seconds: CACHE_DURATIONS[match[1]] };
}

function sendCurrentTime(response, duration, headOnly) {
  const generatedAt = new Date().toISOString();
  const cacheControl = `public, max-age=${duration.seconds}`;
  const body = JSON.stringify({
    generatedAt,
    timestamp: Date.parse(generatedAt),
    originRequestId: randomUUID(),
    cache: {
      spec: duration.spec,
      seconds: duration.seconds,
      cacheControl
    }
  }, null, 2) + "\n";

  response.writeHead(200, {
    "cache-control": cacheControl,
    "content-type": "application/json; charset=utf-8",
    "x-cache-duration": duration.spec,
    "x-origin-generated-at": generatedAt
  });
  response.end(headOnly ? undefined : body);
}

function requestOrigin(request) {
  const forwardedProto = firstHeaderValue(request.headers["x-forwarded-proto"]);
  const protocol = forwardedProto || (request.socket.encrypted ? "https" : "http");
  const forwardedHost = firstHeaderValue(request.headers["x-forwarded-host"]);
  const host = forwardedHost || request.headers.host || `127.0.0.1:${PORT}`;
  return `${protocol}://${host}`;
}

function firstHeaderValue(value) {
  if (Array.isArray(value)) {
    return value[0];
  }
  return value?.split(",", 1)[0].trim();
}

function renderIndex() {
  const routeLinks = Object.entries(CACHE_DURATIONS).map(([spec, seconds]) => `
    <li>
      <a href="/current-time/${spec}"><code>/current-time/${spec}</code></a>
      <span>${formatSeconds(seconds)}</span>
    </li>`).join("");

  return renderLayout("CDN Cache Tester", `
    <p class="eyebrow">Wasmer Edge diagnostics</p>
    <h1>CDN Cache Tester</h1>
    <p>Each current-time route returns a freshly generated timestamp and a matching <code>Cache-Control</code> header. Repeated requests should be served by the CDN until the selected duration expires.</p>
    <ul class="routes">${routeLinks}
    </ul>
    <p><a class="button" href="/test">Run nested-request tests</a></p>
  `);
}

function renderTestPage() {
  const tests = Object.keys(CACHE_DURATIONS).flatMap((spec) => [
    { id: `${spec}-header`, name: `${spec}: cache-control header` },
    { id: `${spec}-cached`, name: `${spec}: repeated request is cached` }
  ]);
  const items = tests.map((test) => `
    <li class="result pending" id="${test.id}">
      <strong>PENDING — ${escapeHtml(test.name)}</strong>
      <span>Waiting to run…</span>
    </li>`).join("");

  return renderLayout("Cache test results", `
    <p class="eyebrow">Client-side test run</p>
    <h1 id="summary">0/${tests.length} tests passed · 0 complete</h1>
    <p>Browser JavaScript runs each test against the current-time routes and updates these results as requests complete.</p>
    <ul class="results">${items}
    </ul>
    <p><button class="button" id="run-tests" type="button">Run again</button> <a class="back" href="/">Back to routes</a></p>
    <script>
      const durations = ${JSON.stringify(CACHE_DURATIONS)};
      const total = Object.keys(durations).length * 2;
      const runButton = document.querySelector("#run-tests");
      const summary = document.querySelector("#summary");

      function setResult(id, state, detail) {
        const item = document.getElementById(id);
        const name = item.querySelector("strong").textContent.replace(/^[A-Z]+ — /, "");
        item.className = "result " + state;
        item.querySelector("strong").textContent = state.toUpperCase() + " — " + name;
        item.querySelector("span").textContent = detail;
      }

      async function snapshot(url) {
        const response = await fetch(url, {
          headers: { accept: "application/json" },
          redirect: "manual"
        });
        const body = await response.text();
        let data = null;
        try { data = JSON.parse(body); } catch {}
        return {
          status: response.status,
          cacheControl: response.headers.get("cache-control"),
          body,
          data
        };
      }

      async function runTest(id, test) {
        setResult(id, "running", "Running…");
        try {
          const detail = await test();
          setResult(id, "pass", detail);
          return true;
        } catch (error) {
          setResult(id, "fail", error instanceof Error ? error.message : String(error));
          return false;
        }
      }

      async function runTests() {
        runButton.disabled = true;
        let passed = 0;
        let complete = 0;
        summary.textContent = "0/" + total + " tests passed · 0 complete";

        for (const [spec, seconds] of Object.entries(durations)) {
          const headerId = spec + "-header";
          const cacheId = spec + "-cached";
          setResult(headerId, "pending", "Waiting to run…");
          setResult(cacheId, "pending", "Waiting to run…");

          passed += Number(await runTest(headerId, async () => {
            const response = await snapshot("/current-time/" + spec + "?header-test=" + crypto.randomUUID());
            const expected = "public, max-age=" + seconds;
            if (response.status !== 200 || response.cacheControl !== expected) {
              throw new Error("expected " + expected + "; received " + response.status + " " + (response.cacheControl || "(missing)"));
            }
            return "received " + expected;
          }));
          complete += 1;
          summary.textContent = passed + "/" + total + " tests passed · " + complete + " complete";

          passed += Number(await runTest(cacheId, async () => {
            const url = "/current-time/" + spec + "?cache-test=" + crypto.randomUUID();
            const first = await snapshot(url);
            const second = await snapshot(url);
            if (first.status !== 200 || second.status !== 200) {
              throw new Error("received HTTP " + first.status + " then " + second.status);
            }
            if (first.body !== second.body) {
              throw new Error("origin responses differed (" + (first.data?.originRequestId || "unknown") + " → " + (second.data?.originRequestId || "unknown") + ")");
            }
            return "same origin response (" + (first.data?.originRequestId || "unknown id") + ")";
          }));
          complete += 1;
          summary.textContent = passed + "/" + total + " tests passed · " + complete + " complete";
        }

        runButton.disabled = false;
      }

      runButton.addEventListener("click", runTests);
      runTests();
    </script>
  `);
}

function renderNotFound() {
  return renderLayout("Not found", `
    <h1>Route not found</h1>
    <p>Try one of the cache routes listed on the <a href="/">main page</a>.</p>
  `);
}

function renderError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return renderLayout("Test error", `
    <h1>Test error</h1>
    <p>${escapeHtml(message)}</p>
    <p><a href="/">Back to the main page</a></p>
  `);
}

function renderLayout(title, content) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(title)}</title>
    <style>
      :root { color-scheme: light dark; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
      body { margin: 0; background: #10131a; color: #e7edf6; }
      main { width: min(760px, calc(100% - 2rem)); margin: 4rem auto; }
      h1 { margin: .25rem 0 1rem; font-size: clamp(2rem, 7vw, 4rem); line-height: 1; }
      p { color: #abb8ca; line-height: 1.7; }
      a { color: #80bfff; }
      code { color: #e7edf6; }
      .eyebrow { color: #7de2b8; letter-spacing: .12em; text-transform: uppercase; }
      .routes, .results { padding: 0; margin: 2rem 0; list-style: none; border-top: 1px solid #303949; }
      .routes li, .result { display: flex; justify-content: space-between; gap: 1rem; padding: 1rem; border-bottom: 1px solid #303949; }
      .routes span, .result span { color: #8997aa; text-align: right; }
      .result { flex-direction: column; }
      .result span { text-align: left; }
      .pass strong { color: #7de2b8; }
      .fail strong { color: #ff8b8b; }
      .running strong { color: #80bfff; }
      .pending strong { color: #8997aa; }
      .button { display: inline-block; margin-top: .5rem; padding: .7rem 1rem; border: 0; border-radius: .35rem; background: #2f78db; color: white; font: inherit; text-decoration: none; cursor: pointer; }
      .button:disabled { opacity: .55; cursor: wait; }
      .back { margin-left: 1rem; }
    </style>
  </head>
  <body><main>${content}</main></body>
</html>`;
}

function sendHtml(response, html, statusCode, headOnly, extraHeaders = {}) {
  response.writeHead(statusCode, {
    "content-type": "text/html; charset=utf-8",
    ...extraHeaders
  });
  response.end(headOnly ? undefined : html);
}

function formatSeconds(seconds) {
  if (seconds < 60) return `${seconds} seconds`;
  if (seconds < 3600) return `${seconds / 60} minutes`;
  if (seconds < 86400) return `${seconds / 3600} hour`;
  return `${seconds / 86400} day`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
