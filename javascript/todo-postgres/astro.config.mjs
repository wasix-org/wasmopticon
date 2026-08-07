import node from "@astrojs/node";
import { defineConfig } from "astro/config";

export default defineConfig({
  output: "server",
  adapter: node({ mode: "standalone" }),
  server: { host: true },
  security: {
    allowedDomains: [
      { hostname: "todo-js-postgres.wasmer.app", protocol: "https" },
    ],
  },
});
