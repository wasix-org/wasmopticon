import { createServer } from "node:http";
import { Form, Outlet, RemixServer, useActionData, useLoaderData } from "@remix-run/react";
import { createRequestHandler, json } from "@remix-run/server-runtime";
import React from "react";
import { renderToString } from "react-dom/server";

const h = React.createElement;

function Page() {
  const { name } = useLoaderData();
  const action = useActionData();
  return h("main", null,
    h("h1", null, "Hello from Remix on Wasmer Edge"),
    h("output", { id: "loader-value" }, name),
    h(Form, { method: "post" },
      h("label", null, "Message ", h("input", { name: "message" })),
      h("button", { type: "submit" }, "Submit"),
    ),
    action && h("output", { id: "action-value" }, action.message),
  );
}

const routes = {
  root: { id: "root", path: "", module: { default: Outlet } },
  home: {
    id: "home",
    parentId: "root",
    index: true,
    module: {
      default: Page,
      loader: ({ request }) => json({ name: new URL(request.url).searchParams.get("name") ?? "world" }),
      action: async ({ request }) => json({ message: (await request.formData()).get("message") }),
    },
  },
  json: {
    id: "json",
    parentId: "root",
    path: "json",
    module: {
      loader: ({ request }) => json({
        value: new URL(request.url).searchParams.get("value"),
        probe: request.headers.get("X-Probe"),
      }),
    },
  },
  missing: {
    id: "missing",
    parentId: "root",
    path: "*",
    module: {
      default: () => h("h1", null, "Not Found"),
      loader: () => json(null, { status: 404 }),
    },
  },
};

// The fixture renders documents and resource routes directly, with no client bundle.
const assetRoutes = Object.fromEntries(Object.values(routes).map(({ module, ...route }) => [
  route.id,
  { ...route, imports: [], hasLoader: Boolean(module.loader), hasAction: Boolean(module.action) },
]));
const handle = createRequestHandler({
  routes,
  assets: { routes: assetRoutes },
  future: {},
  isSpaMode: false,
  entry: {
    module: {
      default(request, status, headers, context) {
        headers.set("Content-Type", "text/html; charset=utf-8");
        const html = renderToString(h(RemixServer, { context, url: request.url }));
        return new Response(`<!doctype html><html lang="en"><body>${html}</body></html>`, {
          status,
          headers,
        });
      },
    },
  },
}, "production");

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
      "X-Fixture": "js-remix-ssr",
    });
    outgoing.end(body);
  } catch (error) {
    console.error(error);
    outgoing.writeHead(500);
    outgoing.end("Internal Server Error");
  }
}).listen(port, host, () => {
  console.log(`Remix server listening on http://${host}:${port}`);
});
