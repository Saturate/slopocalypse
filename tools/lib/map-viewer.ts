// Pure parts of tools/map-viewer.ts: reading a render request and naming its cache entry.

export const LAYERS = ["zones", "settlements", "roads", "earthworks", "sites", "remoteness"] as const;
export type Layer = (typeof LAYERS)[number];
// Drawn when a request names none: everything but the remoteness tint, which hides the land.
export const DEFAULT_LAYERS: readonly Layer[] = ["zones", "settlements", "roads", "earthworks", "sites"];

export type RenderRequest = { map: string; seed: number; pixels: number; layers: Layer[] };

function isLayer(v: string): v is Layer {
	return (LAYERS as readonly string[]).includes(v);
}

// `map` must be a recipe name, never a path: it picks a file under the world module.
export function parseRender(params: URLSearchParams): RenderRequest {
	const map = params.get("map") ?? "grassland";
	if (!/^[a-z0-9_-]+$/.test(map)) throw new Error(`map must be a recipe name, not ${map}`);
	const seed = Number(params.get("seed") ?? "1");
	if (!Number.isInteger(seed) || seed < 0 || seed > 2_147_483_647) throw new Error("seed must be a whole number from 0");
	const pixels = Number(params.get("pixels") ?? "512");
	if (!Number.isInteger(pixels) || pixels < 64 || pixels > 2048) throw new Error("pixels must be 64 to 2048");
	const asked = (params.get("layers") ?? DEFAULT_LAYERS.join(",")).split(",").filter((l) => l !== "");
	const layers: Layer[] = [];
	for (const l of asked) {
		if (!isLayer(l)) throw new Error(`unknown layer ${l}`);
		if (!layers.includes(l)) layers.push(l);
	}
	return { map, seed, pixels, layers };
}

// Same request and same recipe text give the same key, so an edited recipe renders afresh.
export function cacheKey(req: RenderRequest, recipeText: string): string {
	let h = 2166136261;
	for (const ch of recipeText) {
		h ^= ch.codePointAt(0) ?? 0;
		h = Math.imul(h, 16777619) >>> 0;
	}
	return `${req.map}-${req.seed}-${req.pixels}-${[...req.layers].sort().join("+")}-${h.toString(16)}`;
}

export function recipeFile(map: string): string {
	return `modules/world/data/maps/${map}.json`;
}
