import { GODOT_NOISE, type StepResult } from "./gate.ts";
import { scanLog } from "./log-scan.ts";
import { run, type ProcResult } from "./proc.ts";

export interface NetReport {
	mode: string;
	peer: number;
	peers: number;
	players: number;
	localPlayers: number;
}

export function parseReport(output: string): NetReport | undefined {
	const m = /NET-REPORT mode=(\w+) peer=(\d+) peers=(\d+) players=(\d+) local_players=(\d+)/.exec(output);
	if (m === null) return undefined;
	return { mode: m[1] ?? "", peer: Number(m[2]), peers: Number(m[3]), players: Number(m[4]), localPlayers: Number(m[5]) };
}

const delay = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

// A dedicated server plus two clients as real processes on localhost. The server reports
// (and quits) while both clients are connected; clients then see it leave and close.
export async function netSmoke(godot: string, root: string, port = 7791): Promise<StepResult> {
	const base = ["--headless", "--path", root, "--"];
	// Clients report at ~700 frames and stay connected; the server reports at 1100 while it
	// still has both, then quits, which closes the clients.
	const server = run(godot, [...base, `--server=${port}`, "--net-report-after=1100"], { cwd: root, timeoutMs: 120_000 });
	// Let the server open its port and load the world before clients knock.
	await delay(4000);
	const clientArgs = [...base, `--connect=127.0.0.1:${port}`, "--net-report-after=700"];
	const clients = [run(godot, clientArgs, { cwd: root, timeoutMs: 120_000 }), run(godot, clientArgs, { cwd: root, timeoutMs: 120_000 })];
	const results: [string, ProcResult][] = [["server", await server], ["client 1", await clients[0]!], ["client 2", await clients[1]!]];

	const problems: string[] = [];
	for (const [name, r] of results) {
		for (const line of scanLog(r.output, GODOT_NOISE)) problems.push(`${name}: ${line}`);
		if (r.timedOut) problems.push(`${name}: timed out`);
	}
	const reports = results.map(([name, r]) => [name, parseReport(r.output)] as const);
	for (const [name, rep] of reports) {
		if (rep === undefined) {
			problems.push(`${name}: no NET-REPORT line`);
			continue;
		}
		if (name === "server") {
			if (rep.mode !== "SERVER" || rep.peers !== 2 || rep.players !== 2 || rep.localPlayers !== 0) {
				problems.push(`server: expected 2 peers, 2 players, 0 local; got ${JSON.stringify(rep)}`);
			}
		} else if (rep.mode !== "CLIENT" || rep.players !== 2 || rep.localPlayers !== 1) {
			problems.push(`${name}: expected 2 players, 1 local; got ${JSON.stringify(rep)}`);
		}
	}
	return problems.length > 0
		? { ok: false, detail: problems.slice(0, 20).join("\n") }
		: { ok: true, detail: "server + 2 clients: everyone sees 2 players" };
}
