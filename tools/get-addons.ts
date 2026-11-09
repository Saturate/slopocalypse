// Fetches third-party Godot extensions that are too large for git, pinned by SHA256, into
// addons/<name>/ (git-ignored). Same idea as get-godot.ts. `--force` reinstalls.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { argv, exit, platform } from "node:process";

interface Addon {
	name: string;
	version: string;
	url: string;
	sha256: string;
}

export const ADDONS: readonly Addon[] = [
	{
		// Voxel Tools (Zylann, MIT): smooth Transvoxel terrain with LOD, editing, streaming.
		name: "zylann.voxel",
		version: "1.7",
		url: "https://github.com/Zylann/godot_voxel/releases/download/v1.7x/GodotVoxelExtension.zip",
		sha256: "600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8",
	},
];

const root = resolve(import.meta.dirname, "..");
const force = argv.includes("--force");

function sha256(file: string): string {
	return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function extract(zip: string, dest: string): void {
	// See get-godot.ts: System32 bsdtar on Windows, unzip on Linux, tar on macOS.
	if (platform === "linux") {
		execFileSync("unzip", ["-o", "-q", zip, "-d", dest], { stdio: "inherit" });
	} else if (platform === "win32") {
		const bsdtar = join(process.env["SystemRoot"] ?? "C:\\Windows", "System32", "tar.exe");
		execFileSync(bsdtar, ["-xf", zip, "-C", dest], { stdio: "inherit" });
	} else {
		execFileSync("tar", ["-xf", zip, "-C", dest], { stdio: "inherit" });
	}
}

async function install(addon: Addon): Promise<void> {
	const target = join(root, "addons", addon.name);
	const marker = join(target, ".installed-version");
	if (!force && existsSync(marker) && readFileSync(marker, "utf8").trim() === addon.version) {
		console.log(`${addon.name} ${addon.version} already present`);
		return;
	}
	const work = mkdtempSync(join(tmpdir(), "slopocalypse-addon-"));
	try {
		const zip = join(work, "addon.zip");
		console.log(`Downloading ${addon.name} ${addon.version}`);
		const res = await fetch(addon.url);
		if (!res.ok) throw new Error(`download failed: ${addon.url} returned ${res.status}`);
		writeFileSync(zip, Buffer.from(await res.arrayBuffer()));
		const actual = sha256(zip);
		if (actual !== addon.sha256) {
			throw new Error(`checksum mismatch for ${addon.name}: expected ${addon.sha256}, got ${actual}`);
		}
		rmSync(target, { recursive: true, force: true });
		// Archives are laid out as addons/<name>/..., so extract at the project root.
		extract(zip, root);
		if (!existsSync(target)) throw new Error(`${addon.name}: archive did not contain addons/${addon.name}`);
		writeFileSync(marker, addon.version + "\n");
		console.log(`Installed ${addon.name} ${addon.version}`);
	} finally {
		rmSync(work, { recursive: true, force: true });
	}
}

try {
	for (const addon of ADDONS) await install(addon);
} catch (err) {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
}
