// Fetches ffmpeg for the trailer pipeline. On Windows: the pinned build into tools/ffmpeg/
// (git-ignored), checked against a pinned SHA256. On Linux and macOS: says how to install it
// with the package manager (the trailer tool uses ffmpeg from PATH). `--force` reinstalls.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { argv, exit, platform } from "node:process";
import { download } from "./lib/download.ts";
import { FFMPEG_VERSION, FFMPEG_WINDOWS, ffmpegDir } from "./lib/ffmpeg.ts";

const root = resolve(import.meta.dirname, "..");
const dir = ffmpegDir(root);
const marker = join(dir, ".installed-version");

async function main(): Promise<void> {
	if (platform !== "win32") {
		console.log("Install ffmpeg with your package manager (apt install ffmpeg, brew install ffmpeg); the trailer tool uses the one on PATH.");
		return;
	}
	if (!argv.includes("--force") && existsSync(join(dir, "ffmpeg.exe")) && existsSync(marker) && readFileSync(marker, "utf8").trim() === FFMPEG_VERSION) {
		console.log(`ffmpeg ${FFMPEG_VERSION} already present`);
		return;
	}
	const work = mkdtempSync(join(tmpdir(), "slopocalypse-ffmpeg-"));
	try {
		const archive = join(work, FFMPEG_WINDOWS.file);
		console.log(`Downloading ffmpeg ${FFMPEG_VERSION} (about 100 MB, once)`);
		await download(FFMPEG_WINDOWS.url, archive);
		const actual = createHash("sha256").update(readFileSync(archive)).digest("hex");
		if (actual !== FFMPEG_WINDOWS.sha256) throw new Error(`checksum mismatch for ${FFMPEG_WINDOWS.file}: expected ${FFMPEG_WINDOWS.sha256}, got ${actual}`);
		// System32 bsdtar reads zips; Git Bash's GNU tar would take "C:" for a host.
		const tar = join(process.env["SystemRoot"] ?? "C:\\Windows", "System32", "tar.exe");
		execFileSync(tar, ["-xf", archive, "-C", work, FFMPEG_WINDOWS.inner], { stdio: "inherit" });
		rmSync(dir, { recursive: true, force: true });
		mkdirSync(dir, { recursive: true });
		copyFileSync(join(work, FFMPEG_WINDOWS.inner), join(dir, "ffmpeg.exe"));
		writeFileSync(marker, FFMPEG_VERSION + "\n");
		console.log(`Installed ffmpeg ${FFMPEG_VERSION} at ${join(dir, "ffmpeg.exe")}`);
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
