import { spawn, spawnSync } from "node:child_process";
import { platform } from "node:process";

export interface ProcResult {
	code: number;
	output: string;
	timedOut: boolean;
}

export interface RunOptions {
	cwd: string;
	timeoutMs: number;
	env?: NodeJS.ProcessEnv;
	// What becomes of processes the command started (a solo game's server) once the command
	// itself exits: "wait" lets them finish, since they share its output and a check may read
	// them; "kill" ends them at once, for a check that only wanted the command.
	children?: "wait" | "kill";
	// Sees the output as it comes, for a caller that waits for a line before going on.
	onOutput?: (text: string) => void;
}

const isWindows = platform === "win32";
// Every process group still running, so a gate stopped with Ctrl-C leaves no Godot behind:
// each command runs in its own group, which the terminal's Ctrl-C does not reach.
const live = new Set<number>();
let cleanupHooked = false;

// Ends a command and everything it started. POSIX gives each command its own process group;
// on Windows taskkill follows the parent links, so it only finds children while the parent is
// still alive.
export function killTree(pid: number): void {
	if (isWindows) {
		spawnSync("taskkill", ["/pid", String(pid), "/T", "/F"], { stdio: "ignore" });
		return;
	}
	try {
		process.kill(-pid, "SIGKILL");
	} catch {
		// The group is already gone.
	}
}

function hookCleanup(): void {
	if (cleanupHooked) return;
	cleanupHooked = true;
	process.on("exit", () => {
		for (const pid of live) killTree(pid);
	});
	for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) {
		process.on(signal, () => {
			for (const pid of live) killTree(pid);
			process.exit(130);
		});
	}
}

export function run(cmd: string, args: readonly string[], opts: RunOptions): Promise<ProcResult> {
	return new Promise((resolve, reject) => {
		hookCleanup();
		const child = spawn(cmd, args, { cwd: opts.cwd, env: opts.env ?? process.env, stdio: ["ignore", "pipe", "pipe"], detached: !isWindows, windowsHide: true });
		const pid = child.pid;
		if (pid !== undefined && !isWindows) live.add(pid);
		let output = "";
		let timedOut = false;
		let settled = false;
		let exitCode: number | null = null;
		const take = (d: Buffer): void => {
			const text = d.toString();
			output += text;
			opts.onOutput?.(text);
		};
		child.stdout.on("data", take);
		child.stderr.on("data", take);
		const finish = (code: number | null): void => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			clearTimeout(drain);
			if (pid !== undefined) live.delete(pid);
			resolve({ code: code ?? -1, output, timedOut });
		};
		// A process outside the group (or a Windows orphan) can keep the pipes open after a kill;
		// past this grace the output so far is the result.
		let drain: NodeJS.Timeout | undefined;
		const giveUpOnPipes = (): void => {
			clearTimeout(drain);
			drain = setTimeout(() => {
				child.stdout.destroy();
				child.stderr.destroy();
				finish(exitCode);
			}, 3000);
		};
		// macOS Godot can hang on a modal error dialog even headless, so every run has a deadline.
		const timer = setTimeout(() => {
			timedOut = true;
			if (pid !== undefined) killTree(pid);
			giveUpOnPipes();
		}, opts.timeoutMs);
		child.on("error", (err) => {
			clearTimeout(timer);
			clearTimeout(drain);
			if (pid !== undefined) live.delete(pid);
			reject(err);
		});
		child.on("exit", (code) => {
			exitCode = code;
			if (opts.children === "kill") {
				if (pid !== undefined && !isWindows) killTree(pid);
				giveUpOnPipes();
			}
		});
		child.on("close", (code) => finish(code ?? exitCode));
	});
}
