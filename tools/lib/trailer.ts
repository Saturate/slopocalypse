// The trailer pipeline's pure parts: shot lists (trailer/<name>.json) and the Godot and ffmpeg
// command lines that turn them into a video. tools/trailer.ts runs them.

export interface Shot {
	// A capture setup script (res://...) to play, or a title card.
	setup?: string;
	title?: string;
	subtitle?: string;
	// Seconds rendered after the shot starts rolling (tools/gd/movie.gd: a setup may hold that
	// back while its world loads) before the part that is kept, and seconds kept.
	skip?: number;
	seconds: number;
	// "off" hides the HUD layers for a clean shot.
	hud?: "on" | "off";
}

export interface GifOutput {
	width: number;
	fps: number;
}

// A single frame saved as a PNG: `at` seconds into the kept part of shot `shot`.
export interface Still {
	name: string;
	shot: number;
	at: number;
}

export interface ShotList {
	fps: number;
	size: [number, number];
	// Fade in and out of every shot, seconds.
	fade: number;
	shots: Shot[];
	gif?: GifOutput;
	stills?: Still[];
}

export function parseShotList(text: string): ShotList {
	const raw: unknown = JSON.parse(text);
	const errors = validateShotList(raw);
	if (errors.length > 0) throw new Error(`bad shot list:\n  ${errors.join("\n  ")}`);
	return raw as ShotList;
}

function isRecord(v: unknown): v is Record<string, unknown> {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function validateShotList(raw: unknown): string[] {
	const errors: string[] = [];
	if (!isRecord(raw)) return ["not an object"];
	if (typeof raw["fps"] !== "number" || raw["fps"] <= 0) errors.push("fps must be a positive number");
	const size = raw["size"];
	if (!Array.isArray(size) || size.length !== 2 || !size.every((n) => typeof n === "number" && n > 0 && n % 2 === 0)) errors.push("size must be [even width, even height]");
	if (typeof raw["fade"] !== "number" || raw["fade"] < 0) errors.push("fade must be a number >= 0");
	const shots = raw["shots"];
	if (!Array.isArray(shots) || shots.length === 0) {
		errors.push("shots must be a non-empty list");
		return errors;
	}
	shots.forEach((s: unknown, i: number) => {
		if (!isRecord(s)) {
			errors.push(`shot ${i}: not an object`);
			return;
		}
		const hasSetup = typeof s["setup"] === "string" && (s["setup"] as string).startsWith("res://");
		const hasTitle = typeof s["title"] === "string";
		if (hasSetup === hasTitle) errors.push(`shot ${i}: needs exactly one of setup (res://...) or title`);
		if (typeof s["seconds"] !== "number" || s["seconds"] <= 0) errors.push(`shot ${i}: seconds must be positive`);
		if (s["skip"] !== undefined && (typeof s["skip"] !== "number" || s["skip"] < 0)) errors.push(`shot ${i}: skip must be >= 0`);
		if (typeof raw["fade"] === "number" && typeof s["seconds"] === "number" && s["seconds"] < raw["fade"] * 2) errors.push(`shot ${i}: shorter than its fades`);
	});
	const stills = raw["stills"];
	if (stills !== undefined) {
		if (!Array.isArray(stills)) errors.push("stills must be a list");
		else
			stills.forEach((st: unknown, i: number) => {
				if (!isRecord(st) || typeof st["name"] !== "string" || !/^[a-z0-9_-]+$/.test(st["name"])) {
					errors.push(`still ${i}: name must be lowercase letters, digits, - or _`);
					return;
				}
				const shot = shots[typeof st["shot"] === "number" ? st["shot"] : -1];
				if (!isRecord(shot) || typeof shot["seconds"] !== "number") {
					errors.push(`still ${i}: shot must be the index of a shot`);
					return;
				}
				if (typeof st["at"] !== "number" || st["at"] < 0 || st["at"] >= shot["seconds"]) errors.push(`still ${i}: at must be within the shot's seconds`);
			});
	}
	return errors;
}

export function totalSeconds(list: ShotList): number {
	return list.shots.reduce((sum, s) => sum + s.seconds, 0);
}

// Frames Godot renders for a shot: the skipped lead-in plus the kept part.
export function shotFrames(shot: Shot, fps: number): number {
	return Math.round(((shot.skip ?? 0) + shot.seconds) * fps);
}

export function godotArgs(root: string, list: ShotList, shot: Shot, movie: string, startFile: string): string[] {
	const args = ["--path", root, "--resolution", `${list.size[0]}x${list.size[1]}`, "--fixed-fps", String(list.fps), "--write-movie", movie, "-s", "res://tools/gd/movie.gd", "--", "--frames", String(shotFrames(shot, list.fps)), "--hud", shot.hud ?? "on", "--start-file", startFile];
	if (shot.title !== undefined) {
		args.push("--title", shot.title);
		if (shot.subtitle !== undefined) args.push("--subtitle", shot.subtitle);
	} else if (shot.setup !== undefined) {
		args.push("--setup", shot.setup);
	}
	return args;
}

// Seconds of loading before a shot started rolling, from the frame number movie.gd wrote.
export function leadInSeconds(startFileText: string | undefined, fps: number): number {
	const frames = Number((startFileText ?? "").trim());
	return Number.isInteger(frames) && frames > 0 ? frames / fps : 0;
}

// One shot trimmed to its kept part, scaled, faded in and out, encoded the same as the rest
// so they join without re-encoding. `leadIn` is the loading time before the shot rolled.
export function segmentArgs(list: ShotList, shot: Shot, movie: string, segment: string, leadIn = 0): string[] {
	const [w, h] = list.size;
	const fades = list.fade > 0 ? `,fade=t=in:st=0:d=${list.fade},fade=t=out:st=${(shot.seconds - list.fade).toFixed(3)}:d=${list.fade}` : "";
	return ["-y", "-ss", String(Number((leadIn + (shot.skip ?? 0)).toFixed(3))), "-t", String(shot.seconds), "-i", movie, "-vf", `scale=${w}:${h},fps=${list.fps}${fades},format=yuv420p`, "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-an", segment];
}

export function concatList(segments: string[]): string {
	return segments.map((s) => `file '${s.replaceAll("\\", "/").replaceAll("'", "'\\''")}'`).join("\n") + "\n";
}

export function joinArgs(listFile: string, out: string): string[] {
	return ["-y", "-f", "concat", "-safe", "0", "-i", listFile, "-c", "copy", "-movflags", "+faststart", out];
}

export function gifArgs(video: string, gif: GifOutput, out: string): string[] {
	return ["-y", "-i", video, "-vf", `fps=${gif.fps},scale=${gif.width}:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4`, "-loop", "0", out];
}

// One full-size frame of a rendered segment as a PNG.
export function stillArgs(segment: string, at: number, out: string): string[] {
	return ["-y", "-ss", String(at), "-i", segment, "-frames:v", "1", "-update", "1", out];
}
