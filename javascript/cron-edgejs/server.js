import { appendFileSync } from "node:fs";
import { serve } from "@hono/node-server";
import { Hono } from "hono";

const app = new Hono();
const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";
const file = "/state/ticks.jsonl";
const intervalMs = 200;
let count = 0;

function record(event) {
  appendFileSync(file, JSON.stringify({ event, count, ms: Date.now() }) + "\n");
}

record("start");
const timer = setInterval(() => {
  count += 1;
  record("tick");
}, intervalMs);

app.get("/", (context) => context.json({ fixture: "cron-edgejs", intervalMs }));
app.post("/shutdown", (context) => {
  clearInterval(timer);
  record("stop");
  // Give the adapter a turn to send the response before closing the listener.
  setTimeout(() => server.close(), 0);
  return context.json({ stopped: true, count });
});

const server = serve({ fetch: app.fetch, port, hostname: host });
