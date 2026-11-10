import { test } from "node:test";
import assert from "node:assert/strict";
import { concatList, gifArgs, godotArgs, parseShotList, segmentArgs, shotFrames, totalSeconds, validateShotList } from "./trailer.ts";

const LIST = {
	fps: 60,
	size: [1280, 720],
	fade: 0.25,
	shots: [
		{ title: "SLOPOCALYPSE", subtitle: "built by AI agents", seconds: 2 },
		{ setup: "res://modules/missions/capture/breaking.gd", skip: 3, seconds: 4, hud: "off" },
	],
};

test("a good shot list parses and adds up", () => {
	const list = parseShotList(JSON.stringify(LIST));
	assert.equal(totalSeconds(list), 6);
	assert.equal(shotFrames(list.shots[1]!, 60), 420);
});

test("bad shot lists say what is wrong", () => {
	assert.ok(validateShotList({ ...LIST, size: [1281, 720] }).some((e) => e.includes("size")));
	assert.ok(validateShotList({ ...LIST, shots: [{ seconds: 2 }] }).some((e) => e.includes("exactly one")));
	assert.ok(validateShotList({ ...LIST, shots: [{ title: "x", setup: "res://a.gd", seconds: 2 }] }).some((e) => e.includes("exactly one")));
	assert.ok(validateShotList({ ...LIST, shots: [{ title: "x", seconds: 0.3 }] }).some((e) => e.includes("fades")));
	assert.ok(validateShotList({ ...LIST, shots: [] }).some((e) => e.includes("non-empty")));
});

test("Godot renders each shot with Movie Maker at the list's size and rate", () => {
	const list = parseShotList(JSON.stringify(LIST));
	const title = godotArgs("/p", list, list.shots[0]!, "/o/shot_0.avi");
	assert.deepEqual(title.slice(0, 8), ["--path", "/p", "--resolution", "1280x720", "--fixed-fps", "60", "--write-movie", "/o/shot_0.avi"]);
	assert.ok(title.includes("--title") && title.includes("SLOPOCALYPSE") && title.includes("--subtitle"));
	const scene = godotArgs("/p", list, list.shots[1]!, "/o/shot_1.avi");
	assert.ok(scene.includes("--setup") && scene.includes("off"));
	assert.equal(scene[scene.indexOf("--frames") + 1], "420");
});

test("ffmpeg trims the lead-in, fades and encodes each shot alike", () => {
	const list = parseShotList(JSON.stringify(LIST));
	const args = segmentArgs(list, list.shots[1]!, "in.avi", "out.mp4");
	assert.equal(args[args.indexOf("-ss") + 1], "3");
	assert.equal(args[args.indexOf("-t") + 1], "4");
	const vf = args[args.indexOf("-vf") + 1]!;
	assert.match(vf, /fade=t=in:st=0:d=0.25/);
	assert.match(vf, /fade=t=out:st=3\.750:d=0.25/);
	assert.ok(args.includes("libx264") && args.includes("-an"));
});

test("the join list quotes paths and the GIF loops", () => {
	assert.equal(concatList(["C:\\b\\it's.mp4"]), "file 'C:/b/it'\\''s.mp4'\n");
	const gif = gifArgs("v.mp4", { width: 720, fps: 15 }, "v.gif");
	assert.ok(gif.join(" ").includes("palettegen") && gif.includes("-loop"));
});
