// "A module owns everything that names it" (docs/decisions/0019): its playtests, the debug
// calls it allows and the player settings it registers live in modules/<id>/, so deleting the
// folder removes them. This finds the three ways that rule has been broken before: a scenario
// outside its module, a central list of another module's debug calls, and a module's setting
// key spelled out in core. Narrow on purpose: EventBus topics and public APIs that name a
// module are how modules talk and are not checked.
import { existsSync, lstatSync, readdirSync, readFileSync } from "node:fs";
import { join, sep } from "node:path";

export interface ModuleClaims {
	id: string;
	debugCalls: string[];
	settings: string[];
}

const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);

export function parseClaims(id: string, manifest: unknown): ModuleClaims {
	const get = (k: string): unknown => (typeof manifest === "object" && manifest !== null ? Reflect.get(manifest, k) : undefined);
	const settingsRaw = get("settings");
	const settings = Array.isArray(settingsRaw)
		? settingsRaw.map((s: unknown) => (typeof s === "object" && s !== null ? Reflect.get(s, "key") : undefined)).filter((k): k is string => typeof k === "string")
		: [];
	return { id, debugCalls: strings(get("debug_calls")), settings };
}

const SCENARIO = /^export\s+default\s+playtest\s*\(/m;

// Problems as "path: what is wrong". `files` are repo-relative with forward slashes.
export function ownershipProblems(files: readonly string[], read: (file: string) => string, modules: readonly ModuleClaims[]): string[] {
	const problems: string[] = [];
	for (const file of files) {
		const owner = /^modules\/([^/]+)\//.exec(file)?.[1];
		if (file.endsWith(".ts")) {
			if (/^modules\/[^/]+\/playtests\//.test(file)) continue;
			if (SCENARIO.test(read(file))) problems.push(`${file}: a playtest scenario belongs in modules/<id>/playtests/ of the module it is about`);
			continue;
		}
		if (!file.endsWith(".gd")) continue;
		const text = read(file);
		for (const m of modules) {
			if (owner === m.id) continue;
			for (const method of m.debugCalls) {
				if (text.includes(`"${m.id}:${method}"`)) problems.push(`${file}: names debug call "${m.id}:${method}"; it is allowed by modules/${m.id}/module.json (debug_calls) only`);
			}
			if (!file.startsWith("core/")) continue;
			for (const key of m.settings) {
				if (text.includes(`"${key}"`)) problems.push(`${file}: names setting "${key}", which modules/${m.id}/module.json registers; core reads module settings through Settings, never by name`);
			}
		}
	}
	return problems;
}

function walk(root: string, dir: string, out: string[]): void {
	for (const name of readdirSync(join(root, dir))) {
		if (name.startsWith(".") || name === "node_modules" || name === "bin" || name === "target") continue;
		const rel = dir === "" ? name : `${dir}/${name}`;
		const st = lstatSync(join(root, rel));
		// tools/godot is a symlink in worktrees and holds the engine.
		if (st.isSymbolicLink()) continue;
		if (st.isDirectory()) walk(root, rel, out);
		else out.push(rel);
	}
}

export function repoOwnershipProblems(root: string): string[] {
	const files: string[] = [];
	for (const top of ["core", "modules", "tools", "tests"]) if (existsSync(join(root, top))) walk(root, top, files);
	const modules: ModuleClaims[] = [];
	const modulesDir = join(root, "modules");
	for (const id of existsSync(modulesDir) ? readdirSync(modulesDir) : []) {
		const manifest = join(modulesDir, id, "module.json");
		if (existsSync(manifest)) modules.push(parseClaims(id, JSON.parse(readFileSync(manifest, "utf8"))));
	}
	return ownershipProblems(
		files.filter((f) => f !== "tools/lib/ownership.ts" && !f.startsWith("tools/godot/")).map((f) => f.split(sep).join("/")),
		(f) => readFileSync(join(root, f), "utf8"),
		modules,
	);
}
