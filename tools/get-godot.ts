// Downloads the pinned Godot build for this machine into tools/godot/ and verifies it.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { arch, exit, platform } from "node:process";
import { expectedSha512, verifySha512 } from "./lib/checksum.ts";
import { download, extract } from "./lib/download.ts";
import { assetFor, GODOT_DIR, GODOT_VERSION, localGodot, RELEASE_URL } from "./lib/godot.ts";

const root = resolve(import.meta.dirname, "..");
const target = join(root, GODOT_DIR);
const force = process.argv.includes("--force");

async function main(): Promise<void> {
	const exe = localGodot(root);
	if (existsSync(exe) && !force) {
		console.log(`Godot ${GODOT_VERSION} already present: ${exe}`);
		return;
	}

	const asset = assetFor(platform, arch);
	const work = mkdtempSync(join(tmpdir(), "outpost-godot-"));
	try {
		const zip = join(work, asset);
		const sumsFile = join(work, "SHA512-SUMS.txt");
		console.log(`Downloading ${asset}`);
		await Promise.all([
			download(`${RELEASE_URL}/${asset}`, zip),
			download(`${RELEASE_URL}/SHA512-SUMS.txt`, sumsFile),
		]);
		const sums = readFileSync(sumsFile, "utf8");
		await verifySha512(zip, expectedSha512(sums, asset));
		console.log("Checksum OK");

		rmSync(target, { recursive: true, force: true });
		mkdirSync(target, { recursive: true });
		extract(zip, target);
		// Self-contained mode keeps editor settings and caches inside tools/godot/.
		writeFileSync(join(target, "._sc_"), "");
		// The engine folder sits inside the project; keep Godot's importer out of it.
		writeFileSync(join(target, ".gdignore"), "");
		if (platform !== "win32") {
			execFileSync("chmod", ["+x", exe]);
		}
		if (!existsSync(exe)) {
			throw new Error(`expected executable not found after extract: ${exe}`);
		}
		console.log(`Installed ${exe}`);
	} finally {
		rmSync(work, { recursive: true, force: true });
	}
}

main().catch((err: unknown) => {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
});
