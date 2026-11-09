import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

export type TargetOs = "windows" | "linux" | "macos";

export interface Preset {
	name: string;
	platform: string;
	exportPath: string;
	options: Record<string, string | number | boolean>;
}

const PLATFORMS: Record<TargetOs, string> = { windows: "Windows Desktop", linux: "Linux", macos: "macOS" };

// Data the game reads with FileAccess is not a Godot resource, so it must be listed.
const INCLUDE = ["*.json"];
// Dev-only: tests, builders, captures, tooling and Rust sources never ship.
const EXCLUDE = [
	"tests/*",
	"tools/*",
	"screenshots/*",
	"addons/gdUnit4/*",
	"modules/*/tests/*",
	"modules/*/builders/*",
	"modules/*/capture/*",
	"modules/*/rust/*",
];

export function presetFor(os: TargetOs, exportPath: string): Preset {
	const common = { "binary_format/embed_pck": true, "texture_format/s3tc_bptc": true, "texture_format/etc2_astc": false };
	const perOs: Record<TargetOs, Preset["options"]> = {
		windows: {
			...common,
			"binary_format/architecture": "x86_64",
			// Always, not only for debug builds: the host's server window is the console exe.
			"debug/export_console_wrapper": 2,
			// Needs rcedit; the default icon is fine for now.
			"application/modify_resources": false,
			"application/product_name": "Slopocalypse",
			"codesign/enable": false,
		},
		linux: { ...common, "binary_format/architecture": "x86_64" },
		macos: { "binary_format/architecture": "universal", "application/bundle_identifier": "dev.saturate.slopocalypse", "codesign/codesign": 0 },
	};
	return { name: PLATFORMS[os], platform: PLATFORMS[os], exportPath, options: perOs[os] };
}

function value(v: string | number | boolean): string {
	return typeof v === "string" ? JSON.stringify(v) : String(v);
}

export function presetsFile(presets: readonly Preset[]): string {
	const out: string[] = [];
	presets.forEach((p, i) => {
		out.push(
			`[preset.${i}]`,
			"",
			`name=${value(p.name)}`,
			`platform=${value(p.platform)}`,
			"runnable=true",
			"dedicated_server=false",
			'custom_features=""',
			'export_filter="all_resources"',
			`include_filter=${value(INCLUDE.join(", "))}`,
			`exclude_filter=${value(EXCLUDE.join(", "))}`,
			`export_path=${value(p.exportPath)}`,
			"encrypt_pck=false",
			"encrypt_directory=false",
			"",
			`[preset.${i}.options]`,
			"",
			...Object.entries(p.options).map(([k, v]) => `${k}=${value(v)}`),
			"",
		);
	});
	return out.join("\n");
}

// Self-contained mode (the `._sc_` file get-godot writes) keeps templates next to the engine.
export function templatesDir(godotDir: string, version: string): string {
	return join(godotDir, "editor_data", "export_templates", version.replace("-", "."));
}

export function exeName(os: TargetOs): string {
	return os === "windows" ? "Slopocalypse.exe" : os === "linux" ? "Slopocalypse.x86_64" : "Slopocalypse.app";
}

// Gameplay data files a player can tune: data/*.json and modules/<id>/data/*.json,
// relative to the project root with forward slashes.
export function dataFiles(root: string): string[] {
	const out: string[] = [];
	const addDir = (rel: string): void => {
		const dir = join(root, rel);
		if (!existsSync(dir)) return;
		for (const f of readdirSync(dir).sort()) if (f.endsWith(".json")) out.push(`${rel}/${f}`);
	};
	addDir("data");
	const modules = join(root, "modules");
	if (existsSync(modules)) for (const m of readdirSync(modules).sort()) addDir(`modules/${m}/data`);
	return out;
}

export const TWEAKS_README = [
	"Tuning the game without rebuilding it",
	"",
	"Every gameplay number lives in a JSON file. The game's own copies are in the defaults folder.",
	"To change one: copy the file from defaults into this tweaks folder at the same path,",
	"edit it, and start the game again. For example:",
	"  defaults/modules/enemies/data/enemies.json  ->  tweaks/modules/enemies/data/enemies.json",
	"",
	"The copy here replaces the built-in file completely. Delete it to go back to the default.",
	"In multiplayer the server's numbers decide damage, health, enemies and loot, so tweak on",
	"the machine that hosts; give friends the same tweaks folder so guns and parts match.",
	"",
].join("\r\n");

// servers.json beside the game: the main menu lists these under Recent, so a friend's copy
// already knows where to join. `hosts` is a comma-separated list of addresses.
export function shippedServers(hosts: string): string {
	const servers = hosts.split(",").map((h) => h.trim()).filter((h) => h.length > 0);
	return JSON.stringify({ servers }, null, 2);
}

// Runs a dedicated server in a visible window, so the host can see it and close it.
export function hostScript(os: TargetOs, port: number): string {
	if (os === "windows") {
		return `@echo off\r\ncd /d "%~dp0"\r\n"%~dp0Slopocalypse.console.exe" --headless -- --server=${port}\r\npause\r\n`;
	}
	return `#!/bin/sh\ncd "$(dirname "$0")"\nexec ./${exeName(os)} --headless -- --server=${port}\n`;
}
