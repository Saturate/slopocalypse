import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { platform } from "node:process";
import { run } from "./proc.ts";

export interface BindingCrate {
	name: string;
	moduleDir: string;
}

const OS_DIR: Record<string, string> = { win32: "windows", linux: "linux", darwin: "macos" };

export function libraryFile(crate: string, os: string): string {
	if (os === "win32") return `${crate}.dll`;
	if (os === "darwin") return `lib${crate}.dylib`;
	return `lib${crate}.so`;
}

// Must match the library paths written in each module's .gdextension file.
export function binDir(moduleDir: string, os: string, profile: "debug" | "release"): string {
	const dir = OS_DIR[os];
	if (dir === undefined) throw new Error(`unsupported OS for Rust extensions: ${os}`);
	return join(moduleDir, "bin", dir, profile);
}

// Binding crates are the cdylib crates in modules/<id>/rust/<crate>/; pure crates are skipped.
export function findBindingCrates(root: string): BindingCrate[] {
	const modulesDir = join(root, "modules");
	if (!existsSync(modulesDir)) return [];
	const found: BindingCrate[] = [];
	for (const mod of readdirSync(modulesDir)) {
		const rustDir = join(modulesDir, mod, "rust");
		if (!existsSync(rustDir)) continue;
		for (const crate of readdirSync(rustDir)) {
			const toml = join(rustDir, crate, "Cargo.toml");
			if (!existsSync(toml)) continue;
			const text = readFileSync(toml, "utf8");
			const name = /^name\s*=\s*"([^"]+)"/m.exec(text)?.[1];
			if (name !== undefined && /crate-type\s*=\s*\[[^\]]*"cdylib"/.test(text)) {
				found.push({ name, moduleDir: join(modulesDir, mod) });
			}
		}
	}
	return found;
}

export function hasRustCrates(root: string): boolean {
	const modulesDir = join(root, "modules");
	if (!existsSync(modulesDir)) return false;
	return readdirSync(modulesDir).some((mod) => existsSync(join(modulesDir, mod, "rust")));
}

export interface BuildResult {
	ok: boolean;
	detail: string;
}

export async function buildRust(root: string, release: boolean): Promise<BuildResult> {
	const crates = findBindingCrates(root);
	if (crates.length === 0) return { ok: true, detail: "no binding crates" };
	const profile = release ? "release" : "debug";
	const args = ["build", ...crates.flatMap((c) => ["-p", c.name]), ...(release ? ["--release"] : [])];
	const r = await run("cargo", args, { cwd: root, timeoutMs: 1_800_000 });
	if (r.code !== 0) return { ok: false, detail: r.output.trim().split(/\r?\n/).slice(-30).join("\n") };
	// target/ sits inside the Godot project; keep the importer out of it.
	mkdirSync(join(root, "target"), { recursive: true });
	writeFileSync(join(root, "target", ".gdignore"), "");
	for (const c of crates) {
		const file = libraryFile(c.name, platform);
		const dest = binDir(c.moduleDir, platform, profile);
		mkdirSync(dest, { recursive: true });
		const from = join(root, "target", profile, file);
		const to = join(dest, file);
		// Windows locks a DLL while the game or editor has it loaded, so skip identical copies
		// and only fail when the library really changed.
		if (existsSync(to) && readFileSync(from).equals(readFileSync(to))) continue;
		try {
			copyFileSync(from, to);
		} catch (err) {
			const code = err instanceof Error && "code" in err ? String(err.code) : "";
			if (code === "EBUSY" || code === "EPERM") {
				return { ok: false, detail: `${to} is locked: close the running game or Godot editor, then rerun` };
			}
			throw err;
		}
	}
	return { ok: true, detail: `built ${crates.map((c) => c.name).join(", ")} (${profile})` };
}
