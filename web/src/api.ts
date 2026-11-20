// The server's API (modules/web/api/openapi.yaml): types generated from the spec, and
// guards that check what came over the wire before the app uses it.
import type { components } from "./schema.d.ts";

export type Status = components["schemas"]["Status"];
export type Mission = components["schemas"]["Mission"];
export type MapList = components["schemas"]["MapList"];
export type RenderRequest = components["schemas"]["RenderRequest"];
export type RenderResult = components["schemas"]["RenderResult"];
export type Grid = components["schemas"]["Grid"];
export type Region = components["schemas"]["Region"];
export type Layer = NonNullable<RenderRequest["layers"]>[number];
export const LAYERS: readonly Layer[] = ["zones", "settlements", "roads", "earthworks", "sites", "remoteness"];
// Drawn unless switched off; the rest (the remoteness tint) only when asked for.
export const DEFAULT_LAYERS: readonly Layer[] = ["zones", "settlements", "roads", "earthworks", "sites"];

function isRecord(v: unknown): v is Record<string, unknown> {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isMission(v: unknown): v is Mission {
	return isRecord(v) && typeof v["codename"] === "string" && typeof v["kind"] === "string" && typeof v["place"] === "string" && typeof v["pays"] === "number";
}

export function isStatus(v: unknown): v is Status {
	if (!isRecord(v)) return false;
	const players = v["players"];
	const board = v["board"];
	const mission = v["mission"];
	return (
		typeof v["name"] === "string" &&
		typeof v["version"] === "string" &&
		typeof v["uptime_seconds"] === "number" &&
		Array.isArray(players) &&
		players.every((p) => typeof p === "string") &&
		typeof v["soldiers_alive"] === "number" &&
		(board === undefined || (Array.isArray(board) && board.every(isMission))) &&
		(mission === undefined || mission === null || isMission(mission))
	);
}

function isNumbers(v: unknown): v is number[] {
	return Array.isArray(v) && v.every((n) => typeof n === "number");
}

export function isMapList(v: unknown): v is MapList {
	return isRecord(v) && Array.isArray(v["maps"]) && v["maps"].every((m) => typeof m === "string");
}

function isGrid(v: unknown): v is Grid {
	const kinds = isRecord(v) ? v["kinds"] : undefined;
	return (
		isRecord(v) &&
		typeof v["left"] === "number" &&
		typeof v["top"] === "number" &&
		typeof v["size"] === "number" &&
		typeof v["cells"] === "number" &&
		isNumbers(v["heights"]) &&
		isNumbers(v["zones"]) &&
		Array.isArray(kinds) &&
		kinds.every((k) => typeof k === "string")
	);
}

function isRegion(v: unknown): v is Region {
	return isRecord(v) && typeof v["left"] === "number" && typeof v["top"] === "number" && typeof v["size"] === "number";
}

export function isRenderResult(v: unknown): v is RenderResult {
	if (!isRecord(v) || typeof v["image"] !== "string" || !isRegion(v["region"])) return false;
	const stats = v["stats"];
	if (!isRecord(stats) || !isGrid(stats["grid"])) return false;
	const summary = stats["summary"];
	return isRecord(summary) && Object.values(summary).every((x) => typeof x === "string" || typeof x === "number");
}

export function isRecipe(v: unknown): v is Record<string, unknown> {
	return isRecord(v);
}

// The error an API answer carries, or its status line.
async function failure(path: string, res: Response): Promise<Error> {
	const text = await res.text();
	try {
		const body: unknown = JSON.parse(text);
		if (isRecord(body) && typeof body["error"] === "string") return new Error(body["error"]);
	} catch {
		// Not JSON: the status says enough.
	}
	return new Error(`${path}: ${res.status} ${res.statusText}`);
}

// POSTs `body` as JSON to `path` and checks the answer with `guard`.
export async function post<T>(path: string, body: unknown, guard: (v: unknown) => v is T, signal?: AbortSignal): Promise<T> {
	const res = await fetch(new URL(path, window.location.origin), {
		method: "POST",
		signal: signal ?? null,
		headers: { "content-type": "application/json", accept: "application/json" },
		body: JSON.stringify(body),
	});
	if (!res.ok) throw await failure(path, res);
	const answer: unknown = await res.json();
	if (!guard(answer)) throw new Error(`${path}: not the shape the API describes`);
	return answer;
}

// GETs `path` and checks the answer with `guard`; throws when it is not what the spec says.
export async function get<T>(path: string, guard: (v: unknown) => v is T): Promise<T> {
	// Against the origin, never the page's own URL: a URL carrying user:password (pasted to
	// log in) makes the browser refuse relative requests.
	const res = await fetch(new URL(path, window.location.origin), { headers: { accept: "application/json" } });
	if (!res.ok) throw await failure(path, res);
	const body: unknown = await res.json();
	if (!guard(body)) throw new Error(`${path}: not the shape the API describes`);
	return body;
}
