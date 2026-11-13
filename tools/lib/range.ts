// The test range's session arguments (modules/range): its flag, nothing saved, the flat test
// world, and the modules its data switches off so nothing hostile turns up.
import { readFileSync } from "node:fs";
import { join } from "node:path";

export function rangeFlags(text: string): string | undefined {
	const data: unknown = JSON.parse(text);
	if (typeof data !== "object" || data === null || !("flags" in data)) return undefined;
	return typeof data.flags === "string" ? data.flags : undefined;
}

export function rangeArgs(root: string): string[] {
	const flags = rangeFlags(readFileSync(join(root, "modules", "range", "data", "range.json"), "utf8"));
	return ["--range", "--no-save", "--world=flat", ...(flags === undefined ? [] : [`--flags=${flags}`])];
}
