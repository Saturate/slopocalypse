// ffmpeg for the trailer pipeline: a pinned Windows build fetched into tools/ffmpeg/
// (git-ignored, checked against a pinned SHA256) by tools/get-ffmpeg.ts, or ffmpeg from the
// system's package manager on Linux and macOS. A tool only; never shipped with the game.
import { existsSync } from "node:fs";
import { join } from "node:path";

export const FFMPEG_VERSION = "9.0.2";
// GyanD's versioned Windows "essentials" build (GPL; fine for a local tool we don't ship).
export const FFMPEG_WINDOWS = {
	file: `ffmpeg-${FFMPEG_VERSION}-essentials_build.zip`,
	url: `https://github.com/GyanD/codexffmpeg/releases/download/${FFMPEG_VERSION}/ffmpeg-${FFMPEG_VERSION}-essentials_build.zip`,
	sha256: "60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba",
	inner: `ffmpeg-${FFMPEG_VERSION}-essentials_build/bin/ffmpeg.exe`,
};

export function ffmpegDir(root: string): string {
	return join(root, "tools", "ffmpeg");
}

// The ffmpeg to run: the pinned one when installed, else whatever is on PATH.
export function ffmpegBin(root: string, platform: string): string {
	const pinned = join(ffmpegDir(root), platform === "win32" ? "ffmpeg.exe" : "ffmpeg");
	return existsSync(pinned) ? pinned : "ffmpeg";
}
