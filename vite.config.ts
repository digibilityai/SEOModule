/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";

export default defineConfig({
  base: "/",
  server: {
    host: "::",
    port: 8090,
  },
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  test: {
    environment: "node",
    // The second pattern covers the server-side machine boundary
    // (supabase/functions/seo-module-api). Those files import nothing from
    // src/, so they cannot reach the browser service-adapter or mock layer;
    // they live outside src/ for that reason and still need to be tested.
    include: ["src/**/*.test.ts", "supabase/functions/**/*.test.ts"],
  },
});
