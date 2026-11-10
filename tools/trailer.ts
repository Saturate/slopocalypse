// Renders a trailer from a shot list:
//   node tools/trailer.ts <name> [--only N]
// Reads trailer/<name>.json, renders every shot with Godot's Movie Maker (a real window, fixed
// frame rate, so nothing drops however slow), then ffmpeg trims, fades, joins and encodes:
// build/trailer/<name>.mp4, and build/trailer/<name>.gif when the list asks for one.
// --only N renders just shot N (to tune it). Needs ffmpeg: node tools/get-ffmpeg.ts.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { argv, exit, platform } from "node:process";
import { GODOT_NOISE } from "./lib/gate.ts";
import { ffmpegBin } from "./lib/ffmpeg.ts";
import { localGodot } from "./lib/godot.ts";
import { scanLog } from "./lib/log-scan.ts";
import { run } from "./lib/proc.ts";
import { concatList, gifArgs, godotArgs, joinArgs, parseShotList, segmentArgs, totalSeconds } from "./lib/trailer.ts";

const root = resolve(import.meta.dirname, "..");

async function main(): Promise<void> {
	const name = argv[2];
	if (name === undefined || name.startsWith("--")) throw new Error("usage: node tools/trailer.ts <name> [--only N]");
	const listPath = join(root, "trailer", `${name}.json`);
	if (!existsSync(listPath)) throw new Error(`no shot list at ${listPath}`);
	const list = parseShotList(readFileSync(listPath, "utf8"));
	const onlyAt = argv.indexOf("--only");
	const only = onlyAt >= 0 ? Number(argv[onlyAt + 1]) : -1;
	const out = join(root, "build", "trailer", name);
	mkdirSync(out, { recursive: true });
	const ffmpeg = ffmpegBin(root, platform);
	const godot = localGodot(root);
	console.log(`${name}: ${list.shots.length} shots, ${totalSeconds(list).toFixed(1)} s at ${list.size[0]}x${list.size[1]} ${list.fps} fps`);
	const segments: string[] = [];
	for (let i = 0; i < list.shots.length; i++) {
		if (only >= 0 && i !== only) continue;
		const shot = list.shots[i];
		if (shot === undefined) continue;
		const movie = join(out, `shot_${i}.avi`);
		const segment = join(out, `segment_${i}.mp4`);
		console.log(`  shot ${i}: ${shot.title ?? shot.setup} (${shot.seconds} s)`);
		const r = await run(godot, godotArgs(root, list, shot, movie), { cwd: root, timeoutMs: 600_000 });
		// Quitting mid-scene leaves engine resources the exit reports as leaked: harmless here.
		const problems = scanLog(r.output, GODOT_NOISE).filter((l) => !/leaked at exit/.test(l));
		if (r.code !== 0 || problems.length > 0 || !existsSync(movie)) {
			throw new Error(`shot ${i} failed (exit ${r.code}):\n${problems.slice(0, 20).join("\n") || r.output.slice(-2000)}`);
		}
		const f = await run(ffmpeg, segmentArgs(list, shot, movie, segment), { cwd: root, timeoutMs: 600_000 });
		if (f.code !== 0) throw new Error(`ffmpeg failed on shot ${i}:\n${f.output.slice(-2000)}`);
		segments.push(segment);
	}
	if (only >= 0) {
		console.log(`Shot ${only}: ${segments[0] ?? "nothing"}`);
		return;
	}
	const listFile = join(out, "segments.txt");
	writeFileSync(listFile, concatList(segments));
	const video = join(root, "build", "trailer", `${name}.mp4`);
	const j = await run(ffmpeg, joinArgs(listFile, video), { cwd: root, timeoutMs: 600_000 });
	if (j.code !== 0) throw new Error(`ffmpeg could not join the shots:\n${j.output.slice(-2000)}`);
	console.log(`Video: ${video}`);
	if (list.gif !== undefined) {
		const gif = join(root, "build", "trailer", `${name}.gif`);
		const g = await run(ffmpeg, gifArgs(video, list.gif, gif), { cwd: root, timeoutMs: 600_000 });
		if (g.code !== 0) throw new Error(`ffmpeg could not make the GIF:\n${g.output.slice(-2000)}`);
		console.log(`GIF: ${gif}`);
	}
}

try {
	await main();
} catch (err) {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
}
