// Godot can exit 0 after a script error, and gdUnit4 passes tests that only push_error,
// so the gate reads the log itself instead of trusting exit codes.

// Matches the start of Godot's error lines. Mixed case is deliberate: Godot prints
// "Error: Can't run project" for some fatal startup failures.
const ERROR_LINE = /^\s*(SCRIPT ERROR|ERROR|Error):/;

const ANSI = /\u001b\[[0-9;?]*[A-Za-z]/g;

export function stripAnsi(text: string): string {
	return text.replace(ANSI, "");
}

export function scanLog(log: string, allow: readonly RegExp[]): string[] {
	return stripAnsi(log)
		.split(/\r?\n/)
		.filter((line) => ERROR_LINE.test(line))
		.filter((line) => !allow.some((pattern) => pattern.test(line)));
}

export interface TestSummary {
	cases: number;
	errors: number;
	failures: number;
}

export function testSummary(log: string): TestSummary | undefined {
	const match = /Overall Summary:\s*(\d+) test cases \| (\d+) errors \| (\d+) failures/.exec(stripAnsi(log));
	if (match === null) {
		return undefined;
	}
	return { cases: Number(match[1]), errors: Number(match[2]), failures: Number(match[3]) };
}
