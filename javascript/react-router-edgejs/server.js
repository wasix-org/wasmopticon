import { createServer } from "node:http";
import React from "react";
import { renderToString } from "react-dom/server";
import {
  createStaticHandler,
  createStaticRouter,
  Form,
  StaticRouterProvider,
  useActionData,
  useLoaderData,
} from "react-router";

const h = React.createElement;

function Page() {
  const { name } = useLoaderData();
  const action = useActionData();
  return h("main", null,
    h("h1", null, "Hello from React Router on Wasmer Edge"),
    h("output", { id: "loader-value" }, name),
    h(Form, { method: "post" },
      h("label", null, "Message ", h("input", { name: "message" })),
      h("button", { type: "submit" }, "Submit"),
    ),
    action && h("output", { id: "action-value" }, action.message),
  );
}

const handler = createStaticHandler([
  {
    id: "home",
    path: "/",
    Component: Page,
    loader: ({ request }) => ({ name: new URL(request.url).searchParams.get("name") ?? "world" }),
    action: async ({ request }) => ({ message: (await request.formData()).get("message") }),
  },
  {
    id: "json",
    path: "/json",
    loader: ({ request }) => Response.json({
      value: new URL(request.url).searchParams.get("value"),
      probe: request.headers.get("X-Probe"),
    }),
  },
  {
    id: "missing",
    path: "*",
    Component: () => h("h1", null, "Not Found"),
    loader: () => new Response(null, { status: 404 }),
  },
]);

async function handle(request) {
  if (new URL(request.url).pathname === "/json") {
    return handler.queryRoute(request, { routeId: "json" });
  }
  const context = await handler.query(request);
  if (context instanceof Response) return context;
  const router = createStaticRouter(handler.dataRoutes, context);
  const html = renderToString(h(StaticRouterProvider, { router, context, hydrate: false }));
  return new Response(`<!doctype html><html lang="en"><body>${html}</body></html>`, {
    status: context.statusCode,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || "127.0.0.1";
createServer(async (incoming, outgoing) => {
  try {
    const headers = new Headers();
    for (const [name, value] of Object.entries(incoming.headers)) headers.set(name, value);
    const chunks = [];
    if (incoming.method === "POST") {
      for await (const chunk of incoming) chunks.push(chunk);
    }
    const request = new Request(new URL(incoming.url, `http://localhost:${port}`), {
      method: incoming.method,
      headers,
      body: chunks.length ? Buffer.concat(chunks) : undefined,
    });
    const response = await handle(request);
    const body = Buffer.from(await response.arrayBuffer());
    outgoing.writeHead(response.status, {
      ...Object.fromEntries(response.headers),
      "X-Fixture": "js-react-router",
    });
    outgoing.end(body);
  } catch (error) {
    console.error(error);
    outgoing.writeHead(500);
    outgoing.end("Internal Server Error");
  }
}).listen(port, host, () => {
  console.log(`React Router server listening on http://${host}:${port}`);
});
