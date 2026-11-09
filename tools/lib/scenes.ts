import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, sep } from "node:path";
import { GODOT_NOISE, godotImport, type StepResult } from "./gate.ts";
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

// Godot's sin, cos and quaternion maths round differently on Windows, Linux and macOS, so a
// rebuild on another OS can change a scene's last float bits without changing the scene.
// tools/gd/scene_equal.gd compares the two as scenes, within a float tolerance.
async function sameScene(godot: string, root: string, a: string, b: string): Promise<boolean> {
	const r = await run(godot, ["--headless", "--path", root, "-s", "res://tools/gd/scene_equal.gd", "--", a, b], { cwd: root, timeoutMs: 120_000 });
	return r.code === 0 && /^SAME$/m.test(r.output);
}

export async function buildScenes(godot: string, root: string): Promise<StepResult & { changed: string[] }> {
	// New class_name scripts are only visible to builders after an import refreshes the class cache.
	const imported = await godotImport(godot, root);
	if (!imported.ok) return { ...imported, changed: [] };
	const before = sceneHashes(root);
	const original = new Map<string, Buffer>([...before.keys()].map((k) => [k, readFileSync(k)]));
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
	const differ = [...after.keys()].filter((k) => before.get(k) !== after.get(k));
	const changed: string[] = [];
	let rounding = 0;
	const work = mkdtempSync(join(tmpdir(), "slopocalypse-scenes-"));
	try {
		for (const k of differ) {
			const old = original.get(k);
			if (old !== undefined) {
				const copy = join(work, `old-${rounding + changed.length}.tscn`);
				writeFileSync(copy, old);
				if (await sameScene(godot, root, k, copy)) {
					// Only float rounding: keep the committed bytes so nothing shows as modified.
					writeFileSync(k, old);
					rounding++;
					continue;
				}
			}
			changed.push(relative(root, k));
		}
	} finally {
		rmSync(work, { recursive: true, force: true });
	}
	const note = rounding > 0 ? `, ${rounding} equal within float rounding` : "";
	return { ok: true, detail: `${builders.length} builder(s)${note}`, changed };
}
