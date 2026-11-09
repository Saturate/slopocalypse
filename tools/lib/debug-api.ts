// Finding and calling running games' debug APIs (modules/debug_api). Each game started with
// --debug-api writes user://debug/api-<pid>.json with its port and token.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export const APP_NAME = "Slopocalypse";

export interface Game {
	pid: number;
	role: string;
	port: number;
	token: string;
	log: string;
	file: string;
}

// Godot's user:// for this project (no custom user dir), per OS.
export function godotUserDir(os: string, env: Readonly<Record<string, string | undefined>>, home: string): string {
	if (os === "win32") return join(env["APPDATA"] ?? join(home, "AppData", "Roaming"), "Godot", "app_userdata", APP_NAME);
	if (os === "darwin") return join(home, "Library", "Application Support", "Godot", "app_userdata", APP_NAME);
	return join(env["XDG_DATA_HOME"] ?? join(home, ".local", "share"), "godot", "app_userdata", APP_NAME);
}

export function parseApiFile(text: string, file: string): Game | undefined {
	let data: unknown;
	try {
		data = JSON.parse(text);
	} catch {
		return undefined;
	}
	if (typeof data !== "object" || data === null) return undefined;
	const pid = Reflect.get(data, "pid");
	const port = Reflect.get(data, "port");
	const token = Reflect.get(data, "token");
	const role = Reflect.get(data, "role");
	const log = Reflect.get(data, "log");
	if (typeof pid !== "number" || typeof port !== "number" || typeof token !== "string") return undefined;
	return { pid, port, token, role: typeof role === "string" ? role : "unknown", log: typeof log === "string" ? log : "", file };
}

export function discover(userDir: string): Game[] {
	const dir = join(userDir, "debug");
	if (!existsSync(dir)) return [];
	const games: Game[] = [];
	for (const name of readdirSync(dir)) {
		if (!/^api-\d+\.json$/.test(name)) continue;
		const file = join(dir, name);
		const game = parseApiFile(readFileSync(file, "utf8"), file);
		if (game !== undefined) games.push(game);
	}
	return games.sort((a, b) => a.pid - b.pid);
}

// `target` is a pid or a role ("client", "server"); with none, the client if there is one.
export function pickTarget(games: readonly Game[], target: string | number | undefined): Game | undefined {
	if (target === undefined || target === "") return games.find((g) => g.role === "client") ?? games[0];
	const pid = typeof target === "number" ? target : /^\d+$/.test(target) ? Number(target) : undefined;
	if (pid !== undefined) return games.find((g) => g.pid === pid);
	return games.find((g) => g.role === target);
}

export class ApiError extends Error {}

export async function rpc(game: Game, method: string, params: Record<string, unknown> = {}, timeoutMs = 5000): Promise<unknown> {
	const res = await fetch(`http://127.0.0.1:${game.port}/rpc`, {
		method: "POST",
		headers: { Authorization: `Bearer ${game.token}`, "Content-Type": "application/json" },
		body: JSON.stringify({ method, params }),
		signal: AbortSignal.timeout(timeoutMs),
	});
	const body: unknown = await res.json();
	if (typeof body !== "object" || body === null) throw new ApiError(`bad reply from pid ${game.pid}`);
	const error = Reflect.get(body, "error");
	if (typeof error === "string") throw new ApiError(error);
	return Reflect.get(body, "result");
}
