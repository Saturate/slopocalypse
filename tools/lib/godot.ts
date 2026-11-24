import { join } from "node:path";
import { arch, platform } from "node:process";

export const GODOT_VERSION = "4.7.2-stable";
export const RELEASE_URL = `https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}`;
export const GODOT_DIR = "tools/godot";

const BUILDS: Record<string, Record<string, string>> = {
	win32: { x64: "win64.exe", arm64: "windows_arm64.exe" },
	linux: { x64: "linux.x86_64", arm64: "linux.arm64" },
	darwin: { x64: "macos.universal", arm64: "macos.universal" },
};

function buildSuffix(os: string, cpu: string): string {
	const suffix = BUILDS[os]?.[cpu];
	if (suffix === undefined) {
		throw new Error(`no official Godot build for ${os}/${cpu}`);
	}
	return suffix;
}

export function assetFor(os: string, cpu: string): string {
	return `Godot_v${GODOT_VERSION}_${buildSuffix(os, cpu)}.zip`;
}

export function executableIn(dir: string, os: string, cpu: string): string {
	const suffix = buildSuffix(os, cpu);
	if (os === "darwin") {
		return `${dir}/Godot.app/Contents/MacOS/Godot`;
	}
	if (os === "win32") {
		// The console variant keeps stdout attached, which headless runs and log scanning rely on.
		return `${dir}/Godot_v${GODOT_VERSION}_${suffix.replace(/\.exe$/, "")}_console.exe`;
	}
	return `${dir}/Godot_v${GODOT_VERSION}_${suffix}`;
}

export function localGodot(root: string): string {
	return join(root, executableIn(GODOT_DIR, platform, arch));
}

// What a windowed run a tool starts (captures, playtests, benches, trailers) adds so it stays
// out of the way of whoever is at the machine. On macOS Godot forces itself to the front when
// the bundle id in its environment is not its own (the terminal's leaks in), so the window
// would take the keyboard; and macOS stops drawing a window that is covered, minimised or off
// screen (Godot pulls off-screen positions back), so it stays on top instead of hiding.
// Launchers meant for a person at the keyboard (run-local, range, library) keep a normal window.
export const GODOT_BUNDLE_ID = "org.godotengine.godot";

export interface QuietWindow {
	args: string[];
	env: NodeJS.ProcessEnv;
}

export function quietWindow(os: string, env: NodeJS.ProcessEnv): QuietWindow {
	if (os !== "darwin") return { args: [], env };
	return { args: ["--always-on-top"], env: { ...env, __CFBundleIdentifier: GODOT_BUNDLE_ID } };
}
