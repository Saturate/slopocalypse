// Scripted playtests (tools/play.ts): a scenario starts a real session (a headless dedicated
// server and named windowed clients, every one with the debug API on), drives it through
// that API, checks game state and takes screenshots that a reviewer judges without the code.
// See docs/decisions/0017-scripted-playtests-over-the-debug-api.md.
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve as resolvePath } from "node:path";
import { env, platform } from "node:process";
import { isDeepStrictEqual } from "node:util";
import { discover, godotUserDir, rpc, type Game as ApiGame } from "./debug-api.ts";
import { GODOT_NOISE } from "./gate.ts";
import { scanLog, stripAnsi } from "./log-scan.ts";
import { watch, type Watched } from "./net.ts";
import { brighterPixels, decodePng, findColour, meanLuma, parseColour, WHOLE, type Image, type Region } from "./png.ts";
import { killTree, type ProcResult } from "./proc.ts";
import { summarisePerf, type ImageCheck, type LogRecord, type PerfRecord, type PerfSample, type ShotRecord, type StepKind, type StepRecord } from "./play-report.ts";

// ---------------------------------------------------------------------------------------
// Pure helpers (tested in play.test.ts)

export interface PlayArgs {
	scenario: string;
	keep: boolean;
	headless: boolean;
	port: number | undefined;
	timeoutSeconds: number | undefined;
	list: boolean;
}

export function parsePlayArgs(args: readonly string[]): PlayArgs {
	const out: PlayArgs = { scenario: "", keep: false, headless: false, port: undefined, timeoutSeconds: undefined, list: false };
	for (let i = 0; i < args.length; i++) {
		const a = args[i] ?? "";
		const value = (): number => {
			const v = Number(args[++i]);
			if (!Number.isInteger(v) || v <= 0) throw new Error(`${a} needs a positive whole number`);
			return v;
		};
		if (a === "--keep") out.keep = true;
		else if (a === "--headless") out.headless = true;
		else if (a === "--list") out.list = true;
		else if (a === "--port") out.port = value();
		else if (a === "--timeout") out.timeoutSeconds = value();
		else if (a.startsWith("--")) throw new Error(`unknown option ${a}`);
		else if (out.scenario === "") out.scenario = a;
		else throw new Error(`one scenario at a time (got ${out.scenario} and ${a})`);
	}
	if (out.scenario === "" && !out.list) throw new Error("name a scenario (--list shows them)");
	if (!/^[a-z0-9][a-z0-9-]*$/.test(out.scenario) && !out.list) throw new Error(`scenario names are lower-case words joined by -, got ${out.scenario}`);
	return out;
}

// Where a run's port search starts: spread over a band away from the gate's smoke tests
// (7791..7796) and the default 7777, so two agents' runs seldom try the same one first.
export const PORT_BAND = { from: 7820, span: 160 } as const;

export function preferredPort(random: number): number {
	return PORT_BAND.from + Math.floor(Math.min(Math.max(random, 0), 0.999999) * PORT_BAND.span);
}

export type Vec3 = readonly [number, number, number];

// A value the game reads as a Godot value string (str_to_var): what `set` and `call` take.
export type GodotValue = number | string | boolean | null | Float | Vec2Value | Vec3Value | PathValue;

// A number Godot must see as a float even when it is whole (a typed float property).
export class Float {
	readonly value: number;
	constructor(value: number) {
		this.value = value;
	}
}
export class Vec2Value {
	readonly v: readonly [number, number];
	constructor(v: readonly [number, number]) {
		this.v = v;
	}
}
export class Vec3Value {
	readonly v: Vec3;
	constructor(v: Vec3) {
		this.v = v;
	}
}
// A node path; `call` hands the method the node itself.
export class PathValue {
	readonly path: string;
	constructor(path: string) {
		this.path = path;
	}
}

export const float = (n: number): Float => new Float(n);
export const vec2 = (v: readonly [number, number]): Vec2Value => new Vec2Value(v);
export const vec3 = (v: Vec3): Vec3Value => new Vec3Value(v);
export const nodePath = (p: string): PathValue => new PathValue(p);

function floatText(n: number): string {
	if (!Number.isFinite(n)) throw new Error(`cannot send ${n} to Godot`);
	return Number.isInteger(n) ? `${n}.0` : String(n);
}

export function godotValue(v: GodotValue): string {
	if (v === null) return "null";
	if (typeof v === "boolean") return v ? "true" : "false";
	if (typeof v === "number") {
		if (!Number.isFinite(v)) throw new Error(`cannot send ${v} to Godot`);
		return String(v);
	}
	// JSON's escapes (\" \\ \n \uXXXX) are ones Godot's parser reads too.
	if (typeof v === "string") return JSON.stringify(v);
	if (v instanceof Float) return floatText(v.value);
	if (v instanceof Vec2Value) return `Vector2(${v.v.map(floatText).join(", ")})`;
	if (v instanceof Vec3Value) return `Vector3(${v.v.map(floatText).join(", ")})`;
	return `NodePath(${JSON.stringify(v.path)})`;
}

// "Vector3(1, 2.5, -3)" (var_to_str) or [1, 2.5, -3] (plain JSON) as numbers.
export function parseVec3(value: unknown): Vec3 | undefined {
	if (Array.isArray(value) && value.length === 3 && value.every((n) => typeof n === "number")) return [Number(value[0]), Number(value[1]), Number(value[2])];
	if (typeof value !== "string") return undefined;
	const m = /^Vector3i?\(\s*(-?[\d.e+-]+),\s*(-?[\d.e+-]+),\s*(-?[\d.e+-]+)\s*\)$/.exec(value.trim());
	if (m === null) return undefined;
	const v: Vec3 = [Number(m[1]), Number(m[2]), Number(m[3])];
	return v.every(Number.isFinite) ? v : undefined;
}

export const distance = (a: Vec3, b: Vec3): number => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);

// The yaw (around Y, radians) and pitch (up positive) that turn Godot's forward (-Z) from
// `from` towards `to`.
export function yawPitchTo(from: Vec3, to: Vec3): { yaw: number; pitch: number } {
	const dx = to[0] - from[0];
	const dy = to[1] - from[1];
	const dz = to[2] - from[2];
	return { yaw: Math.atan2(-dx, -dz), pitch: Math.atan2(dy, Math.hypot(dx, dz)) };
}

// Horizontal distance: walking cares where the feet are on the map, not how high.
export const flatDistance = (a: Vec3, b: Vec3): number => Math.hypot(a[0] - b[0], a[2] - b[2]);

export interface Steer {
	// Facing (yaw around Y) from `at` towards `to`, as yawPitchTo gives it.
	yaw: number;
	// Forward push 0..1: full until the last couple of metres, then less, so a poll every few
	// hundred milliseconds does not carry the walker past the target and back.
	forward: number;
	distance: number;
	arrived: boolean;
}

export const SLOW_WITHIN_M = 2;
const MIN_PUSH = 0.3;

// One step of walking from `at` to `to`: which way to face and how hard to push.
export function steer(at: Vec3, to: Vec3, within: number): Steer {
	const distance = flatDistance(at, to);
	const arrived = distance <= within;
	return { yaw: yawPitchTo(at, [to[0], at[1], to[2]]).yaw, forward: arrived ? 0 : Math.min(1, Math.max(MIN_PUSH, distance / SLOW_WITHIN_M)), distance, arrived };
}

// The player's walking pace, m/s (modules/player/data/player.json walk_speed; a tool test
// keeps the two the same).
export const WALK_SPEED = 4.5;

// How long a walk of `distance` metres may take before it counts as stuck: three times
// the time at walking pace, and never under 10 s.
export function walkTimeoutMs(distance: number, speed = WALK_SPEED): number {
	return Math.max(10_000, Math.ceil((distance / speed) * 3 * 1000));
}

// Rounds fired between two magazine readings: a reload in between (the count went up)
// counts as nothing fired, never as a negative.
export function roundsFired(before: number, now: number): number {
	return before >= 0 && now >= 0 ? Math.max(0, before - now) : 0;
}

// The debug API file that belongs to the process logging to `logFile` (each run gives every
// process its own log, so this needs no pid, which a launcher on Windows would not match).
export function apiForLog(games: readonly ApiGame[], logFile: string): ApiGame | undefined {
	const norm = (p: string): string => {
		const slashes = p.replaceAll("\\", "/");
		return platform === "win32" ? slashes.toLowerCase() : slashes;
	};
	return games.find((g) => g.log !== "" && norm(g.log) === norm(logFile));
}

export interface LogScan {
	errors: string[];
	allowed: number;
	warnings: string[];
	warningCount: number;
}

// Error lines as the gate reads them (any of them fails the run unless allowed), and the
// warnings, which only show in the report.
export function scanPlayLog(output: string, allow: readonly RegExp[]): LogScan {
	const all = scanLog(output, GODOT_NOISE);
	const errors = all.filter((l) => !allow.some((p) => p.test(l)));
	const warnings = stripAnsi(output)
		.split(/\r?\n/)
		.filter((l) => /^\s*WARNING:/.test(l));
	return { errors, allowed: all.length - errors.length, warnings: warnings.slice(0, 20), warningCount: warnings.length };
}

export function describeValue(value: unknown, max = 300): string {
	let text: string;
	try {
		text = typeof value === "string" ? JSON.stringify(value) : (JSON.stringify(value) ?? String(value));
	} catch {
		text = String(value);
	}
	return text.length > max ? `${text.slice(0, max)}...` : text;
}

// ---------------------------------------------------------------------------------------
// Steps and expectations

export class PlaytestFailure extends Error {}
export class PlaytestSkip extends Error {}

export class Recorder {
	readonly steps: StepRecord[] = [];
	readonly shots: ShotRecord[] = [];
	private readonly started = Date.now();
	// Set when the run is over (deadline, Ctrl-C, teardown): a scenario still running after
	// that is abandoned, and nothing it does reaches the report or the games any more.
	closed = false;
	log = (line: string): void => console.log(line);

	since(): number {
		return Date.now() - this.started;
	}

	add(kind: StepKind, title: string, ok: boolean, detail?: string): void {
		if (this.closed) return;
		const step: StepRecord = detail === undefined ? { at: this.since(), kind, title, ok } : { at: this.since(), kind, title, ok, detail };
		this.steps.push(step);
		this.log(`  ${(step.at / 1000).toFixed(1).padStart(6)} s  ${ok ? "  " : "FAIL "}${kind}: ${title}${detail !== undefined && detail !== "" ? ` (${detail})` : ""}`);
	}
}

interface Check<V> {
	// What the value should be, said after "expected <what> ".
	wants: string;
	pass: (value: V) => boolean;
}

// The checks, shared by expect(value) and expect.poll(fn); `run` decides what a check does.
abstract class Matchers<V, R> {
	protected abstract run(check: Check<V>): R;

	toBe(want: unknown): R {
		return this.run({ wants: `to be ${describeValue(want)}`, pass: (v) => Object.is(v, want) });
	}
	toEqual(want: unknown): R {
		return this.run({ wants: `to equal ${describeValue(want)}`, pass: (v) => isDeepStrictEqual(v, want) });
	}
	toBeTruthy(): R {
		return this.run({ wants: "to be truthy", pass: (v) => Boolean(v) });
	}
	toBeFalsy(): R {
		return this.run({ wants: "to be falsy", pass: (v) => !v });
	}
	toBeGreaterThan(n: number): R {
		return this.run({ wants: `to be greater than ${n}`, pass: (v) => typeof v === "number" && v > n });
	}
	toBeLessThan(n: number): R {
		return this.run({ wants: `to be less than ${n}`, pass: (v) => typeof v === "number" && v < n });
	}
	toBeCloseTo(n: number, within: number): R {
		return this.run({ wants: `to be within ${within} of ${n}`, pass: (v) => typeof v === "number" && Math.abs(v - n) <= within });
	}
	toContain(item: unknown): R {
		return this.run({
			wants: `to contain ${describeValue(item)}`,
			pass: (v) => (typeof v === "string" && typeof item === "string" ? v.includes(item) : Array.isArray(v) && v.some((x) => isDeepStrictEqual(x, item))),
		});
	}
	toMatch(pattern: RegExp): R {
		return this.run({ wants: `to match ${pattern}`, pass: (v) => typeof v === "string" && pattern.test(v) });
	}
	// `says` reads after "expected <what> ", e.g. "to show Bo's marker".
	toSatisfy(fn: (v: V) => boolean, says: string): R {
		return this.run({ wants: says, pass: fn });
	}
}

class ValueMatchers<V> extends Matchers<V, void> {
	private readonly rec: Recorder;
	private readonly value: V;
	private readonly what: string;
	constructor(rec: Recorder, value: V, what: string) {
		super();
		this.rec = rec;
		this.value = value;
		this.what = what;
	}
	protected run(check: Check<V>): void {
		const ok = check.pass(this.value);
		this.rec.add("assert", `${this.what} ${check.wants}`, ok, ok ? undefined : `got ${describeValue(this.value)}`);
		if (!ok) throw new PlaytestFailure(`expected ${this.what} ${check.wants}; got ${describeValue(this.value)}`);
	}
}

export interface PollOptions {
	timeout?: number;
	interval?: number;
	// What is being waited for, in the report and the failure message.
	what?: string;
}

const DEFAULT_POLL_MS = 15_000;
const POLL_INTERVAL_MS = 250;

export const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

// Waits on the wall clock, never on frames: a slow machine renders fewer frames, not less time.
class PollMatchers<T> extends Matchers<T, Promise<T>> {
	private readonly rec: Recorder;
	private readonly fn: () => T | Promise<T>;
	private readonly opts: PollOptions;
	constructor(rec: Recorder, fn: () => T | Promise<T>, opts: PollOptions) {
		super();
		this.rec = rec;
		this.fn = fn;
		this.opts = opts;
	}
	protected async run(check: Check<T>): Promise<T> {
		const what = this.opts.what ?? "polled value";
		const timeout = this.opts.timeout ?? DEFAULT_POLL_MS;
		const started = Date.now();
		let last: unknown = undefined;
		let lastError = "";
		for (;;) {
			if (this.rec.closed) throw new PlaytestFailure("the run is over");
			try {
				const value = await this.fn();
				last = value;
				lastError = "";
				if (check.pass(value)) {
					this.rec.add("wait", `${what} ${check.wants}`, true, `after ${((Date.now() - started) / 1000).toFixed(1)} s`);
					return value;
				}
			} catch (err) {
				if (err instanceof PlaytestSkip) throw err;
				lastError = err instanceof Error ? err.message : String(err);
			}
			if (Date.now() - started >= timeout) break;
			await sleep(this.opts.interval ?? POLL_INTERVAL_MS);
		}
		const got = lastError !== "" ? `last try threw: ${lastError}` : `last value ${describeValue(last)}`;
		this.rec.add("wait", `${what} ${check.wants}`, false, `not within ${timeout / 1000} s; ${got}`);
		throw new PlaytestFailure(`expected ${what} ${check.wants} within ${timeout / 1000} s; ${got}`);
	}
}

export interface Expect {
	<V>(value: V, what?: string): Matchers<V, void>;
	poll<T>(fn: () => T | Promise<T>, opts?: PollOptions): Matchers<T, Promise<T>>;
}

export function makeExpect(rec: Recorder): Expect {
	return Object.assign(<V>(value: V, what = "value"): Matchers<V, void> => new ValueMatchers(rec, value, what), {
		poll: <T>(fn: () => T | Promise<T>, opts: PollOptions = {}): Matchers<T, Promise<T>> => new PollMatchers(rec, fn, opts),
	});
}

// ---------------------------------------------------------------------------------------
// Games: one per process, each reached through its debug API

export interface PlayerInfo {
	path: string;
	node: string;
	peerId: number;
	playerName: string;
	dead: boolean;
	local: boolean;
	at: Vec3;
}

export interface GameState {
	role: string;
	mode: string;
	connected: boolean;
	peerId: number;
	players: PlayerInfo[];
	modules: string[];
	fps: number;
}

const field = (o: unknown, key: string): unknown => (typeof o === "object" && o !== null ? Reflect.get(o, key) : undefined);
const str = (v: unknown): string => (typeof v === "string" ? v : "");
const num = (v: unknown): number => (typeof v === "number" ? v : 0);

export function parseState(raw: unknown): GameState {
	const players = field(raw, "players");
	const modules = field(raw, "modules");
	return {
		role: str(field(raw, "role")),
		mode: str(field(raw, "mode")),
		connected: field(raw, "connected") === true,
		peerId: num(field(raw, "peer_id")),
		players: (Array.isArray(players) ? players : []).map((p: unknown) => ({
			path: str(field(p, "path")),
			node: str(field(p, "name")),
			peerId: num(field(p, "peer_id")),
			playerName: str(field(p, "player_name")),
			dead: field(p, "dead") === true,
			local: field(p, "local") === true,
			at: parseVec3(field(p, "at")) ?? parseVec3(field(p, "position")) ?? [0, 0, 0],
		})),
		modules: (Array.isArray(modules) ? modules : []).filter((m: unknown): m is string => typeof m === "string"),
		fps: num(field(raw, "fps")),
	};
}

const regionText = (r: Region): string => `x ${r.x.toFixed(2)}+${r.w.toFixed(2)}, y ${r.y.toFixed(2)}+${r.h.toFixed(2)}`;

export class Shot {
	readonly record: ShotRecord;
	readonly path: string;
	private readonly rec: Recorder;
	private decoded: Image | undefined;
	constructor(rec: Recorder, record: ShotRecord, path: string) {
		this.rec = rec;
		this.record = record;
		this.path = path;
	}

	image(): Image | undefined {
		if (this.path === "") return undefined;
		this.decoded ??= decodePng(readFileSync(this.path));
		return this.decoded;
	}

	private check(title: string, ok: boolean, detail: string): void {
		const c: ImageCheck = { title, ok, detail };
		this.record.checks.push(c);
		this.rec.add("assert", `${this.record.name}: ${title}`, ok, detail);
	}

	// At least `minPixels` pixels within `tolerance` of `colour` in `region`. Recorded, never
	// thrown: one picture's check failing should not stop the rest being taken.
	hasColour(opts: { colour: string; tolerance?: number; region?: Region; minPixels?: number; what?: string }): boolean {
		const img = this.image();
		const what = opts.what ?? `has ${opts.colour}`;
		if (img === undefined) return true;
		const m = findColour(img, parseColour(opts.colour), opts.tolerance ?? 40, opts.region ?? WHOLE);
		const ok = m.count >= (opts.minPixels ?? 1);
		this.check(what, ok, `${m.count} px within ${opts.tolerance ?? 40} in ${regionText(opts.region ?? WHOLE)}${m.centre !== undefined ? ` around (${m.centre[0].toFixed(2)}, ${m.centre[1].toFixed(2)})` : ""}; nearest rgb(${m.nearest.join(", ")}) at ${m.distance}`);
		return ok;
	}

	lacksColour(opts: { colour: string; tolerance?: number; region?: Region; maxPixels?: number; what?: string }): boolean {
		const img = this.image();
		const what = opts.what ?? `lacks ${opts.colour}`;
		if (img === undefined) return true;
		const m = findColour(img, parseColour(opts.colour), opts.tolerance ?? 40, opts.region ?? WHOLE);
		const ok = m.count <= (opts.maxPixels ?? 0);
		this.check(what, ok, `${m.count} px within ${opts.tolerance ?? 40} in ${regionText(opts.region ?? WHOLE)}`);
		return ok;
	}

	// At least `minPixels` pixels in `region` became `by` (luma, 0..255) brighter since `before`.
	brighterThan(before: Shot, opts: { by?: number; region?: Region; minPixels?: number; what?: string }): boolean {
		const a = before.image();
		const b = this.image();
		const what = opts.what ?? `brighter than ${before.record.name}`;
		if (a === undefined || b === undefined) return true;
		const count = brighterPixels(a, b, opts.by ?? 60, opts.region ?? WHOLE);
		const ok = count >= (opts.minPixels ?? 1);
		this.check(what, ok, `${count} px at least ${opts.by ?? 60} brighter than in ${before.record.name}`);
		return ok;
	}

	// Mean brightness 0..255 of a region; not a check by itself.
	luma(region: Region = WHOLE): number {
		const img = this.image();
		return img === undefined ? 0 : meanLuma(img, region);
	}
}

export class NodeHandle {
	private readonly game: Game;
	readonly path: string;
	constructor(game: Game, path: string) {
		this.game = game;
		this.path = path;
	}
	// A property as plain JSON (vectors as arrays), script variables too.
	async get(property: string): Promise<unknown> {
		return field(await this.game.rpc("get", { path: this.path, property }), "value");
	}
	async set(property: string, value: GodotValue): Promise<void> {
		await this.game.rpc("set", { path: this.path, property, value: godotValue(value) });
	}
	// Class, script, stored properties and children.
	async describe(): Promise<unknown> {
		return this.game.rpc("node", { path: this.path });
	}
	async exists(): Promise<boolean> {
		return this.game.rpc("node", { path: this.path }).then(
			() => true,
			() => false,
		);
	}
}

export class Game {
	readonly name: string;
	readonly role: "server" | "client";
	api: ApiGame | undefined;
	private readonly run: PlayRun;
	constructor(run: PlayRun, name: string, role: "server" | "client") {
		this.run = run;
		this.name = name;
		this.role = role;
	}

	async rpc(method: string, params: Record<string, unknown> = {}, timeoutMs = 10_000): Promise<unknown> {
		if (this.run.rec.closed) throw new PlaytestFailure("the run is over");
		if (this.api === undefined) throw new Error(`${this.name} has no debug API yet`);
		try {
			return await rpc(this.api, method, params, timeoutMs);
		} catch (err) {
			throw new Error(`${this.name}: ${method} ${describeValue(params, 160)}: ${err instanceof Error ? err.message : String(err)}`);
		}
	}

	async state(): Promise<GameState> {
		return parseState(await this.rpc("state"));
	}

	node(path: string): NodeHandle {
		return new NodeHandle(this, path);
	}

	async find(pattern: string, type = "", limit = 50): Promise<{ path: string; cls: string }[]> {
		const found = await this.rpc("find_nodes", { pattern, type, limit });
		return (Array.isArray(found) ? found : []).map((f: unknown) => ({ path: str(field(f, "path")), cls: str(field(f, "class")) }));
	}

	async publish(topic: string, payload: Record<string, unknown> = {}): Promise<void> {
		await this.rpc("publish", { topic, payload });
		this.run.rec.add("action", `${this.name}: publish ${topic} ${describeValue(payload, 120)}`, true);
	}

	// An allow-listed module method (DebugHandler.CALLS), e.g. "inventory:server_give".
	async call(target: string, ...args: GodotValue[]): Promise<unknown> {
		return this.rpc("call", { target, args: args.map(godotValue) });
	}

	// One of this process's settings (DebugHandler.SETTINGS: colour_blind, coop_marker,
	// compass, blood), as the settings screen changes it; never saved to the settings file.
	async setting(key: string, value: boolean): Promise<void> {
		const got = await this.rpc("setting", { key, value });
		this.run.rec.add("action", `${this.name}: setting ${key} = ${describeValue(value)}`, got === value, got === value ? undefined : `reads back ${describeValue(got)}`);
		if (got !== value) throw new PlaytestFailure(`${this.name}: setting ${key} reads back ${describeValue(got)}`);
	}

	async log(lines = 50): Promise<string> {
		return str(await this.rpc("log", { lines }));
	}

	async perf(): Promise<unknown> {
		return this.rpc("perf");
	}

	async waitFor(what: string, test: (s: GameState) => boolean, timeout = DEFAULT_POLL_MS): Promise<GameState> {
		let state: GameState | undefined;
		await this.run.expect
			.poll(
				async () => {
					state = await this.state();
					return test(state);
				},
				{ what: `${this.name}: ${what}`, timeout },
			)
			.toBe(true);
		if (state === undefined) throw new Error("unreachable: the poll passed without a state");
		return state;
	}

	// What this window shows now, saved into the run folder with what it should show; the
	// reviewer gets the picture and `expect`, never the code.
	// Client: the world scene is in and the terrain round its own player is built (meshes and
	// collision), so a screenshot shows the place and not the grey void before it streams in.
	async worldReady(radius = WORLD_READY_RADIUS, timeout = CLIENT_READY_MS): Promise<void> {
		await this.run.expect
			.poll(
				async () => {
					const self = (await this.state()).players.find((p) => p.local);
					return self !== undefined && (await this.call("world:is_ready_at", vec3(self.at), float(radius))) === true;
				},
				{ what: `${this.name}: the world round its player`, timeout },
			)
			.toBe(true);
	}

	async screenshot(name: string, opts: { expect: string }): Promise<Shot> {
		if (!/^[\w-]+$/.test(name)) throw new Error(`screenshot names are letters, digits, - and _: ${name}`);
		const record: ShotRecord = { name, client: this.name, file: "", expect: opts.expect, at: this.run.rec.since(), checks: [] };
		this.run.rec.shots.push(record);
		if (this.run.headless || this.role === "server") {
			this.run.rec.add("shot", `${this.name}: ${name} (not taken: ${this.role === "server" ? "the server has no screen" : "headless run"})`, true);
			return new Shot(this.run.rec, record, "");
		}
		await this.worldReady();
		// A finished mesh shows on the next drawn frame; this covers a few at any playable rate.
		await sleep(SETTLE_MS);
		const taken = await this.rpc("screenshot");
		const from = str(field(taken, "path"));
		if (from === "" || !existsSync(from)) throw new Error(`${this.name}: the game returned no screenshot file`);
		const file = `shots/${String(this.run.rec.shots.length).padStart(2, "0")}-${this.name}-${name}.png`;
		mkdirSync(join(this.run.outDir, "shots"), { recursive: true });
		copyFileSync(from, join(this.run.outDir, file));
		rmSync(from, { force: true });
		record.file = file;
		this.run.rec.add("shot", `${this.name}: ${name}`, true, opts.expect);
		return new Shot(this.run.rec, record, join(this.run.outDir, file));
	}
}

// ---------------------------------------------------------------------------------------
// The session: server and clients, and the helpers that act on a named player

export interface SessionOptions {
	// One windowed client per name, joined in this order.
	clients: readonly string[];
	// `--start=` for every process (e.g. "city").
	start?: string;
	// Time of day once everyone is in: an hour, or day (12) / night (23).
	time?: "day" | "night" | number;
	// Extra arguments for every process after `--` (e.g. --flags=enemies:off).
	args?: readonly string[];
}

// Looking at a player aims here above their feet: their chest, where the marker's sight
// check aims too (coop_marker.json aim_height_m is 1.4).
const CHEST_HEIGHT = 1.2;
const NIGHT_HOUR = 23;
const DAY_HOUR = 12;
// More than any health in the game: a kill.
const KILL_DAMAGE = 100_000;
// Feet this far above the ground on a teleport: the body drops onto it, not through it.
const GROUND_CLEARANCE = 0.2;
const WALK_WITHIN_M = 1;
const WALK_POLL_MS = 150;
const FIRE_TIMEOUT_MS = 5_000;
const RELEASE_MS = 150;
// WeaponsModule.WEAPON_SLOTS, in the order weapon_slot counts them.
export const WEAPON_SLOTS = ["primary", "secondary"] as const;
// The player's one-shot intent actions (PlayerIntent.ONE_SHOTS).
export const ONE_SHOTS = ["jump", "interact", "reload", "throw", "detonate", "weapon_1", "weapon_2", "back_to_spawn", "glowstick", "glowstick_drop"] as const;
export type OneShot = (typeof ONE_SHOTS)[number];

export interface IntentInput {
	// x strafe right, y forward, each -1..1.
	move?: readonly [number, number];
	sprint?: boolean;
	crouch?: boolean;
	fire?: boolean;
	aim?: boolean;
}

export class Session {
	readonly server: Game;
	private readonly clients = new Map<string, Game>();
	private readonly run: PlayRun;
	constructor(run: PlayRun, server: Game) {
		this.run = run;
		this.server = server;
	}

	addClient(game: Game): void {
		this.clients.set(game.name, game);
	}

	client(name: string): Game {
		const g = this.clients.get(name);
		if (g === undefined) throw new Error(`no client ${name}; this session has ${[...this.clients.keys()].join(", ")}`);
		return g;
	}

	get clientNames(): string[] {
		return [...this.clients.keys()];
	}

	// The named player as the server has them.
	async player(name: string): Promise<PlayerInfo> {
		const p = (await this.server.state()).players.find((x) => x.playerName === name);
		if (p === undefined) throw new Error(`the server has no player named ${name}`);
		return p;
	}

	async position(name: string): Promise<Vec3> {
		return (await this.player(name)).at;
	}

	// Skips the scenario (not a failure) when a module it is about is switched off.
	async requireModules(...ids: string[]): Promise<void> {
		const loaded = new Set((await this.server.state()).modules);
		const missing = ids.filter((id) => !loaded.has(id));
		if (missing.length > 0) throw new PlaytestSkip(`module(s) off: ${missing.join(", ")}`);
	}

	// Server: moves the player there (out of any car, held until the ground under them exists)
	// and waits until the server and their own window have them there.
	async teleport(name: string, at: Vec3): Promise<void> {
		const p = await this.player(name);
		await this.server.call("player:server_move_to", nodePath(p.path), vec3(at));
		this.run.rec.add("action", `teleport ${name} to ${at.map((n) => n.toFixed(1)).join(", ")}`, true);
		const near = (v: Vec3): boolean => Math.hypot(v[0] - at[0], v[2] - at[2]) < 1.0;
		await this.run.expect.poll(async () => near((await this.player(name)).at), { what: `${name} within 1 m of the target on the server`, timeout: 20_000 }).toBe(true);
		const own = this.clients.get(name);
		if (own !== undefined) await own.waitFor(`sees itself at the teleport target`, (s) => s.players.some((x) => x.local && near(x.at)), 20_000);
	}

	// Server: sets the intent's continuous parts. Clients run with --bot=playtest, so no
	// keyboard or mouse overwrites it.
	async intent(name: string, input: IntentInput): Promise<void> {
		const intent = this.server.node(`${(await this.player(name)).path}/Intent`);
		if (input.move !== undefined) await intent.set("move", vec2(input.move));
		for (const key of ["sprint", "crouch", "fire", "aim"] as const) {
			const v = input[key];
			if (v !== undefined) await intent.set(key, v);
		}
		this.run.rec.add("action", `${name} intent ${describeValue(input, 120)}`, true);
	}

	// Server: turns the player's body and head (yaw around Y, pitch up positive, radians).
	async look(name: string, yaw: number, pitch = 0): Promise<void> {
		const intent = this.server.node(`${(await this.player(name)).path}/Intent`);
		await intent.set("look_yaw", float(yaw));
		await intent.set("look_pitch", float(pitch));
		await intent.set("remote_look", true);
	}

	// Turns `name`'s eyes towards a point or another player's chest, and waits until their
	// own window shows the turn. `yawOffset` (radians, positive to the left) looks a little
	// past it, so the crosshair does not cover what a screenshot is about.
	async lookAt(name: string, target: Vec3 | string, opts: { yawOffset?: number } = {}): Promise<void> {
		const p = await this.player(name);
		const eye = parseVec3(await this.server.node(`${p.path}/Head`).get("global_position")) ?? [p.at[0], p.at[1] + 1.6, p.at[2]];
		const other = typeof target === "string" ? await this.position(target) : undefined;
		const to: Vec3 = other !== undefined ? [other[0], other[1] + CHEST_HEIGHT, other[2]] : typeof target === "string" ? [0, 0, 0] : target;
		const aim = yawPitchTo(eye, to);
		const yaw = aim.yaw + (opts.yawOffset ?? 0);
		await this.look(name, yaw, aim.pitch);
		this.run.rec.add("action", `${name} looks at ${typeof target === "string" ? target : to.map((n) => n.toFixed(1)).join(", ")}`, true);
		const own = this.clients.get(name);
		if (own === undefined) return;
		const self = (await own.state()).players.find((x) => x.local);
		if (self === undefined) return;
		const facing = (v: unknown): boolean => typeof v === "number" && Math.abs(Math.atan2(Math.sin(v - yaw), Math.cos(v - yaw))) < 0.05;
		await this.run.expect.poll(async () => parseVec3(await own.node(self.path).get("rotation"))?.[1], { what: `${name}'s window turned`, timeout: 10_000 }).toSatisfy(facing, `to face yaw ${yaw.toFixed(2)}`);
	}

	// Server: a one-shot action as if its key was pressed once (glowstick, interact, jump...).
	async action(name: string, action: OneShot): Promise<void> {
		await this.server.node(`${(await this.player(name)).path}/Intent`).set(action, true);
		this.run.rec.add("action", `${name} presses ${action}`, true);
	}

	// Server: jumps the clock for everyone.
	async setTime(time: "day" | "night" | number): Promise<void> {
		const hour = time === "night" ? NIGHT_HOUR : time === "day" ? DAY_HOUR : time;
		await this.server.call("daytime:server_set_hour", float(hour));
		this.run.rec.add("action", `time set to ${hour}:00`, true);
	}

	// Server: puts an item in the player's gear; fails the run when it does not fit.
	async give(name: string, item: string): Promise<void> {
		const p = await this.player(name);
		const given = await this.server.call("inventory:server_give", p.peerId, item);
		this.run.rec.add("action", `give ${name} ${item}`, given === true, given === true ? undefined : "refused (no room, or no such item)");
		if (given !== true) throw new PlaytestFailure(`could not give ${name} ${item}`);
	}

	async count(name: string, item: string): Promise<number> {
		return num(await this.server.call("inventory:count", (await this.player(name)).peerId, item));
	}

	// Server: the player's health now (their HealthComponent).
	async health(name: string): Promise<number> {
		return num(await this.server.node(`${(await this.player(name)).path}/Health`).get("health"));
	}

	// Server: hurts the player as a hit with no shooter would; returns the damage dealt (none
	// in god mode or when already dead).
	async damage(name: string, amount: number): Promise<number> {
		const dealt = num(await this.server.call("player:server_damage", nodePath((await this.player(name)).path), float(amount)));
		this.run.rec.add("action", `${name} takes ${amount} damage`, true, `${dealt} dealt`);
		return dealt;
	}

	// Server: kills the player and waits until the server has them dead.
	async kill(name: string): Promise<void> {
		await this.damage(name, KILL_DAMAGE);
		await this.server.waitFor(`has ${name} dead`, (st) => st.players.some((p) => p.playerName === name && p.dead), 10_000);
	}

	// Server: the untouched ground's height at (x, z) (buildings are not in it).
	async ground(x: number, z: number): Promise<number> {
		const h = await this.server.call("world:ground_height", float(x), float(z));
		if (typeof h !== "number") throw new Error(`the server has no ground height at ${x}, ${z} (no world loaded?)`);
		return h;
	}

	// A point on the ground at (x, z), a little above it so the body settles onto it.
	async onGround(x: number, z: number): Promise<Vec3> {
		return [x, (await this.ground(x, z)) + GROUND_CLEARANCE, z];
	}

	// Server: walks the player to `to` (only x and z count) by steering their intent, facing
	// the way they go, and waits on the wall clock until they are within `within` metres. Fails
	// the step with where they got stuck when `timeoutMs` (by default three times the time at
	// walking pace) runs out. Stops them either way.
	async walkTo(name: string, to: Vec3, opts: { within?: number; timeoutMs?: number } = {}): Promise<void> {
		const within = opts.within ?? WALK_WITHIN_M;
		const p = await this.player(name);
		const timeout = opts.timeoutMs ?? walkTimeoutMs(flatDistance(p.at, to));
		const intent = this.server.node(`${p.path}/Intent`);
		const started = Date.now();
		let at = p.at;
		let s = steer(at, to, within);
		try {
			while (!s.arrived) {
				if (this.run.rec.closed) throw new PlaytestFailure("the run is over");
				if (Date.now() - started >= timeout) {
					const where = at.map((n) => n.toFixed(1)).join(", ");
					this.run.rec.add("action", `${name} walks to ${to[0].toFixed(1)}, ${to[2].toFixed(1)}`, false, `stuck at ${where}, ${s.distance.toFixed(1)} m short after ${timeout / 1000} s`);
					throw new PlaytestFailure(`${name} did not reach ${to[0].toFixed(1)}, ${to[2].toFixed(1)} within ${timeout / 1000} s; stuck at ${where}, ${s.distance.toFixed(1)} m short`);
				}
				await intent.set("look_yaw", float(s.yaw));
				await intent.set("look_pitch", float(0));
				await intent.set("remote_look", true);
				await intent.set("move", vec2([0, s.forward]));
				await sleep(WALK_POLL_MS);
				at = (await this.player(name)).at;
				s = steer(at, to, within);
			}
		} finally {
			// A game that died mid-walk must not hide why the walk failed.
			if (!this.run.rec.closed) await intent.set("move", vec2([0, 0])).catch(() => {});
		}
		this.run.rec.add("action", `${name} walks to ${to[0].toFixed(1)}, ${to[2].toFixed(1)}`, true, `${s.distance.toFixed(1)} m off after ${((Date.now() - started) / 1000).toFixed(1)} s`);
		const own = this.clients.get(name);
		if (own !== undefined) await own.waitFor("sees itself where it walked to", (st) => st.players.some((x) => x.local && flatDistance(x.at, to) <= within + 0.5), 10_000);
	}

	// The drawn gun on the server and its rounds as the player's own game last heard them from
	// the server (-1 before it has).
	private async gun(name: string): Promise<{ server: NodeHandle; rounds: number }> {
		const p = await this.player(name);
		const slot = num(await this.server.node(`${p.path}/Intent`).get("weapon_slot"));
		const path = `${p.path}/Head/Camera/Weapon_${WEAPON_SLOTS[slot] ?? "primary"}`;
		const ammo = await this.client(name).node(path).get("_synced_ammo");
		return { server: this.server.node(path), rounds: typeof ammo === "number" ? ammo : -1 };
	}

	private async rounds(name: string): Promise<number> {
		return (await this.gun(name)).rounds;
	}

	// Server: aims the player at a point or another player's chest and pulls the trigger until
	// at least `shots` rounds have left the drawn gun (read from the owner's magazine count). A
	// pull per round for a pistol; an automatic gun may let go of one or two more before the
	// release reaches it. Returns the rounds fired; fails when a pull fires nothing in time.
	async fire(name: string, at: Vec3 | string, opts: { shots?: number; timeoutMs?: number } = {}): Promise<number> {
		const shots = opts.shots ?? 1;
		await this.lookAt(name, at);
		const intent = this.server.node(`${(await this.player(name)).path}/Intent`);
		await this.run.expect.poll(() => this.rounds(name), { what: `${name}'s magazine`, timeout: 10_000 }).toBeGreaterThan(0);
		let fired = 0;
		try {
			while (fired < shots) {
				// A trigger held through a draw (or the last pull) is not a new pull: let go first,
				// and pull only once the gun is out (a semi-automatic counts a pull during the draw
				// as held from then on).
				await intent.set("fire", false);
				const { server } = await this.gun(name);
				await this.run.expect.poll(async () => num(await server.get("_draw_left")), { what: `${name}'s gun drawn on the server`, timeout: 10_000 }).toSatisfy((v) => v <= 0, "to be out");
				await sleep(RELEASE_MS);
				const before = await this.rounds(name);
				if (before <= 0) break;
				await intent.set("fire", true);
				// Added up pull by pull, so a reload in between does not reset the count.
				fired += await this.run.expect.poll(async () => roundsFired(before, await this.rounds(name)), { what: `rounds out of ${name}'s gun`, timeout: opts.timeoutMs ?? FIRE_TIMEOUT_MS, interval: 50 }).toBeGreaterThan(0);
				await intent.set("fire", false);
			}
		} finally {
			if (!this.run.rec.closed) await intent.set("fire", false).catch(() => {});
		}
		this.run.rec.add("action", `${name} fires at ${typeof at === "string" ? at : at.map((n) => n.toFixed(1)).join(", ")}`, fired >= shots, `${fired} round(s)`);
		return fired;
	}

	// Walks the player to the first car and presses interact; waits until they sit in it.
	async enterCar(name: string): Promise<string> {
		const cars = await this.server.find("Car*", "VehicleBody3D", 10);
		const car = cars[0];
		if (car === undefined) throw new PlaytestFailure("no car in the world");
		const at = parseVec3(await this.server.node(car.path).get("global_position"));
		if (at === undefined) throw new Error(`cannot read where ${car.path} is`);
		await this.teleport(name, [at[0] + 2.5, at[1] + 0.5, at[2]]);
		await this.action(name, "interact");
		const p = await this.player(name);
		await this.run.expect.poll(async () => this.server.call("car:occupied_seats"), { what: `${name} in ${car.path}`, timeout: 10_000 }).toSatisfy((v) => Array.isArray(v) && v.some((s: unknown) => field(s, "player") === p.path), "to list them in a seat");
		return car.path;
	}
}

// ---------------------------------------------------------------------------------------
// A run: the processes, the perf sampler and the scenario's context

export interface PlaytestMeta {
	title: string;
	// Modules the scenario is about: with one off, the run is skipped, not failed.
	needs?: readonly string[];
	// Error lines that are expected in this scenario's logs (the gate's own noise always is).
	allowErrors?: readonly RegExp[];
}

export interface PlayContext {
	// Starts the server and the named clients; one session per run.
	session(opts: SessionOptions): Promise<Session>;
	expect: Expect;
	// A heading in the report; with `fn`, runs it under that heading.
	step(title: string, fn?: () => Promise<void>): Promise<void>;
	note(text: string): void;
	// Clients are headless (state only, screenshots are recorded as not taken).
	headless: boolean;
}

export class Playtest {
	readonly meta: PlaytestMeta;
	readonly run: (t: PlayContext) => Promise<void>;
	constructor(meta: PlaytestMeta, run: (t: PlayContext) => Promise<void>) {
		this.meta = meta;
		this.run = run;
	}
}

export const playtest = (meta: PlaytestMeta, run: (t: PlayContext) => Promise<void>): Playtest => new Playtest(meta, run);

export interface RunConfig {
	root: string;
	godot: string;
	outDir: string;
	port: number;
	headless: boolean;
	// Whole run, start to teardown; each process gets a little longer as its own backstop.
	timeoutMs: number;
	// --keep: the processes outlive the scenario until Ctrl-C, so their own backstop is long.
	keep: boolean;
	needs: readonly string[];
}

interface Proc {
	game: Game;
	log: string;
	output: string;
	pid: number | undefined;
	done: Promise<ProcResult>;
	ended: boolean;
}

// Booting the world and loading every module; on a cold shader cache a first run is slow.
const SERVER_READY_MS = 180_000;
const CLIENT_READY_MS = 180_000;
const PERF_EVERY_MS = 5_000;
// A kept session ends on Ctrl-C; this only stops one left running and forgotten.
const KEEP_BACKSTOP_MS = 24 * 3600 * 1000;
// Terrain that must be built round a client's player before a screenshot (metres).
const WORLD_READY_RADIUS = 40;
const SETTLE_MS = 300;
const WINDOW = { width: 960, height: 540, gap: 20 } as const;

export class PlayRun {
	readonly rec = new Recorder();
	readonly expect: Expect;
	readonly outDir: string;
	readonly headless: boolean;
	readonly port: number;
	private readonly cfg: RunConfig;
	private readonly userDir = godotUserDir(platform, env, homedir());
	private readonly procs: Proc[] = [];
	private readonly perfSamples = new Map<string, PerfSample[]>();
	private perfTimer: NodeJS.Timeout | undefined;
	private opened = false;

	constructor(cfg: RunConfig) {
		this.cfg = cfg;
		this.outDir = cfg.outDir;
		this.headless = cfg.headless;
		this.port = cfg.port;
		this.expect = makeExpect(this.rec);
		mkdirSync(join(cfg.outDir, "logs"), { recursive: true });
	}

	context(): PlayContext {
		return {
			session: (opts) => this.openSession(opts),
			expect: this.expect,
			step: async (title, fn) => {
				this.rec.add("step", title, true);
				if (fn !== undefined) await fn();
			},
			note: (text) => this.rec.add("note", text, true),
			headless: this.headless,
		};
	}

	private start(name: string, role: "server" | "client", userArgs: readonly string[], window: number): Proc {
		const log = resolvePath(this.outDir, "logs", `${name}.log`);
		const screen = role === "server" || this.headless ? ["--headless"] : ["--resolution", `${WINDOW.width}x${WINDOW.height}`, "--position", `${WINDOW.gap + (window % 2) * (WINDOW.width + WINDOW.gap)},${40 + Math.floor(window / 2) * (WINDOW.height + 60)}`];
		const proc: Proc = { game: new Game(this, name, role), log, output: "", pid: undefined, done: Promise.resolve({ code: 0, output: "", timedOut: false }), ended: false };
		// Godot keeps its own --log-file from scripts; the copy after -- tells the debug API.
		const watched: Watched = watch(this.cfg.godot, [...screen, "--log-file", log, "--path", this.cfg.root, "--", ...userArgs, "--debug-api", `--log-file=${log}`], {
			cwd: this.cfg.root,
			timeoutMs: this.cfg.keep ? KEEP_BACKSTOP_MS : this.cfg.timeoutMs + 60_000,
			onSpawn: (pid) => (proc.pid = pid),
		});
		proc.done = watched.done.then(
			(r) => {
				proc.ended = true;
				proc.output = r.output;
				return r;
			},
			(err: unknown) => {
				proc.ended = true;
				proc.output = `could not start ${this.cfg.godot}: ${err instanceof Error ? err.message : String(err)}`;
				return { code: -1, output: proc.output, timedOut: false };
			},
		);
		this.procs.push(proc);
		return proc;
	}

	private async waitForApi(proc: Proc, timeoutMs: number): Promise<void> {
		const started = Date.now();
		while (Date.now() - started < timeoutMs) {
			if (proc.ended) throw new Error(`${proc.game.name} quit before its debug API came up; its log: ${proc.log}`);
			const api = apiForLog(discover(this.userDir), proc.log);
			if (api !== undefined) {
				const alive = await rpc(api, "ping", {}, 2000).then(
					() => true,
					() => false,
				);
				if (alive) {
					proc.game.api = api;
					return;
				}
			}
			await sleep(POLL_INTERVAL_MS);
		}
		throw new Error(`${proc.game.name}: no debug API after ${timeoutMs / 1000} s; its log: ${proc.log}`);
	}

	async openSession(opts: SessionOptions): Promise<Session> {
		if (this.opened) throw new Error("one session per playtest run");
		this.opened = true;
		if (opts.clients.length === 0) throw new Error("a session needs at least one client");
		if (new Set(opts.clients).size !== opts.clients.length || opts.clients.some((n) => !/^[A-Za-z][A-Za-z0-9]*$/.test(n))) throw new Error(`client names must be distinct single words: ${opts.clients.join(", ")}`);
		const shared = [...(opts.start !== undefined ? [`--start=${opts.start}`] : []), ...(opts.args ?? [])];
		// --no-save: a playtest never touches the player's own world.
		const server = this.start("server", "server", [`--server=${this.port}`, "--no-save", ...shared], 0);
		this.rec.add("step", `server on port ${this.port}${opts.start !== undefined ? `, starting in ${opts.start}` : ""}`, true);
		await this.waitForApi(server, SERVER_READY_MS);
		const session = new Session(this, server.game);
		// Loading modules is the last thing the server does before it takes players.
		await this.expect.poll(async () => (await server.game.state()).modules.length, { what: "the server's modules", timeout: SERVER_READY_MS }).toBeGreaterThan(0);
		await session.requireModules(...this.cfg.needs);
		// --bot=playtest: no keyboard or mouse (the intent is the run's alone), the mouse is
		// never captured and the window runs without focus; no module drives that name.
		const clients = opts.clients.map((name, i) => this.start(name, "client", [`--connect=127.0.0.1:${this.port}`, `--name=${name}`, "--bot=playtest", ...shared], i));
		for (const c of clients) {
			await this.waitForApi(c, CLIENT_READY_MS);
			session.addClient(c.game);
		}
		for (const c of clients) {
			const name = c.game.name;
			await server.game.waitFor(`has ${name}'s player`, (s) => s.players.some((p) => p.playerName === name && !p.dead), CLIENT_READY_MS);
			await c.game.waitFor("has its own player in the world", (s) => s.connected && s.players.some((p) => p.local), CLIENT_READY_MS);
			await c.game.worldReady();
		}
		if (opts.time !== undefined) await session.setTime(opts.time);
		this.startPerf();
		return session;
	}

	private startPerf(): void {
		this.perfTimer = setInterval(() => {
			for (const p of this.procs) {
				if (p.ended || p.game.api === undefined) continue;
				p.game.perf().then(
					(rec) => {
						const frames = num(field(rec, "frames"));
						if (frames <= 0) return;
						const list = this.perfSamples.get(p.game.name) ?? [];
						list.push({ fps: num(field(rec, "fps")), p95: num(field(rec, "frame_ms_p95")), max: num(field(rec, "frame_ms_max")) });
						this.perfSamples.set(p.game.name, list);
					},
					() => {},
				);
			}
		}, PERF_EVERY_MS);
	}

	// Whether any process this run started is still going (for --keep).
	running(): boolean {
		return this.procs.some((p) => !p.ended);
	}

	// Who is running, for --keep.
	describeProcesses(): string[] {
		return this.procs.map((p) => `${p.game.name}: pid ${p.pid ?? "?"}, debug API port ${p.game.api?.port ?? "?"}, log ${p.log}`);
	}

	// Ends every process this run started, and the debug API files a kill leaves behind.
	async close(): Promise<void> {
		this.killAll();
		await Promise.all(this.procs.map((p) => Promise.race([p.done, sleep(15_000)])));
	}

	killAll(): void {
		this.rec.closed = true;
		if (this.perfTimer !== undefined) clearInterval(this.perfTimer);
		for (const p of this.procs) {
			// A pid the OS has handed on would take an unrelated process tree with it on Windows.
			if (p.pid !== undefined && !p.ended) killTree(p.pid);
			if (p.game.api !== undefined) rmSync(p.game.api.file, { force: true });
		}
	}

	logs(allow: readonly RegExp[]): LogRecord[] {
		return this.procs.map((p) => {
			// The pipe has everything up to the kill; the log file is the fallback when the
			// process is still running (an interrupted run).
			const text = p.output !== "" ? p.output : existsSync(p.log) ? readFileSync(p.log, "utf8") : "";
			const scan = scanPlayLog(text, allow);
			return { process: p.game.name, file: `logs/${p.game.name}.log`, ...scan };
		});
	}

	perf(): PerfRecord[] {
		return [...this.perfSamples.entries()].map(([name, samples]) => summarisePerf(name, samples));
	}
}
