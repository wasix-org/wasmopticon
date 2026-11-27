export default defineEventHandler((event) => {
  setResponseStatus(event, 404);
  return { error: "Not Found" };
});
