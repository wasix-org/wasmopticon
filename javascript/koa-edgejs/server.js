import Koa from "koa";

const app = new Koa();
const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";

app.use(async (ctx) => {
  ctx.set("X-Fixture", "js-koa");

  if (ctx.method === "GET" && ctx.path === "/") {
    ctx.type = "text/plain";
    ctx.body = "Hello from Koa on Wasmer Edge";
  } else if (ctx.method === "GET" && ctx.path === "/json") {
    ctx.body = { framework: "koa" };
  } else if (ctx.method === "POST" && ctx.path === "/echo") {
    try {
      const chunks = [];
      for await (const chunk of ctx.req) chunks.push(chunk);
      ctx.body = { body: JSON.parse(Buffer.concat(chunks)), probe: ctx.get("X-Probe") };
    } catch (error) {
      if (!(error instanceof SyntaxError)) throw error;
      ctx.throw(400, "Invalid JSON");
    }
  } else {
    ctx.status = 404;
    ctx.body = { error: "Not Found" };
  }
});

app.listen(port, host, () => {
  console.log(`Koa server listening on http://${host}:${port}`);
});
