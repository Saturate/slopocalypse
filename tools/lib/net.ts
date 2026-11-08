import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join as pathJoin } from "node:path";
import { GODOT_NOISE, type StepResult } from "./gate.ts";
import { scanLog } from "./log-scan.ts";
import { run, type ProcResult } from "./proc.ts";

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
}

export function parseReport(output: string): NetReport | undefined {
	const m = /NET-REPORT mode=(\w+) peer=(\d+) peers=(\d+) players=(\d+) local_players=(\d+) moved=([\d.]+) shots=(\d+) driven=([\d.]+) ammo=(-?\d+)/.exec(output);
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
	if (rep === undefined) problems.push("solo: no NET-REPORT line");
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
export async function netSmoke(godot: string, root: string, port = 7791): Promise<StepResult> {
	const base = ["--headless", "--path", root, "--"];
	// Clients report at ~900 frames and stay connected; the server reports at 1300 while it
	// still has both, then quits, which closes the clients.
	const saves = mkdtempSync(pathJoin(tmpdir(), "outpost-net-"));
	const server = run(godot, [...base, `--server=${port}`, "--net-report-after=1300", `--save=${pathJoin(saves, "world.db")}`], { cwd: root, timeoutMs: 150_000 });
	// Let the server open its port and load the world before clients knock.
	await delay(4000);
	const join = `--connect=127.0.0.1:${port}`;
	const clients = [
		run(godot, [...base, join, "--net-report-after=900", "--bot=walk"], { cwd: root, timeoutMs: 150_000 }),
		run(godot, [...base, join, "--net-report-after=900", "--bot=drive"], { cwd: root, timeoutMs: 150_000 }),
	];
	const results: [string, ProcResult][] = [["server", await server], ["client 1 (bot)", await clients[0]!], ["client 2", await clients[1]!]];
	rmSync(saves, { recursive: true, force: true });

	const problems: string[] = [];
	for (const [name, r] of results) {
		for (const line of scanLog(r.output, GODOT_NOISE)) problems.push(`${name}: ${line}`);
		if (r.timedOut) problems.push(`${name}: timed out`);
	}
	for (const [name, r] of results) {
		const rep = parseReport(r.output);
		if (rep === undefined) {
			problems.push(`${name}: no NET-REPORT line`);
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

// Progress survives a server restart: a named bot walks off and the server stops (saving on
// the way out); a second server on the same file must put the same name back where it was,
// without that client moving at all.
export async function saveSmoke(godot: string, root: string, port = 7793): Promise<StepResult> {
	const base = ["--headless", "--path", root, "--"];
	const saves = mkdtempSync(pathJoin(tmpdir(), "outpost-save-"));
	const save = `--save=${pathJoin(saves, "world.db")}`;
	const address = `--connect=127.0.0.1:${port}`;
	const problems: string[] = [];
	const check = (name: string, r: ProcResult): void => {
		for (const line of scanLog(r.output, GODOT_NOISE)) problems.push(`${name}: ${line}`);
		if (r.timedOut) problems.push(`${name}: timed out`);
	};
	try {
		const first = run(godot, [...base, `--server=${port}`, "--net-report-after=1100", save], { cwd: root, timeoutMs: 150_000 });
		await delay(4000);
		const walker = await run(godot, [...base, address, "--net-report-after=900", "--bot=walk", "--name=Saver"], { cwd: root, timeoutMs: 150_000 });
		const firstServer = await first;
		check("first server", firstServer);
		check("walking client", walker);
		// The server reports in the same frame it stops and saves; the bot keeps walking
		// until then, so its own report is from earlier.
		const walked = parseReport(firstServer.output)?.moved ?? 0;
		if (walked < 3.0) problems.push(`first server: Saver did not get 3 m from the spawn (moved=${walked})`);

		const second = run(godot, [...base, `--server=${port}`, "--net-report-after=700", save], { cwd: root, timeoutMs: 150_000 });
		await delay(4000);
		const back = await run(godot, [...base, address, "--net-report-after=400", "--name=Saver"], { cwd: root, timeoutMs: 150_000 });
		const secondServer = await second;
		check("second server", secondServer);
		check("returning client", back);
		if (!secondServer.output.includes("Saver is back")) problems.push("second server: did not recognise Saver from the save");
		const rep = parseReport(back.output);
		if (rep === undefined) problems.push("returning client: no NET-REPORT line");
		else if (Math.abs(rep.moved - walked) > 1.5) problems.push(`returning client: not put back where it left (moved=${rep.moved}, left at ${walked})`);
	} finally {
		rmSync(saves, { recursive: true, force: true });
	}
	return problems.length > 0
		? { ok: false, detail: problems.slice(0, 20).join("\n") }
		: { ok: true, detail: "a named player's spot survives a server restart" };
}
