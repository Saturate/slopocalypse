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
			"application/product_name": "Outpost",
			"codesign/enable": false,
		},
		linux: { ...common, "binary_format/architecture": "x86_64" },
		macos: { "binary_format/architecture": "universal", "application/bundle_identifier": "dev.saturate.outpost", "codesign/codesign": 0 },
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
	return os === "windows" ? "Outpost.exe" : os === "linux" ? "Outpost.x86_64" : "Outpost.app";
}

// What a friend double-clicks to join. The address is baked in so nobody types anything.
export function joinScript(os: TargetOs, host: string): string {
	if (os === "windows") {
		return `@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0Outpost.exe" -- --connect=${host}\r\n`;
	}
	return `#!/bin/sh\ncd "$(dirname "$0")"\nexec ./${exeName(os)} -- --connect=${host}\n`;
}

// Runs a dedicated server in a visible window, so the host can see it and close it.
export function hostScript(os: TargetOs, port: number): string {
	if (os === "windows") {
		return `@echo off\r\ncd /d "%~dp0"\r\n"%~dp0Outpost.console.exe" --headless -- --server=${port}\r\npause\r\n`;
	}
	return `#!/bin/sh\ncd "$(dirname "$0")"\nexec ./${exeName(os)} --headless -- --server=${port}\n`;
}
