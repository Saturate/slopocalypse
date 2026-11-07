// Puts the dedicated server on a Linux machine you own and keeps it running with systemd.
//   node tools/deploy.ts --host user@server [--port 7777] [--dir /opt/outpost] [--user outpost]
//                        [--open-firewall] (--zip build/linux-folder-or-zip | --ci) [--dry-run]
// The Linux build needs the Rust extensions compiled for Linux, which this Windows machine
// cannot do. Give a Linux build with --zip (built on a Linux box with
// `node tools/export.ts --os linux`), or --ci to run the manual `server-build` GitHub
// workflow and download its artifact; that spends Actions minutes, so it is opt-in.
// Needs ssh and scp (key login is easiest), and root or passwordless sudo on the server:
// the install runs non-interactively, so sudo cannot ask for a password.
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { argv, exit } from "node:process";
import { extract } from "./lib/download.ts";
import { checkScript, installScript, LINUX_EXE, serverIsUp, type DeployTarget } from "./lib/deploy.ts";

const root = resolve(import.meta.dirname, "..");
const WORKFLOW = "server-build.yml";
const ARTIFACT = "outpost-linux";

function arg(name: string): string | undefined {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 ? argv[i + 1] : undefined;
}

function sh(cmd: string, args: string[], input?: string): string {
	const r = spawnSync(cmd, args, { cwd: root, input, encoding: "utf8", stdio: ["pipe", "pipe", "inherit"], maxBuffer: 1 << 26 });
	if (r.error !== undefined) throw r.error;
	if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")} failed (exit ${r.status})\n${r.stdout}`);
	return r.stdout;
}

function stampNow(): string {
	return new Date().toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 13);
}

// Runs the workflow on main and downloads its build into a temp folder.
function buildOnCi(): string {
	const before = sh("gh", ["run", "list", "--workflow", WORKFLOW, "--limit", "1", "--json", "databaseId", "-q", ".[0].databaseId"]).trim();
	console.log("Starting the Linux server build on GitHub Actions (main branch)...");
	sh("gh", ["workflow", "run", WORKFLOW, "--ref", "main"]);
	let id = before;
	for (let tries = 0; tries < 30 && id === before; tries++) {
		spawnSync(process.execPath, ["-e", "setTimeout(() => {}, 2000)"]);
		id = sh("gh", ["run", "list", "--workflow", WORKFLOW, "--limit", "1", "--json", "databaseId", "-q", ".[0].databaseId"]).trim();
	}
	if (id === before || id === "") throw new Error("the workflow run did not appear; check `gh run list`");
	console.log(`Waiting for run ${id} (about 10 minutes the first time, less once caches are warm)...`);
	const watch = spawnSync("gh", ["run", "watch", id, "--exit-status", "--interval", "20"], { cwd: root, stdio: "inherit" });
	if (watch.status !== 0) throw new Error(`the build failed: gh run view ${id} --log-failed`);
	const dir = mkdtempSync(join(tmpdir(), "outpost-linux-"));
	sh("gh", ["run", "download", id, "-n", ARTIFACT, "-D", dir]);
	return dir;
}

async function localBuild(path: string): Promise<string> {
	if (statSync(path).isDirectory()) return path;
	const dir = mkdtempSync(join(tmpdir(), "outpost-linux-"));
	await extract(path, dir);
	return dir;
}

async function main(): Promise<void> {
	const host = arg("host");
	if (host === undefined) throw new Error("missing --host user@server");
	const target: DeployTarget = {
		dir: arg("dir") ?? "/opt/outpost",
		port: Number(arg("port") ?? "7777"),
		user: arg("user") ?? "outpost",
		keep: 3,
		openFirewall: argv.includes("--open-firewall"),
	};
	if (!Number.isInteger(target.port) || target.port < 1 || target.port > 65535) throw new Error("bad --port");
	const stamp = stampNow();
	const remoteTar = `/tmp/outpost-${stamp}.tar.gz`;

	if (argv.includes("--dry-run")) {
		console.log(`# would copy the build to ${host}:${remoteTar}, then run:\n`);
		console.log(installScript(target, stamp, remoteTar));
		console.log("# then check:\n");
		console.log(checkScript(target));
		return;
	}

	const zip = arg("zip");
	// GitHub Actions minutes are limited, so CI runs only when asked for by name.
	if (zip === undefined && !argv.includes("--ci")) {
		throw new Error("give --zip <linux build folder or zip>, or --ci to build it on the server-build GitHub workflow (uses Actions minutes)");
	}
	const build = zip !== undefined ? await localBuild(resolve(zip)) : buildOnCi();
	if (!existsSync(join(build, LINUX_EXE))) throw new Error(`${build} has no ${LINUX_EXE}; files: ${readdirSync(build).join(", ")}`);

	const tarball = join(mkdtempSync(join(tmpdir(), "outpost-tar-")), "outpost.tar.gz");
	sh("tar", ["-czf", tarball, "-C", build, "."]);
	console.log(`Copying to ${host}...`);
	// scp reads "C:\..." as host "C"; a relative path from the tarball's folder avoids that.
	const r = spawnSync("scp", ["-q", "outpost.tar.gz", `${host}:${remoteTar}`], { cwd: join(tarball, ".."), stdio: "inherit" });
	if (r.status !== 0) throw new Error("scp failed");
	rmSync(join(tarball, ".."), { recursive: true, force: true });

	console.log("Installing and restarting the service...");
	sh("ssh", [host, "bash", "-s"], installScript(target, stamp, remoteTar));
	const out = sh("ssh", [host, "bash", "-s"], checkScript(target));
	const [active = "", ...journal] = out.split("\n");
	if (!serverIsUp(active, journal.join("\n"), target.port)) {
		throw new Error(`the service is not up (${active.trim()}). Recent log:\n${journal.join("\n")}`);
	}
	const name = host.includes("@") ? host.slice(host.indexOf("@") + 1) : host;
	console.log(`\nServer is up: ${name}:${target.port} (UDP).`);
	console.log("If friends cannot connect, open UDP port " + target.port + " in the server's firewall and any cloud provider firewall.");
	console.log(`Friend zip that lists it: node tools/export.ts --connect ${name}${target.port === 7777 ? "" : `:${target.port}`}`);
}

main().catch((err: unknown) => {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
});
