import { existsSync, readFileSync } from "node:fs";
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
}

export function parseReport(output: string): NetReport | undefined {
	const m = /NET-REPORT mode=(\w+) peer=(\d+) peers=(\d+) players=(\d+) local_players=(\d+) moved=([\d.]+) shots=(\d+)/.exec(output);
	if (m === null) return undefined;
	return {
		mode: m[1] ?? "",
		peer: Number(m[2]),
		peers: Number(m[3]),
		players: Number(m[4]),
		localPlayers: Number(m[5]),
		moved: Number(m[6]),
		shots: Number(m[7]),
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
	const r = await run(godot, ["--headless", "--path", root, "--", "--net-report-after=900", "--bot=walk"], { cwd: root, timeoutMs: 120_000 });
	const problems: string[] = [];
	for (const line of scanLog(r.output, GODOT_NOISE)) problems.push(`solo: ${line}`);
	if (r.timedOut) problems.push("solo: timed out");
	const rep = parseReport(r.output);
	if (rep === undefined) problems.push("solo: no NET-REPORT line");
	else {
		if (rep.mode !== "SOLO" || rep.peers !== 1 || rep.players !== 1 || rep.localPlayers !== 1) problems.push(`solo: wrong session shape: ${JSON.stringify(rep)}`);
		if (rep.moved < 3.0) problems.push(`solo: player did not move through the server (moved=${rep.moved})`);
		if (rep.shots < 1) problems.push("solo: saw no shots");
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
// that walks and fires through the network intent path; the checks prove input reaches the
// server and the results (movement, shots) reach the other client.
export async function netSmoke(godot: string, root: string, port = 7791): Promise<StepResult> {
	const base = ["--headless", "--path", root, "--"];
	// Clients report at ~900 frames and stay connected; the server reports at 1300 while it
	// still has both, then quits, which closes the clients.
	const server = run(godot, [...base, `--server=${port}`, "--net-report-after=1300"], { cwd: root, timeoutMs: 150_000 });
	// Let the server open its port and load the world before clients knock.
	await delay(4000);
	const join = `--connect=127.0.0.1:${port}`;
	const clients = [
		run(godot, [...base, join, "--net-report-after=900", "--bot=walk"], { cwd: root, timeoutMs: 150_000 }),
		run(godot, [...base, join, "--net-report-after=900"], { cwd: root, timeoutMs: 150_000 }),
	];
	const results: [string, ProcResult][] = [["server", await server], ["client 1 (bot)", await clients[0]!], ["client 2", await clients[1]!]];

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
	}
	return problems.length > 0
		? { ok: false, detail: problems.slice(0, 20).join("\n") }
		: { ok: true, detail: "server + 2 clients: bot input reaches the server, movement and shots reach everyone" };
}
