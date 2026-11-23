// The server's admin app (#448): built into modules/web/static, which the game server
// serves under /admin/app behind its password. `npm run dev -w web` serves it locally and
// sends /api to a running server (SLOP_API, default http://127.0.0.1:7777).
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
	plugins: [react()],
	base: "/admin/app/",
	build: {
		outDir: "../modules/web/static",
		emptyOutDir: true,
		// One small app: plain names keep the server's file list obvious.
		rollupOptions: { output: { entryFileNames: "app.js", chunkFileNames: "[name].js", assetFileNames: "[name][extname]" } },
	},
	server: {
		proxy: { "/api": process.env["SLOP_API"] ?? "http://127.0.0.1:7777" },
	},
});
