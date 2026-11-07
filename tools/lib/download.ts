import { execFileSync } from "node:child_process";
import { readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { platform } from "node:process";

export async function download(url: string, dest: string): Promise<void> {
	const res = await fetch(url);
	if (!res.ok) {
		throw new Error(`download failed: ${url} returned ${res.status}`);
	}
	writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
}

// Extracts a zip (any extension; Godot's .tpz is a zip).
export function extract(zip: string, dest: string): void {
	// bsdtar reads zip on Windows and macOS; stock Linux tar does not, so use unzip there.
	// On Windows call System32 tar by path: Git Bash puts GNU tar first on PATH, which treats "C:" as a remote host.
	if (platform === "linux") {
		execFileSync("unzip", ["-o", "-q", zip, "-d", dest], { stdio: "inherit" });
	} else if (platform === "win32") {
		const bsdtar = join(process.env["SystemRoot"] ?? "C:\\Windows", "System32", "tar.exe");
		execFileSync(bsdtar, ["-xf", zip, "-C", dest], { stdio: "inherit" });
	} else {
		execFileSync("tar", ["-xf", zip, "-C", dest], { stdio: "inherit" });
	}
}

// Zips a folder's contents. bsdtar writes zip with -a on Windows and macOS.
// Entries are listed by name (no shell globbing), so the zip has no "./" prefixes.
export function zipFolder(folder: string, zip: string): void {
	const entries = readdirSync(folder);
	if (platform === "linux") {
		execFileSync("zip", ["-r", "-q", zip, ...entries], { cwd: folder, stdio: "inherit" });
	} else {
		const tar = platform === "win32" ? join(process.env["SystemRoot"] ?? "C:\\Windows", "System32", "tar.exe") : "tar";
		execFileSync(tar, ["-a", "-cf", zip, ...entries], { cwd: folder, stdio: "inherit" });
	}
}
