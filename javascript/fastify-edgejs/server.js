import Fastify from "fastify";

const app = Fastify();
const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";

app.addHook("onRequest", async (_request, reply) => {
  reply.header("X-Fixture", "js-fastify");
});

app.get("/", async () => "Hello from Fastify on Wasmer Edge");
app.get("/json", async () => ({ framework: "fastify" }));
app.post("/echo", async (request) => ({
  body: request.body,
  probe: request.headers["x-probe"],
}));
app.setNotFoundHandler((_request, reply) => {
  reply.code(404).send({ error: "Not Found" });
});

await app.listen({ host, port });
console.log(`Fastify server listening on http://${host}:${port}`);
