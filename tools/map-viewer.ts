// A local page for looking at and tuning generated maps (#448, #427, #428):
//   node tools/map-viewer.ts [--port=8787]
// then open http://127.0.0.1:8787. Pick a recipe and seed, toggle layers, pan and zoom,
// read the stats, edit the recipe and re-render, save it back. Local only: it binds to
// 127.0.0.1 and can write recipe files.
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { localGodot } from "./lib/godot.ts";
import { cacheKey, parseRender, recipeFile } from "./lib/map-viewer.ts";
import { run } from "./lib/proc.ts";

const root = resolve(import.meta.dirname, "..");
const cache = join(root, "build", "map-viewer");
mkdirSync(cache, { recursive: true });
const portArg = process.argv.find((a) => a.startsWith("--port="));
const port = portArg === undefined ? 8787 : Number(portArg.slice("--port=".length));

// One render at a time: each is a Godot process that fills a core for a few seconds.
let queue: Promise<unknown> = Promise.resolve();

function send(res: ServerResponse, code: number, type: string, body: string | Buffer): void {
	res.writeHead(code, { "content-type": type, "cache-control": "no-store" });
	res.end(body);
}

function body(req: IncomingMessage): Promise<string> {
	return new Promise((ok, fail) => {
		let text = "";
		req.on("data", (d: Buffer) => {
			text += d.toString();
			if (text.length > 1_000_000) fail(new Error("recipe too large"));
		});
		req.on("end", () => ok(text));
		req.on("error", fail);
	});
}

function recipes(): string[] {
	return readdirSync(join(root, "modules/world/data/maps"))
		.filter((f) => f.endsWith(".json"))
		.map((f) => f.slice(0, -5))
		.sort();
}

async function render(params: URLSearchParams, edited: string | undefined): Promise<{ key: string; stats: unknown }> {
	const req = parseRender(params);
	const text = edited ?? readFileSync(join(root, recipeFile(req.map)), "utf8");
	JSON.parse(text);
	const key = cacheKey(req, text);
	const png = join(cache, `${key}.png`);
	const stats = join(cache, `${key}.json`);
	if (!existsSync(png) || !existsSync(stats)) {
		const recipePath = join(cache, `${key}.recipe.json`);
		writeFileSync(recipePath, text);
		const job = queue.then(() =>
			run(localGodot(root), ["--headless", "--path", root, "-s", "res://tools/gd/map_preview.gd", "--", recipePath, String(req.seed), png, String(req.pixels), req.layers.join(","), stats], { cwd: root, timeoutMs: 300_000 }),
		);
		queue = job.catch(() => undefined);
		const r = await job;
		if (r.code !== 0 || r.timedOut || !existsSync(png)) throw new Error(`render failed:\n${r.output.slice(-2000)}`);
	}
	return { key, stats: JSON.parse(readFileSync(stats, "utf8")) };
}

const server = createServer((req, res) => {
	const url = new URL(req.url ?? "/", "http://127.0.0.1");
	const handle = async (): Promise<void> => {
		if (req.method === "GET" && url.pathname === "/") {
			return send(res, 200, "text/html; charset=utf-8", readFileSync(join(root, "tools/map-viewer/index.html")));
		}
		if (url.pathname === "/favicon.ico") return send(res, 204, "text/plain", "");
		if (req.method === "GET" && url.pathname === "/recipes") return send(res, 200, "application/json", JSON.stringify(recipes()));
		if (url.pathname === "/recipe") {
			const map = parseRender(url.searchParams).map;
			if (req.method === "GET") return send(res, 200, "application/json", readFileSync(join(root, recipeFile(map))));
			if (req.method === "POST") {
				const text = await body(req);
				JSON.parse(text);
				writeFileSync(join(root, recipeFile(map)), text.endsWith("\n") ? text : `${text}\n`);
				return send(res, 200, "application/json", '{"saved":true}');
			}
		}
		if (url.pathname === "/render" && (req.method === "GET" || req.method === "POST")) {
			const edited = req.method === "POST" ? await body(req) : undefined;
			const out = await render(url.searchParams, edited);
			return send(res, 200, "application/json", JSON.stringify({ image: `/image/${out.key}.png`, stats: out.stats }));
		}
		const image = /^\/image\/([A-Za-z0-9+_.-]+\.png)$/.exec(url.pathname);
		if (req.method === "GET" && image !== null) {
			const file = join(cache, image[1] ?? "");
			if (existsSync(file)) return send(res, 200, "image/png", readFileSync(file));
		}
		send(res, 404, "text/plain", "not found");
	};
	handle().catch((err: unknown) => send(res, 400, "text/plain", err instanceof Error ? err.message : String(err)));
});

server.listen(port, "127.0.0.1", () => {
	process.stdout.write(`map viewer on http://127.0.0.1:${port}\n`);
});
