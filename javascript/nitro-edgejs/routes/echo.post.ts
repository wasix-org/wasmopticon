export default defineEventHandler(async (event) => ({
  body: await readBody(event),
  probe: getHeader(event, "x-probe"),
}));
