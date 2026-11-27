import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  generateBuildId: async () => "wasmopticon-next-ssr",
};

export default nextConfig;
