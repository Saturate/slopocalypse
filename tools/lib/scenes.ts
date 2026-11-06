import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { GODOT_NOISE, type StepResult } from "./gate.ts";
import { scanLog } from "./log-scan.ts";
import { run } from "./proc.ts";

// Builders live in modules/<id>/builders/*.gd and run in file-name order within a module,
// so a numeric prefix (10_, 20_) puts leaf scenes before the scenes that instance them.
export function findBuilders(root: string): string[] {
	const modulesDir = join(root, "modules");
	if (!existsSync(modulesDir)) return [];
	const found: string[] = [];
	for (const mod of readdirSync(modulesDir).sort()) {
		const dir = join(modulesDir, mod, "builders");
		if (!existsSync(dir)) continue;
		for (const f of readdirSync(dir).sort()) {
			if (f.endsWith(".gd")) found.push(join(dir, f));
		}
	}
	return found;
}

function sceneHashes(root: string): Map<string, string> {
	const out = new Map<string, string>();
	const walk = (dir: string): void => {
		for (const name of readdirSync(dir, { withFileTypes: true })) {
			if (name.name.startsWith(".") || ["node_modules", "target", "tools", "addons"].includes(name.name)) continue;
			const full = join(dir, name.name);
			if (name.isDirectory()) walk(full);
			else if (name.name.endsWith(".tscn")) out.set(full, createHash("sha1").update(readFileSync(full)).digest("hex"));
		}
	};
	walk(root);
	return out;
}

export async function buildScenes(godot: string, root: string): Promise<StepResult & { changed: string[] }> {
	const before = sceneHashes(root);
	const builders = findBuilders(root);
	for (const b of builders) {
		const res = "res://" + relative(root, b).split(sep).join("/");
		const r = await run(godot, ["--headless", "--path", root, "-s", res], { cwd: root, timeoutMs: 120_000 });
		const problems = scanLog(r.output, GODOT_NOISE);
		if (r.code !== 0 || r.timedOut || problems.length > 0) {
			return { ok: false, detail: [`${relative(root, b)} failed (exit ${r.code})`, ...problems].join("\n"), changed: [] };
		}
	}
	const after = sceneHashes(root);
	const changed = [...after.keys()].filter((k) => before.get(k) !== after.get(k)).map((k) => relative(root, k));
	return { ok: true, detail: `${builders.length} builder(s)`, changed };
}
