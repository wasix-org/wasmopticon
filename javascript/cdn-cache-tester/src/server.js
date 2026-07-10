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

    if ((request.method === "GET" || request.method === "HEAD") && url.pathname === "/uat") {
      return sendHtml(response, renderUatPage(), 200, request.method === "HEAD", {
        "cache-control": "no-store"
      });
    }

    if ((request.method === "GET" || request.method === "HEAD") && url.pathname === "/uat-data") {
      return sendCurrentTime(response, {
        spec: "uat",
        seconds: 24 * 60 * 60,
        cacheControl: "public, max-age=1, s-maxage=86400"
      }, request.method === "HEAD");
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
  const cacheControl = duration.cacheControl || `public, max-age=${duration.seconds}`;
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
    "content-length": Buffer.byteLength(body),
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
    <p><a class="button" href="/test">Run automated tests</a> <a class="button secondary" href="/uat">Open UAT wizard</a></p>
  `);
}

function renderTestPage() {
  const tests = [
    { id: "becomes-cached", name: "Response becomes cached" },
    { id: "client-no-cache", name: "Client Cache-Control bypasses cache" },
    { id: "cache-expires", name: "Cached response expires after 30s" }
  ];
  const items = tests.map((test) => `
    <li class="result pending" id="${test.id}">
      <strong>PENDING — ${escapeHtml(test.name)}</strong>
      <span>Waiting to run…</span>
    </li>`).join("");

  return renderLayout("Cache test results", `
    <p class="eyebrow">Client-side test run</p>
    <h1 id="summary">0/${tests.length} tests passed · 0 complete</h1>
    <p>Browser JavaScript tests the three CDN cache behaviours and updates these results as requests complete.</p>
    <ul class="results">${items}
    </ul>
    <p><button class="button" id="run-tests" type="button">Run again</button> <a class="back" href="/">Back to routes</a></p>
    <script>
      const total = ${tests.length};
      const cacheSeconds = ${CACHE_DURATIONS["30s"]};
      const runButton = document.querySelector("#run-tests");
      const summary = document.querySelector("#summary");

      function setResult(id, state, detail) {
        const item = document.getElementById(id);
        const name = item.querySelector("strong").textContent.replace(/^[A-Z]+ — /, "");
        item.className = "result " + state;
        item.setAttribute("aria-busy", state === "running" ? "true" : "false");
        item.querySelector("strong").textContent = state.toUpperCase() + " — " + name;
        item.querySelector("span").textContent = detail;
      }

      async function snapshot(url, requestHeaders = {}) {
        const headers = { accept: "application/json", ...requestHeaders };
        if (!("cache-control" in headers)) {
          headers["if-none-match"] = '"client-probe-' + crypto.randomUUID() + '"';
        }
        const response = await fetch(url, {
          headers,
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

      function updateSummary(passed, complete) {
        summary.textContent = passed + "/" + total + " tests passed · " + complete + " complete";
      }

      function assertOk(...responses) {
        const failed = responses.find((response) => response.status !== 200);
        if (failed) {
          throw new Error("received HTTP " + failed.status);
        }
      }

      async function runTests() {
        runButton.disabled = true;
        let passed = 0;
        let complete = 0;
        document.querySelectorAll(".result").forEach((item) => {
          setResult(item.id, "pending", "Waiting to run…");
        });
        updateSummary(passed, complete);

        passed += Number(await runTest("becomes-cached", async () => {
          const url = "/current-time/30s?cache-test=" + crypto.randomUUID();
          const first = await snapshot(url);
          const second = await snapshot(url);
          assertOk(first, second);
          if (first.body !== second.body) {
            throw new Error("origin responses differed (" + (first.data?.originRequestId || "unknown") + " → " + (second.data?.originRequestId || "unknown") + ")");
          }
          return "same origin response (" + (first.data?.originRequestId || "unknown id") + ")";
        }));
        complete += 1;
        updateSummary(passed, complete);

        passed += Number(await runTest("client-no-cache", async () => {
          const url = "/current-time/30s?no-cache-test=" + crypto.randomUUID();
          const primed = await snapshot(url);
          const cached = await snapshot(url);
          assertOk(primed, cached);
          if (primed.body !== cached.body) {
            throw new Error("could not prime the cached response");
          }

          const bypassed = await snapshot(url, { "cache-control": "no-cache" });
          assertOk(bypassed);
          if (bypassed.body === primed.body) {
            throw new Error("cached origin response was served despite Cache-Control: no-cache");
          }
          return "no-cache reached origin (" + (primed.data?.originRequestId || "unknown") + " → " + (bypassed.data?.originRequestId || "unknown") + ")";
        }));
        complete += 1;
        updateSummary(passed, complete);

        passed += Number(await runTest("cache-expires", async () => {
          const url = "/current-time/30s?expiry-test=" + crypto.randomUUID();
          const first = await snapshot(url);
          const cached = await snapshot(url);
          assertOk(first, cached);
          if (first.body !== cached.body) {
            throw new Error("could not prime the cached response");
          }

          const waitSeconds = cacheSeconds + 1;
          for (let remaining = waitSeconds; remaining > 0; remaining -= 1) {
            setResult("cache-expires", "running", "Waiting " + remaining + "s for the 30s TTL to expire…");
            await new Promise((resolve) => setTimeout(resolve, 1000));
          }

          const second = await snapshot(url);
          assertOk(second);
          if (first.body === second.body) {
            throw new Error("same origin response was still served after " + waitSeconds + "s (" + (first.data?.originRequestId || "unknown id") + ")");
          }
          return "origin response changed after " + waitSeconds + "s (" + (first.data?.originRequestId || "unknown") + " → " + (second.data?.originRequestId || "unknown") + ")";
        }));
        complete += 1;
        updateSummary(passed, complete);

        runButton.disabled = false;
      }

      runButton.addEventListener("click", runTests);
      runTests();
    </script>
  `);
}

function renderUatPage() {
  return renderLayout("CDN Cache UAT", `
    <p class="eyebrow">Guided acceptance test</p>
    <h1>CDN Cache UAT</h1>
    <p>This wizard verifies CDN enablement, purging, and disabling through both the dashboard and Wasmer CLI.</p>
    <ol class="progress" id="uat-progress">
      <li class="active">Initial state</li>
      <li>Dashboard enable</li>
      <li>Dashboard purge</li>
      <li>Dashboard disable</li>
      <li>CLI enable</li>
      <li>CLI purge</li>
      <li>CLI disable</li>
    </ol>
    <section class="wizard" id="uat-step" aria-live="polite"></section>
    <p><a class="back" href="/">Back to routes</a></p>
    <script>
      const stepElement = document.querySelector("#uat-step");
      const progressItems = [...document.querySelectorAll("#uat-progress li")];
      const propagationAttempts = 12;
      const propagationDelayMs = 1500;
      let uiCache = null;
      let cliCache = null;

      function probeKey(prefix) {
        return prefix + "-" + crypto.randomUUID();
      }

      async function probe(key) {
        const response = await fetch("/uat-data?key=" + encodeURIComponent(key), {
          credentials: "omit",
          headers: { accept: "application/json" },
          redirect: "manual"
        });
        const result = await response.json();
        if (!response.ok || !result.originRequestId) {
          throw new Error(result.error || "Probe request failed with HTTP " + response.status);
        }
        return result;
      }

      function setProgress(index) {
        progressItems.forEach((item, itemIndex) => {
          item.className = itemIndex < index ? "done" : itemIndex === index ? "active" : "";
        });
      }

      function showChecking(title, detail) {
        stepElement.innerHTML = '<div class="wizard-status running"><span class="spinner" aria-hidden="true"></span><div><h2>' + title + '</h2><p>' + detail + '</p></div></div>';
        stepElement.setAttribute("aria-busy", "true");
      }

      function showError(message, retry) {
        stepElement.setAttribute("aria-busy", "false");
        stepElement.innerHTML = '<div class="notice error"><h2>Check failed</h2><p></p></div><button class="button" type="button">Retry check</button>';
        stepElement.querySelector(".notice p").textContent = message;
        stepElement.querySelector("button").addEventListener("click", retry);
      }

      function showAction(title, instructions, buttonLabel, onConfirm, command = "") {
        stepElement.setAttribute("aria-busy", "false");
        stepElement.innerHTML = '<h2></h2><p class="instructions"></p>' + (command ? '<pre><code></code></pre>' : '') + '<button class="button" type="button"></button>';
        stepElement.querySelector("h2").textContent = title;
        stepElement.querySelector(".instructions").textContent = instructions;
        if (command) stepElement.querySelector("code").textContent = command;
        const button = stepElement.querySelector("button");
        button.textContent = buttonLabel;
        button.addEventListener("click", onConfirm);
      }

      async function expectUncached(key, onAttempt) {
        let previous = null;

        for (let attempt = 1; attempt <= propagationAttempts; attempt += 1) {
          onAttempt(attempt, propagationAttempts);
          const current = await probe(key);
          if (previous && previous.originRequestId !== current.originRequestId) {
            return current;
          }
          previous = current;
          if (attempt < propagationAttempts) {
            await new Promise((resolve) => setTimeout(resolve, propagationDelayMs));
          }
        }

        throw new Error("No uncached response was observed after " + propagationAttempts + " attempts. CDN disablement may still be propagating; wait a moment and retry.");
      }

      async function expectCached(key, onAttempt) {
        let previous = null;

        for (let attempt = 1; attempt <= propagationAttempts; attempt += 1) {
          onAttempt(attempt, propagationAttempts);
          const current = await probe(key);
          if (previous && previous.originRequestId === current.originRequestId) {
            return current;
          }
          previous = current;
          if (attempt < propagationAttempts) {
            await new Promise((resolve) => setTimeout(resolve, propagationDelayMs));
          }
        }

        throw new Error("No cached response was observed after " + propagationAttempts + " attempts. CDN enablement may still be propagating; wait a moment and retry.");
      }

      async function checkInitialState() {
                  setProgress(0);
                  showChecking("Checking initial state", "Confirming responses are not cached before the UAT begins…");
                  try {
                    await expectUncached(probeKey("initial"), (attempt, total) => {
                      showChecking("Checking initial state", "Attempt " + attempt + "/" + total + ": confirming repeated requests reach the origin…");
                    });
          showAction(
            "Enable CDN Cache in the dashboard",
            "Open this app in the Wasmer dashboard, go to App Settings → CDN Cache, and enable CDN Cache.",
            "I enabled CDN Cache",
            checkUiEnabled
          );
        } catch (error) {
          showError(error.message, checkInitialState);
        }
      }

      async function checkUiEnabled() {
        setProgress(1);
        showChecking("Checking dashboard enablement", "Priming a long-lived response, then requesting it again…");
                  try {
                    const key = probeKey("ui-cache");
                    uiCache = { key, response: await expectCached(key, (attempt, total) => {
                      showChecking("Checking dashboard enablement", "Attempt " + attempt + "/" + total + ": priming and checking the same long-lived response…");
                    }) };
          setProgress(2);
          showAction(
            "Purge the cache in the dashboard",
            "A 24-hour response is now cached. In App Settings → CDN Cache, purge the cache, then continue.",
            "I purged the cache",
            checkUiPurged
          );
        } catch (error) {
          showError(error.message, checkUiEnabled);
        }
      }

      async function checkUiPurged() {
        showChecking("Checking dashboard purge", "Requesting the previously primed cache key…");
        try {
          const response = await probe(uiCache.key);
          if (response.originRequestId === uiCache.response.originRequestId) {
            throw new Error("The previously cached origin response was returned. The dashboard purge has not taken effect.");
          }
          setProgress(3);
          showAction(
            "Disable CDN Cache in the dashboard",
            "Return to App Settings → CDN Cache and disable CDN Cache.",
            "I disabled CDN Cache",
            checkUiDisabled
          );
        } catch (error) {
          showError(error.message, checkUiPurged);
        }
      }

      async function checkUiDisabled() {
                  showChecking("Checking dashboard disablement", "Confirming repeated requests now reach the origin…");
                  try {
                    await expectUncached(probeKey("ui-disabled"), (attempt, total) => {
                      showChecking("Checking dashboard disablement", "Attempt " + attempt + "/" + total + ": confirming repeated requests reach the origin…");
                    });
          setProgress(4);
          showAction(
            "Enable CDN Cache with the CLI",
            "Run this command from the app directory, then continue.",
            "I ran the command",
            checkCliEnabled,
            "wasmer app cdn enable"
          );
        } catch (error) {
          showError(error.message, checkUiDisabled);
        }
      }

      async function checkCliEnabled() {
        showChecking("Checking CLI enablement", "Priming a new 24-hour response, then requesting it again…");
                  try {
                    const key = probeKey("cli-cache");
                    cliCache = { key, response: await expectCached(key, (attempt, total) => {
                      showChecking("Checking CLI enablement", "Attempt " + attempt + "/" + total + ": priming and checking the same long-lived response…");
                    }) };
          setProgress(5);
          showAction(
            "Purge the cache with the CLI",
            "The response has been primed. Run this command from the app directory, then continue.",
            "I ran the command",
            checkCliPurged,
            "wasmer app cdn purge"
          );
        } catch (error) {
          showError(error.message, checkCliEnabled);
        }
      }

      async function checkCliPurged() {
        showChecking("Checking CLI purge", "Requesting the previously primed cache key…");
        try {
          const response = await probe(cliCache.key);
          if (response.originRequestId === cliCache.response.originRequestId) {
            throw new Error("The previously cached origin response was returned. The CLI purge has not taken effect.");
          }
          setProgress(6);
          showAction(
            "Disable CDN Cache with the CLI",
            "Run this final command from the app directory, then continue.",
            "I ran the command",
            checkCliDisabled,
            "wasmer app cdn disable"
          );
        } catch (error) {
          showError(error.message, checkCliPurged);
        }
      }

      async function checkCliDisabled() {
                  showChecking("Checking CLI disablement", "Confirming repeated requests reach the origin again…");
                  try {
                    await expectUncached(probeKey("cli-disabled"), (attempt, total) => {
                      showChecking("Checking CLI disablement", "Attempt " + attempt + "/" + total + ": confirming repeated requests reach the origin…");
                    });
          setProgress(progressItems.length);
          stepElement.setAttribute("aria-busy", "false");
          stepElement.innerHTML = '<div class="notice success"><h2>UAT complete</h2><p>Dashboard and CLI enable, purge, and disable flows all behaved as expected.</p></div><button class="button" type="button">Run UAT again</button>';
          stepElement.querySelector("button").addEventListener("click", checkInitialState);
        } catch (error) {
          showError(error.message, checkCliDisabled);
        }
      }

      checkInitialState();
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
      .running strong::before { display: inline-block; width: .75em; height: .75em; margin-right: .6em; border: 2px solid #47637d; border-top-color: #80bfff; border-radius: 50%; content: ""; animation: spin .8s linear infinite; }
      .pending strong { color: #8997aa; }
      .button { display: inline-block; margin-top: .5rem; padding: .7rem 1rem; border: 0; border-radius: .35rem; background: #2f78db; color: white; font: inherit; text-decoration: none; cursor: pointer; }
      .button:disabled { opacity: .55; cursor: wait; }
      .back { margin-left: 1rem; }
      .secondary { margin-left: .5rem; background: #334155; }
      .progress { display: grid; grid-template-columns: repeat(7, 1fr); gap: .4rem; padding: 0; margin: 2rem 0; list-style: none; counter-reset: uat-step; }
      .progress li { color: #64748b; font-size: .7rem; text-align: center; }
      .progress li::before { display: block; width: 1.6rem; height: 1.6rem; margin: 0 auto .5rem; border: 2px solid #334155; border-radius: 50%; content: counter(uat-step); counter-increment: uat-step; line-height: 1.6rem; }
      .progress .active { color: #80bfff; }
      .progress .active::before { border-color: #80bfff; }
      .progress .done { color: #7de2b8; }
      .progress .done::before { border-color: #7de2b8; content: "✓"; }
      .wizard { min-height: 13rem; padding: 1.5rem; border: 1px solid #303949; border-radius: .5rem; background: #171c26; }
      .wizard h2 { margin-top: 0; }
      .wizard-status { display: flex; align-items: flex-start; gap: 1rem; }
      .spinner { flex: 0 0 auto; width: 1.2rem; height: 1.2rem; margin-top: .2rem; border: 3px solid #47637d; border-top-color: #80bfff; border-radius: 50%; animation: spin .8s linear infinite; }
      .notice { padding: .8rem 1rem; margin-bottom: 1rem; border-left: 3px solid; background: #111620; }
      .notice.error { border-color: #ff8b8b; }
      .notice.success { border-color: #7de2b8; }
      pre { overflow-x: auto; padding: 1rem; border-radius: .35rem; background: #0c1017; }
      @keyframes spin { to { transform: rotate(360deg); } }
      @media (max-width: 700px) { .progress { grid-template-columns: 1fr; } .progress li { text-align: left; } .progress li::before { display: inline-block; margin: 0 .6rem 0 0; text-align: center; } }
      @media (prefers-reduced-motion: reduce) { .running strong::before, .spinner { animation-duration: 1.8s; } }
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
