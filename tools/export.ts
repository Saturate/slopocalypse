// Builds a portable game folder and zip a player can unpack and double-click.
//   node tools/export.ts [--os windows|linux] [--connect HOST[:PORT][,HOST...]] [--port 7777]
// --connect ships those addresses in servers.json, so the menu already lists them and a
// friend just clicks. Output: build/<os>/ and build/outpost-<os>.zip.
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { argv, exit, platform } from "node:process";
import { expectedSha512, verifySha512 } from "./lib/checksum.ts";
import { download, extract, zipFolder } from "./lib/download.ts";
import { exeName, hostScript, shippedServers, presetFor, presetsFile, templatesDir, type TargetOs } from "./lib/export.ts";
import { GODOT_NOISE, godotImport } from "./lib/gate.ts";
import { GODOT_DIR, GODOT_VERSION, localGodot, RELEASE_URL } from "./lib/godot.ts";
import { scanLog } from "./lib/log-scan.ts";
import { parseReport } from "./lib/net.ts";
import { run } from "./lib/proc.ts";
import { buildRust } from "./lib/rust.ts";

const root = resolve(import.meta.dirname, "..");

function arg(name: string): string | undefined {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 ? argv[i + 1] : undefined;
}

function hostOs(): TargetOs {
	return platform === "win32" ? "windows" : platform === "darwin" ? "macos" : "linux";
}

function parseOs(value: string | undefined): TargetOs {
	if (value === undefined) return hostOs();
	if (value === "windows" || value === "linux" || value === "macos") return value;
	throw new Error(`unknown --os ${value} (windows, linux or macos)`);
}

async function ensureTemplates(): Promise<void> {
	const dir = templatesDir(join(root, GODOT_DIR), GODOT_VERSION);
	if (existsSync(join(dir, "version.txt"))) return;
	const asset = `Godot_v${GODOT_VERSION}_export_templates.tpz`;
	const work = mkdtempSync(join(tmpdir(), "outpost-templates-"));
	try {
		console.log(`Downloading ${asset} (about 1 GB, once)`);
		const tpz = join(work, asset);
		const sums = join(work, "SHA512-SUMS.txt");
		await Promise.all([download(`${RELEASE_URL}/${asset}`, tpz), download(`${RELEASE_URL}/SHA512-SUMS.txt`, sums)]);
		await verifySha512(tpz, expectedSha512(readFileSync(sums, "utf8"), asset));
		console.log("Checksum OK");
		extract(tpz, work);
		mkdirSync(dir, { recursive: true });
		// The archive holds a templates/ folder; Godot wants its contents in the version folder.
		cpSync(join(work, "templates"), dir, { recursive: true });
		console.log(`Installed export templates in ${dir}`);
	} finally {
		rmSync(work, { recursive: true, force: true });
	}
}

const README = (host: string | undefined, port: number, os: TargetOs): string => {
	const ext = os === "windows" ? "bat" : "sh";
	const lines = [
		"OUTPOST",
		"",
		"Start: double-click Outpost" + (os === "windows" ? ".exe" : "") + ". The menu has Play solo, Host a game and Join a friend.",
		host !== undefined ? `Join a friend: ${host} is already listed under Recent; click it.` : "Join a friend: paste their address under Join a friend and click Join.",
		`Host a game: click Host a game and send friends the address the menu shows. They need to reach UDP port ${port} on your machine (Tailscale, or a forwarded port).`,
		`A server that stays up without playing: double-click "Host server.${ext}" and leave the window open.`,
		"",
		"Controls: WASD move, mouse aim, left click fire, R reload, G charge, E interact / enter and leave the car, Space jump, Shift sprint, Ctrl or C crouch. In the car: WASD drive, Space brake.",
		"",
		os === "windows" ? 'Windows may say "Windows protected your PC" because the game is not signed: click "More info", then "Run anyway".' : "",
	];
	return lines.join(os === "windows" ? "\r\n" : "\n");
};

async function main(): Promise<void> {
	const os = parseOs(arg("os"));
	if (os === "macos") throw new Error("macOS exports need signing and notarisation; not set up yet");
	const connect = arg("connect");
	const port = Number(arg("port") ?? "7777");
	const godot = localGodot(root);
	if (!existsSync(godot)) throw new Error("Godot missing: run node tools/get-godot.ts");

	await ensureTemplates();

	const rust = await buildRust(root, true);
	console.log(rust.detail);
	if (!rust.ok) throw new Error("rust release build failed");

	const outDir = join(root, "build", os);
	const exe = join(outDir, exeName(os));
	writeFileSync(join(root, "export_presets.cfg"), presetsFile([presetFor(os, exe.replaceAll("\\", "/"))]));

	const imported = await godotImport(godot, root);
	if (!imported.ok) throw new Error(`import failed:\n${imported.detail}`);

	rmSync(outDir, { recursive: true, force: true });
	mkdirSync(outDir, { recursive: true });
	console.log(`Exporting ${os} to ${outDir}`);
	const r = await run(godot, ["--headless", "--path", root, "--export-release", presetFor(os, exe).name, exe], { cwd: root, timeoutMs: 600_000 });
	const problems = scanLog(r.output, GODOT_NOISE);
	if (r.code !== 0 || problems.length > 0 || !existsSync(exe)) {
		throw new Error(`export failed (exit ${r.code}):\n${problems.join("\n") || r.output.slice(-3000)}`);
	}

	const ext = os === "windows" ? "bat" : "sh";
	if (connect !== undefined) writeFileSync(join(outDir, "servers.json"), shippedServers(connect));
	writeFileSync(join(outDir, `Host server.${ext}`), hostScript(os, port));
	writeFileSync(join(outDir, "README.txt"), README(connect, port, os));

	if (os === hostOs()) await smokeTest(outDir, os);

	const zip = join(root, "build", `outpost-${os}.zip`);
	rmSync(zip, { force: true });
	zipFolder(outDir, zip);
	console.log(`Files: ${readdirSync(outDir).join(", ")}`);
	console.log(`Ready: ${zip}`);
}

// The exported game, not the project: solo must start its own server from the exported
// executable and the bot must move and shoot through it.
async function smokeTest(outDir: string, os: TargetOs): Promise<void> {
	const exe = join(outDir, os === "windows" ? "Outpost.console.exe" : exeName(os));
	const r = await run(exe, ["--headless", "--", "--net-report-after=600", "--bot=walk"], { cwd: outDir, timeoutMs: 120_000 });
	const rep = parseReport(r.output);
	const problems = scanLog(r.output, GODOT_NOISE);
	if (r.timedOut) problems.push("timed out");
	if (rep === undefined) problems.push("no NET-REPORT line");
	else if (rep.mode !== "SOLO" || rep.players !== 1 || rep.moved < 3 || rep.shots < 1) problems.push(`unexpected session: ${JSON.stringify(rep)}`);
	if (problems.length > 0) throw new Error(`exported build failed its smoke test:\n${problems.join("\n")}\n${r.output.slice(-2000)}`);
	console.log("Exported build: solo through its own server works");
}

main().catch((err: unknown) => {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
});
