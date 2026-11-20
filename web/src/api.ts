// The server's API (modules/web/api/openapi.yaml): types generated from the spec, and
// guards that check what came over the wire before the app uses it.
import type { components } from "./schema.d.ts";

export type Status = components["schemas"]["Status"];
export type Mission = components["schemas"]["Mission"];

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

// GETs `path` and checks the answer with `guard`; throws when it is not what the spec says.
export async function get<T>(path: string, guard: (v: unknown) => v is T): Promise<T> {
	// Against the origin, never the page's own URL: a URL carrying user:password (pasted to
	// log in) makes the browser refuse relative requests.
	const res = await fetch(new URL(path, window.location.origin), { headers: { accept: "application/json" } });
	if (!res.ok) throw new Error(`${path}: ${res.status} ${res.statusText}`);
	const body: unknown = await res.json();
	if (!guard(body)) throw new Error(`${path}: not the shape the API describes`);
	return body;
}
