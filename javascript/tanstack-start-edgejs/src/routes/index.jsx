import { createFileRoute } from "@tanstack/react-router";
import { createServerFn } from "@tanstack/react-start";
import { getRequestHeader } from "@tanstack/react-start/server";

const greet = createServerFn()
  .validator((name) => typeof name === "string" ? name : "world")
  .handler(async ({ data }) => data);

export const submitMessage = createServerFn({ method: "POST" })
  .validator((form) => {
    const message = form instanceof FormData ? form.get("message") : null;
    return typeof message === "string" ? message : "";
  })
  .handler(async ({ data }) => Response.json(
    { message: data, probe: getRequestHeader("X-Probe") ?? null },
    { headers: { "X-Server-Function": "submit-message" } },
  ));

export const Route = createFileRoute("/")({
  validateSearch: (search) => ({ name: search.name }),
  loaderDeps: ({ search }) => ({ name: search.name }),
  loader: ({ deps }) => greet({ data: deps.name }),
  component: Page,
});

function Page() {
  const name = Route.useLoaderData();
  return (
    <main>
      <h1>Hello from TanStack Start on Wasmer Edge</h1>
      <output id="loader-value">{name}</output>
      <form action={submitMessage.url} method="post">
        <label>Message <input name="message" /></label>
        <button type="submit">Submit</button>
      </form>
    </main>
  );
}
