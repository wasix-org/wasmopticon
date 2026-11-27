export function GET() {
  return Response.json({ framework: "solidstart" }, {
    headers: { "X-Fixture": "solidstart" },
  });
}
