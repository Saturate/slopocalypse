import { spawn } from "node:child_process";

export interface ProcResult {
	code: number;
	output: string;
	timedOut: boolean;
}

export function run(cmd: string, args: readonly string[], opts: { cwd: string; timeoutMs: number }): Promise<ProcResult> {
	return new Promise((resolve, reject) => {
		const child = spawn(cmd, args, { cwd: opts.cwd, stdio: ["ignore", "pipe", "pipe"] });
		let output = "";
		let timedOut = false;
		child.stdout.on("data", (d: Buffer) => (output += d.toString()));
		child.stderr.on("data", (d: Buffer) => (output += d.toString()));
		// macOS Godot can hang on a modal error dialog even headless, so every run has a deadline.
		const timer = setTimeout(() => {
			timedOut = true;
			child.kill("SIGKILL");
		}, opts.timeoutMs);
		child.on("error", (err) => {
			clearTimeout(timer);
			reject(err);
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			resolve({ code: code ?? -1, output, timedOut });
		});
	});
}
