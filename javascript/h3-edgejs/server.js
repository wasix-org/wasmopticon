import { createServer } from "node:http";
import { H3, readBody, toNodeListener } from "h3";

const app = new H3();
const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";

app.use((event) => {
  event.res.headers.set("X-Fixture", "js-h3");
});
app.get("/", () => "Hello from H3 on Wasmer Edge");
app.get("/json", () => ({ framework: "h3" }));
app.post("/echo", async (event) => ({
  body: await readBody(event),
  probe: event.req.headers.get("x-probe"),
}));
app.all("/**", () => Response.json({ error: "Not Found" }, { status: 404 }));

createServer(toNodeListener(app)).listen(port, host, () => {
  console.log(`H3 server listening on http://${host}:${port}`);
});
