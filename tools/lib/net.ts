import { createSocket } from "node:dgram";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join as pathJoin } from "node:path";
import { GODOT_NOISE, type StepResult } from "./gate.ts";
import { scanLog } from "./log-scan.ts";
import { run, type ProcResult, type RunOptions } from "./proc.ts";

export interface NetReport {
	mode: string;
	peer: number;
	peers: number;
	players: number;
	localPlayers: number;
	moved: number;
	shots: number;
	driven: number;
	ammo: number;
	parked: number;
	drivers: number;
}

export function parseReport(output: string): NetReport | undefined {
	const m = /NET-REPORT mode=(\w+) peer=(\d+) peers=(\d+) players=(\d+) local_players=(\d+) moved=([\d.]+) shots=(\d+) driven=([\d.]+) ammo=(-?\d+) parked=(\d+) drivers=(\d+)/.exec(output);
	if (m === null) return undefined;
	return {
		mode: m[1] ?? "",
		peer: Number(m[2]),
		peers: Number(m[3]),
		players: Number(m[4]),
		localPlayers: Number(m[5]),
		moved: Number(m[6]),
		shots: Number(m[7]),
		driven: Number(m[8]),
		ammo: Number(m[9]),
		parked: Number(m[10]),
		drivers: Number(m[11]),
	};
}

export interface SoloServerLine {
	pid: number;
	port: number;
	log: string;
}

export function parseSoloServer(output: string): SoloServerLine | undefined {
	const m = /solo server pid=(\d+) port=(\d+) log=(.+?)\r?$/m.exec(output);
	if (m === null) return undefined;
	return { pid: Number(m[1]), port: Number(m[2]), log: m[3] ?? "" };
}

function isRunning(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

const delay = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

// True when nothing on this machine holds UDP `port` (ENet's), on any address.
function udpFree(port: number): Promise<boolean> {
	return new Promise((resolve) => {
		const socket = createSocket("udp4");
		socket.once("error", () => {
			socket.close();
			resolve(false);
		});
		socket.bind(port, "0.0.0.0", () => socket.close(() => resolve(true)));
	});
}

// The first free UDP port from `preferred` on: a process left over from an earlier step, or a
// game the developer has running, must not turn a smoke check into a connection failure.
export async function freeUdpPort(preferred: number, tries = 50): Promise<number> {
	for (let port = preferred; port < preferred + tries; port++) if (await udpFree(port)) return port;
	throw new Error(`no free UDP port in ${preferred}..${preferred + tries - 1}`);
}

// A process whose output can be waited on while it runs.
export interface Watched {
	done: Promise<ProcResult>;
	// Resolves true once `pattern` shows in the output, false after `timeoutMs` or when the
	// process ended without it.
	sees(pattern: RegExp, timeoutMs: number): Promise<boolean>;
}

export function watch(cmd: string, args: readonly string[], opts: Omit<RunOptions, "onOutput">): Watched {
	let output = "";
	let ended = false;
	const waiters = new Set<() => void>();
	const done = run(cmd, args, {
		...opts,
		onOutput: (text) => {
			output += text;
			for (const w of [...waiters]) w();
		},
	});
	void done.finally(() => {
		ended = true;
		for (const w of [...waiters]) w();
	});
	const sees = (pattern: RegExp, timeoutMs: number): Promise<boolean> =>
		new Promise((resolve) => {
			const check = (): void => {
				if (pattern.test(output)) finish(true);
				else if (ended) finish(false);
			};
			const timer = setTimeout(() => finish(false), timeoutMs);
			const finish = (seen: boolean): void => {
				clearTimeout(timer);
				waiters.delete(check);
				resolve(seen);
			};
			waiters.add(check);
			check();
		});
	return { done, sees };
}

async function serverReady(server: Watched, name: string): Promise<string | undefined> {
	if (await server.sees(SERVER_READY, SERVER_READY_MS)) return undefined;
	return `${name}: never finished loading; it ended with:\n${lastLines((await server.done).output)}`;
}

// A server has its world built and is answering once Boot has loaded the modules; clients that
// knock earlier wait on a main loop that is not polling, and give up on a slow machine.
const SERVER_READY = /boot: loaded modules:/;
const SERVER_READY_MS = 120_000;

// The last lines a process printed, for a report that never came.
const lastLines = (output: string, count = 8): string =>
	output
		.trim()
		.split(/\r?\n/)
		.slice(-count)
		.map((l) => `    ${l}`)
		.join("\n");

// Solo is a client of a server process it starts itself. The bot's movement and shots must
// make the round trip, the server's own log must be clean, and the server must not outlive
// the game.
export async function soloSmoke(godot: string, root: string): Promise<StepResult> {
	// --no-save: a test must never touch the player's own solo world.
	const r = await run(godot, ["--headless", "--path", root, "--", "--net-report-after=900", "--bot=walk", "--no-save"], { cwd: root, timeoutMs: 120_000 });
	const problems: string[] = [];
	for (const line of scanLog(r.output, GODOT_NOISE)) problems.push(`solo: ${line}`);
	if (r.timedOut) problems.push("solo: timed out");
	const rep = parseReport(r.output);
	if (rep === undefined) problems.push(`solo: no NET-REPORT line; it ended with:\n${lastLines(r.output)}`);
	else {
		if (rep.mode !== "SOLO" || rep.peers !== 1 || rep.players !== 1 || rep.localPlayers !== 1) problems.push(`solo: wrong session shape: ${JSON.stringify(rep)}`);
		if (rep.moved < 3.0) problems.push(`solo: player did not move through the server (moved=${rep.moved})`);
		if (rep.shots < 1) problems.push("solo: saw no shots");
		// The bot fires and never reloads, so a working magazine sync shows fewer than full.
		if (rep.ammo < 0 || rep.ammo >= 30) problems.push(`solo: the game's ammo count did not follow the server (ammo=${rep.ammo})`);
	}
	const child = parseSoloServer(r.output);
	if (child === undefined) {
		problems.push("solo: no 'solo server pid=' line");
	} else {
		// It quits when its only player leaves, and within a second or so if the game vanished.
		for (let i = 0; i < 20 && isRunning(child.pid); i++) await delay(500);
		if (isRunning(child.pid)) {
			problems.push(`solo: server process ${child.pid} still running after the game quit`);
			process.kill(child.pid);
		}
		if (!existsSync(child.log)) problems.push(`solo: no server log at ${child.log}`);
		else for (const line of scanLog(readFileSync(child.log, "utf8"), GODOT_NOISE)) problems.push(`solo server: ${line}`);
	}
	return problems.length > 0
		? { ok: false, detail: problems.slice(0, 20).join("\n") }
		: { ok: true, detail: "solo runs through its own server process, which exits with the game" };
}

// A dedicated server plus two clients as real processes on localhost. Client 1 runs a bot
// that walks and fires, client 2 one that gets in the car and drives, both through the
// network intent path; the checks prove input reaches the server and the results
// (movement, shots, the car's new position) reach everyone.
export async function netSmoke(godot: string, root: string, preferredPort = 7791): Promise<StepResult> {
	const base = ["--headless", "--path", root, "--"];
	const port = await freeUdpPort(preferredPort);
	// Clients report 900 physics frames after their player is in the world and stay
	// connected; the server reports once it has counted 1300 from its first player and both
	// clients have reported, then quits, which closes the clients.
	const saves = mkdtempSync(pathJoin(tmpdir(), "slopocalypse-net-"));
	const server = watch(godot, [...base, `--server=${port}`, "--net-report-after=1300", `--save=${pathJoin(saves, "world.db")}`], { cwd: root, timeoutMs: 240_000 });
	const notReady = await serverReady(server, "server");
	if (notReady !== undefined) {
		rmSync(saves, { recursive: true, force: true });
		return { ok: false, detail: notReady };
	}
	const join = `--connect=127.0.0.1:${port}`;
	const clients = [
		run(godot, [...base, join, "--net-report-after=900", "--bot=walk"], { cwd: root, timeoutMs: 240_000 }),
		run(godot, [...base, join, "--net-report-after=900", "--bot=drive"], { cwd: root, timeoutMs: 240_000 }),
	];
	const results: [string, ProcResult][] = [["server", await server.done], ["client 1 (bot)", await clients[0]!], ["client 2", await clients[1]!]];
	rmSync(saves, { recursive: true, force: true });

	const problems: string[] = [];
	for (const [name, r] of results) {
		for (const line of scanLog(r.output, GODOT_NOISE)) problems.push(`${name}: ${line}`);
		if (r.timedOut) problems.push(`${name}: timed out`);
	}
	for (const [name, r] of results) {
		const rep = parseReport(r.output);
		if (rep === undefined) {
			problems.push(`${name}: no NET-REPORT line; it ended with:\n${lastLines(r.output)}`);
			continue;
		}
		const want = name === "server" ? { mode: "SERVER", peers: 2, local: 0 } : { mode: "CLIENT", peers: -1, local: 1 };
		if (rep.mode !== want.mode || rep.players !== 2 || rep.localPlayers !== want.local || (want.peers >= 0 && rep.peers !== want.peers)) {
			problems.push(`${name}: wrong session shape: ${JSON.stringify(rep)}`);
		}
		// The bot's player must have walked and fired, as seen by everyone, not only itself.
		if (rep.moved < 3.0) problems.push(`${name}: no player moved more than 3 m (moved=${rep.moved})`);
		if (rep.shots < 1) problems.push(`${name}: saw no shots`);
		if (rep.driven < 5.0) problems.push(`${name}: the car was not driven 5 m (driven=${rep.driven})`);
		if (name === "client 1 (bot)" && (rep.ammo < 0 || rep.ammo >= 30)) problems.push(`${name}: the ammo count did not follow the server (ammo=${rep.ammo})`);
	}
	return problems.length > 0
		? { ok: false, detail: problems.slice(0, 20).join("\n") }
		: { ok: true, detail: "server + 2 clients: walking, shooting and driving reach the server and everyone else" };
}

// What is wrong with one process of the late join smoke: its log, and whether it shows the
// one driver parked in the one driven car. `players` is how many players it must at least see.
function seatProblems(name: string, r: ProcResult, players: number): string[] {
	const problems = scanLog(r.output, GODOT_NOISE).map((line) => `${name}: ${line}`);
	if (r.timedOut) problems.push(`${name}: timed out`);
	const rep = parseReport(r.output);
	if (rep === undefined) return [...problems, `${name}: no NET-REPORT line; it ended with:\n${lastLines(r.output)}`];
	if (rep.players < players) problems.push(`${name}: wrong session shape: ${JSON.stringify(rep)}`);
	if (rep.parked !== 1) problems.push(`${name}: the driver's body is not hidden (parked=${rep.parked})`);
	if (rep.drivers !== 1) problems.push(`${name}: the car does not know its driver (drivers=${rep.drivers})`);
	return problems;
}

// Longest wait for the sitting client to get in before the late client starts anyway.
const SEAT_WAIT_MS = 90_000;

// Someone who joins after a player got in the car. Getting in is broadcast once, to whoever
// is connected then, so the late client only knows about it if the server catches it up
// (#433): it must show the driver parked and the car as driven, as the server does.
export async function lateJoinSmoke(godot: string, root: string, port = 7792): Promise<StepResult> {
	const base = ["--headless", "--path", root, "--"];
	const join = `--connect=127.0.0.1:${port}`;
	// The server counts from its first player and outlasts both clients' reports; the sitter
	// reports late enough to have walked to the car and got in.
	const server = run(godot, [...base, `--server=${port}`, "--net-report-after=2400", "--no-save"], { cwd: root, timeoutMs: 180_000 });
	await delay(4000);
	let markSeated = (): void => {};
	const seated = new Promise<void>((resolve) => (markSeated = resolve));
	let sitterOutput = "";
	const sitter = run(godot, [...base, join, "--net-report-after=900", "--bot=sit", "--name=Sitter"], {
		cwd: root,
		timeoutMs: 180_000,
		// CarBot.SEATED_LOG: the sitter is in the car, so the second client can knock.
		onOutput: (text) => {
			sitterOutput += text;
			if (sitterOutput.includes("bot seated")) markSeated();
		},
	});
	// A sitter that never sits ends (report or timeout) and fails below; don't wait past that.
	await Promise.race([seated, sitter, delay(SEAT_WAIT_MS)]);
	const late = run(godot, [...base, join, "--net-report-after=300", "--name=Late"], { cwd: root, timeoutMs: 180_000 });
	// The sitter may report before the late client is in; everyone else sees both players.
	const results: [string, ProcResult][] = [["server", await server], ["sitting client", await sitter], ["late client", await late]];
	const problems = results.flatMap(([name, r]) => seatProblems(name, r, name === "sitting client" ? 1 : 2));
	return problems.length > 0
		? { ok: false, detail: problems.slice(0, 20).join("\n") }
		: { ok: true, detail: "a client that joins after someone got in the car sees them in it" };
}

// Progress survives a server restart: a named bot walks off and the server stops (saving on
// the way out); a second server on the same file must put the same name back where it was,
// without that client moving at all.
export async function saveSmoke(godot: string, root: string, preferredPort = 7793): Promise<StepResult> {
	const base = ["--headless", "--path", root, "--"];
	const port = await freeUdpPort(preferredPort);
	const saves = mkdtempSync(pathJoin(tmpdir(), "slopocalypse-save-"));
	const save = `--save=${pathJoin(saves, "world.db")}`;
	const address = `--connect=127.0.0.1:${port}`;
	const problems: string[] = [];
	const check = (name: string, r: ProcResult): void => {
		for (const line of scanLog(r.output, GODOT_NOISE)) problems.push(`${name}: ${line}`);
		if (r.timedOut) problems.push(`${name}: timed out`);
	};
	try {
		const first = watch(godot, [...base, `--server=${port}`, "--net-report-after=1100", save], { cwd: root, timeoutMs: 240_000 });
		const firstNotReady = await serverReady(first, "first server");
		if (firstNotReady !== undefined) return { ok: false, detail: firstNotReady };
		const walker = await run(godot, [...base, address, "--net-report-after=900", "--bot=walk", "--name=Saver"], { cwd: root, timeoutMs: 240_000 });
		const firstServer = await first.done;
		check("first server", firstServer);
		check("walking client", walker);
		// The server reports in the same frame it stops and saves; the bot keeps walking
		// until then, so its own report is from earlier.
		const walked = parseReport(firstServer.output)?.moved ?? 0;
		if (walked < 3.0) {
			problems.push(`first server: Saver did not get 3 m from the spawn (moved=${walked})`);
			// Both sides' last lines say whether the bot never walked or the server never saw it.
			for (const [name, r] of [["first server", firstServer], ["walking client", walker]] as const)
				for (const line of r.output.trim().split("\n").slice(-8)) problems.push(`  ${name}> ${line}`);
		}

		const second = watch(godot, [...base, `--server=${port}`, "--net-report-after=700", save], { cwd: root, timeoutMs: 240_000 });
		const secondNotReady = await serverReady(second, "second server");
		if (secondNotReady !== undefined) return { ok: false, detail: secondNotReady };
		// A client claiming another build alongside: the server must turn it away with a reason.
		const stale = run(godot, [...base, address, "--claim-version=0.0.0-old", "--name=Stale"], { cwd: root, timeoutMs: 120_000 });
		const back = await run(godot, [...base, address, "--net-report-after=400", "--name=Saver"], { cwd: root, timeoutMs: 240_000 });
		const staleClient = await stale;
		const secondServer = await second.done;
		check("stale client", staleClient);
		if (!staleClient.output.includes("Update to join")) problems.push(`stale client: not told to update; it ended with:\n${lastLines(staleClient.output)}`);
		if (secondServer.output.includes("Stale is back") || secondServer.output.includes("is Stale")) problems.push("second server: let a client on another build join");
		check("second server", secondServer);
		check("returning client", back);
		if (!secondServer.output.includes("Saver is back")) problems.push("second server: did not recognise Saver from the save");
		const rep = parseReport(back.output);
		if (rep === undefined) problems.push(`returning client: no NET-REPORT line; it ended with:\n${lastLines(back.output)}\n  and the second server with:\n${lastLines(secondServer.output, 12)}`);
		else if (Math.abs(rep.moved - walked) > 1.5) problems.push(`returning client: not put back where it left (moved=${rep.moved}, left at ${walked})`);
	} finally {
		rmSync(saves, { recursive: true, force: true });
	}
	return problems.length > 0
		? { ok: false, detail: problems.slice(0, 20).join("\n") }
		: { ok: true, detail: "a named player's spot survives a server restart; a client on another build is turned away" };
}
