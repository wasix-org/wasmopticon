import { serve } from "@hono/node-server";
import { Hono } from "hono";

const app = new Hono();
const port = Number(process.env.PORT || 8080);
const host = process.env.HONO_HOST || "127.0.0.1";

app.get("/", (context) => {
  return context.text("Hello from Hono on Wasmer Edge");
});

app.post("/echo", async (context) => {
  const { message } = await context.req.json();
  return context.json({ message });
});

serve(
  {
    fetch: app.fetch,
    hostname: host,
    port,
  },
  (info) => {
    console.log(`Hono server listening on http://${host}:${info.port}`);
  },
);
