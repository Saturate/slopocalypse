import { spawn } from "node:child_process";

export interface ProcResult {
	code: number;
	output: string;
	timedOut: boolean;
}

// `onOutput` sees everything printed so far each time more arrives, for waiting on a line.
export function run(cmd: string, args: readonly string[], opts: { cwd: string; timeoutMs: number; onOutput?: (output: string) => void }): Promise<ProcResult> {
	return new Promise((resolve, reject) => {
		const child = spawn(cmd, args, { cwd: opts.cwd, stdio: ["ignore", "pipe", "pipe"] });
		let output = "";
		let timedOut = false;
		const append = (d: Buffer): void => {
			output += d.toString();
			opts.onOutput?.(output);
		};
		child.stdout.on("data", append);
		child.stderr.on("data", append);
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
