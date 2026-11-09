// Fetches the pinned changesetter binary (versions and changelog from .changeset/ files) into
// tools/changesetter/ (git-ignored), checked against a pinned SHA256. `--force` reinstalls.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { arch, argv, exit, platform } from "node:process";
import { download } from "./lib/download.ts";
import { CHANGESETTER_VERSION, changesetterAsset, changesetterBin, changesetterDir, changesetterUrl } from "./lib/changesetter.ts";

const root = resolve(import.meta.dirname, "..");
const dir = changesetterDir(root);
const bin = changesetterBin(root, platform);
const marker = join(dir, ".installed-version");

async function main(): Promise<void> {
	if (!argv.includes("--force") && existsSync(bin) && existsSync(marker) && readFileSync(marker, "utf8").trim() === CHANGESETTER_VERSION) {
		console.log(`changesetter ${CHANGESETTER_VERSION} already present`);
		return;
	}
	const asset = changesetterAsset(platform, arch);
	const work = mkdtempSync(join(tmpdir(), "slopocalypse-changesetter-"));
	try {
		const archive = join(work, asset.file);
		console.log(`Downloading changesetter ${CHANGESETTER_VERSION}`);
		await download(changesetterUrl(asset), archive);
		const actual = createHash("sha256").update(readFileSync(archive)).digest("hex");
		if (actual !== asset.sha256) throw new Error(`checksum mismatch for ${asset.file}: expected ${asset.sha256}, got ${actual}`);
		rmSync(dir, { recursive: true, force: true });
		mkdirSync(dir, { recursive: true });
		// System32 bsdtar on Windows reads the zip (Git Bash's GNU tar would take "C:" for a host);
		// tar everywhere else reads the .tar.gz.
		const tar = platform === "win32" ? join(process.env["SystemRoot"] ?? "C:\\Windows", "System32", "tar.exe") : "tar";
		execFileSync(tar, ["-xf", archive, "-C", dir], { stdio: "inherit" });
		if (!existsSync(bin)) throw new Error(`${asset.file} did not contain ${bin}`);
		if (platform !== "win32") chmodSync(bin, 0o755);
		writeFileSync(marker, CHANGESETTER_VERSION + "\n");
		console.log(`Installed changesetter ${CHANGESETTER_VERSION} at ${bin}`);
	} finally {
		rmSync(work, { recursive: true, force: true });
	}
}

try {
	await main();
} catch (err) {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
}
