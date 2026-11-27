import { node } from "@elysia/node";
import { Elysia } from "elysia";

const port = Number(process.env.PORT || 8080);
const hostname = process.env.HOST || "127.0.0.1";

new Elysia({ adapter: node() })
  .onRequest(({ set }) => {
    set.headers["x-fixture"] = "js-elysia";
  })
  .onError(({ code, status }) => {
    if (code === "NOT_FOUND") return status(404, { error: "Not Found" });
  })
  .get("/", () => "Hello from Elysia on Wasmer Edge")
  .get("/json", () => ({ framework: "elysia" }))
  .post("/echo", ({ body, headers }) => ({ body, probe: headers["x-probe"] }))
  .listen({ hostname, port }, () => {
    console.log(`Elysia server listening on http://${hostname}:${port}`);
  });
