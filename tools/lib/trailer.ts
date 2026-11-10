// The trailer pipeline's pure parts: shot lists (trailer/<name>.json) and the Godot and ffmpeg
// command lines that turn them into a video. tools/trailer.ts runs them.

export interface Shot {
	// A capture setup script (res://...) to play, or a title card.
	setup?: string;
	title?: string;
	subtitle?: string;
	// Seconds rendered before the part that is kept (worlds load first), and seconds kept.
	skip?: number;
	seconds: number;
	// "off" hides the HUD layers for a clean shot.
	hud?: "on" | "off";
}

export interface GifOutput {
	width: number;
	fps: number;
}

export interface ShotList {
	fps: number;
	size: [number, number];
	// Fade in and out of every shot, seconds.
	fade: number;
	shots: Shot[];
	gif?: GifOutput;
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
	return errors;
}

export function totalSeconds(list: ShotList): number {
	return list.shots.reduce((sum, s) => sum + s.seconds, 0);
}

// Frames Godot renders for a shot: the skipped lead-in plus the kept part.
export function shotFrames(shot: Shot, fps: number): number {
	return Math.round(((shot.skip ?? 0) + shot.seconds) * fps);
}

export function godotArgs(root: string, list: ShotList, shot: Shot, movie: string): string[] {
	const args = ["--path", root, "--resolution", `${list.size[0]}x${list.size[1]}`, "--fixed-fps", String(list.fps), "--write-movie", movie, "-s", "res://tools/gd/movie.gd", "--", "--frames", String(shotFrames(shot, list.fps)), "--hud", shot.hud ?? "on"];
	if (shot.title !== undefined) {
		args.push("--title", shot.title);
		if (shot.subtitle !== undefined) args.push("--subtitle", shot.subtitle);
	} else if (shot.setup !== undefined) {
		args.push("--setup", shot.setup);
	}
	return args;
}

// One shot trimmed to its kept part, scaled, faded in and out, encoded the same as the rest
// so they join without re-encoding.
export function segmentArgs(list: ShotList, shot: Shot, movie: string, segment: string): string[] {
	const [w, h] = list.size;
	const fades = list.fade > 0 ? `,fade=t=in:st=0:d=${list.fade},fade=t=out:st=${(shot.seconds - list.fade).toFixed(3)}:d=${list.fade}` : "";
	return ["-y", "-ss", String(shot.skip ?? 0), "-t", String(shot.seconds), "-i", movie, "-vf", `scale=${w}:${h},fps=${list.fps}${fades},format=yuv420p`, "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-an", segment];
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
