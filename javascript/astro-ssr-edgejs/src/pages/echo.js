function result(message) {
  return Response.json({ message }, { headers: { "X-Fixture": "astro-ssr" } });
}

export function GET() {
  return result("Rendered by Astro on Node.");
}

export async function POST({ request }) {
  const form = await request.formData();
  return result(form.get("message"));
}
