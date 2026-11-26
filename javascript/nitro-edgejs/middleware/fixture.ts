export default defineEventHandler((event) => {
  setHeader(event, "X-Fixture", "js-nitro");
});
