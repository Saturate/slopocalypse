// Pure parts of tools/map-preview.ts: reading its arguments.

export type PreviewArgs = { map: string; seed: number; out: string; pixels: number };

export function parsePreviewArgs(argv: string[]): PreviewArgs {
	const value = (name: string): string | undefined => {
		const hit = argv.find((a) => a.startsWith(`--${name}=`));
		return hit === undefined ? undefined : hit.slice(name.length + 3);
	};
	const map = value("map") ?? "grassland";
	if (!/^[a-z0-9_-]+$/.test(map)) throw new Error(`--map must be a recipe name like grassland, not ${map}`);
	const seed = Number(value("seed") ?? "1");
	if (!Number.isInteger(seed)) throw new Error("--seed must be a whole number");
	const pixels = Number(value("pixels") ?? "512");
	if (!Number.isInteger(pixels) || pixels < 16 || pixels > 4096) throw new Error("--pixels must be 16 to 4096");
	const out = value("out") ?? `build/maps/${map}-${seed}.png`;
	return { map, seed, out, pixels };
}

export function recipePath(map: string): string {
	return `res://modules/world/data/maps/${map}.json`;
}
