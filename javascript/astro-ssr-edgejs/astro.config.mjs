import node from "@astrojs/node";
import { defineConfig } from "astro/config";

export default defineConfig({
  adapter: node({
    mode: "standalone",
  }),
  output: "server",
  security: {
    allowedDomains: [{ protocol: "http", hostname: "127.0.0.1" }],
  },
});
