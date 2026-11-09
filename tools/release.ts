// Cuts a release from the maintainer's machine (no Actions minutes):
//   node tools/release.ts [--dry-run]
// Bumps the version and changelog with changesetter, builds the Windows zip, the Linux zip
// and the server image, and only then commits, tags, pushes, creates the GitHub Release with
// the zips and pushes the image to ghcr.io. --dry-run builds everything, then puts the tree
// back and publishes nothing.
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { argv, exit, platform } from "node:process";
import { changesetterBin } from "./lib/changesetter.ts";
import { assetName, hasScope, IMAGE, imageTags, parseReleasePlan, releaseNotes, type ReleasePlan } from "./lib/release.ts";

const root = resolve(import.meta.dirname, "..");
const dryRun = argv.includes("--dry-run");
const outDir = join(root, "build", "release");

function capture(cmd: string, args: readonly string[]): string {
	return execFileSync(cmd, args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function succeeds(cmd: string, args: readonly string[]): boolean {
	try {
		execFileSync(cmd, args, { cwd: root, stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
}

function step(cmd: string, args: readonly string[], input?: string): void {
	console.log(`\n> ${cmd} ${args.join(" ")}`);
	execFileSync(cmd, args, { cwd: root, stdio: [input === undefined ? "inherit" : "pipe", "inherit", "inherit"], input });
}

function preflight(): void {
	const problems: string[] = [];
	// A dry run puts the tree back afterwards, which is only safe from a clean tree.
	if (capture("git", ["status", "--porcelain"]) !== "") problems.push("the working tree is not clean");
	step("git", ["fetch", "origin", "main"]);
	const onMain = capture("git", ["branch", "--show-current"]) === "main";
	const inSync = capture("git", ["rev-parse", "HEAD"]) === capture("git", ["rev-parse", "origin/main"]);
	if (!onMain || !inSync) {
		const why = onMain ? "main is not in sync with origin/main (pull or push first)" : "not on main";
		if (dryRun) console.log(`warning: ${why}; fine for a dry run`);
		else problems.push(why);
	}
	if (!existsSync(changesetterBin(root, platform))) problems.push("changesetter missing: node tools/get-changesetter.ts");
	if (!succeeds("docker", ["info"])) problems.push("Docker is not running");
	if (platform !== "win32") problems.push("the Windows zip is built on Windows; run this there");
	if (!dryRun) {
		let auth = "";
		try {
			auth = execFileSync("gh", ["auth", "status"], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
		} catch (err) {
			problems.push(`gh is not logged in: ${err instanceof Error ? err.message : String(err)}`);
		}
		if (auth !== "" && !hasScope(auth, "write:packages")) problems.push("gh cannot push images: gh auth refresh -h github.com -s write:packages");
	}
	if (problems.length > 0) throw new Error(`not ready to release:\n  ${problems.join("\n  ")}`);
}

function plan(): ReleasePlan | undefined {
	// The changeset files say which kind of change each is, for grouping the notes; read them
	// before the release consumes them.
	return parseReleasePlan(capture(changesetterBin(root, platform), ["release", "--dry-run", "--output", "json"]), (id) => {
		const file = join(root, ".changeset", `${id}.md`);
		return existsSync(file) ? readFileSync(file, "utf8") : undefined;
	});
}

// The tree was clean before the release started, so everything changed since is ours.
function restoreTree(): void {
	console.log("\nPutting the working tree back");
	execFileSync("git", ["restore", "--source=HEAD", "--staged", "--worktree", "--", "."], { cwd: root, stdio: "inherit" });
	execFileSync("git", ["clean", "-fd", "--", "."], { cwd: root, stdio: "inherit" });
}

function build(p: ReleasePlan): string[] {
	rmSync(outDir, { recursive: true, force: true });
	mkdirSync(outDir, { recursive: true });
	step("node", ["tools/export.ts", "--os", "windows"]);
	const windows = join(outDir, assetName(p.version, "windows"));
	copyFileSync(join(root, "build", "slopocalypse-windows.zip"), windows);
	// Linux libraries can't be built on Windows; the Dockerfile's build stage makes the zip.
	const linuxDir = join(outDir, "linux");
	step("docker", ["build", "--target", "linux-zip", "--output", `type=local,dest=${linuxDir}`, "."]);
	const linux = join(outDir, assetName(p.version, "linux"));
	renameSync(join(linuxDir, "slopocalypse-linux.zip"), linux);
	rmSync(linuxDir, { recursive: true, force: true });
	step("docker", ["build", "--build-arg", `VERSION=${p.version}`, ...imageTags(p.version).flatMap((t) => ["-t", t]), "."]);
	return [windows, linux];
}

function publish(p: ReleasePlan, assets: readonly string[]): void {
	step("git", ["add", "-A"]);
	step("git", ["commit", "-m", `chore(release): ${p.tag}`]);
	step("git", ["tag", "-a", p.tag, "-m", `Slopocalypse ${p.version}`]);
	step("git", ["push", "--atomic", "origin", "main", p.tag]);
	const notes = join(outDir, "notes.md");
	writeFileSync(notes, releaseNotes(p));
	step("gh", ["release", "create", p.tag, ...assets, "--title", `Slopocalypse ${p.version}`, "--notes-file", notes]);
	const user = capture("gh", ["api", "user", "--jq", ".login"]);
	step("docker", ["login", "ghcr.io", "-u", user, "--password-stdin"], capture("gh", ["auth", "token"]) + "\n");
	for (const tag of imageTags(p.version)) step("docker", ["push", tag]);
}

async function main(): Promise<void> {
	preflight();
	const p = plan();
	if (p === undefined) {
		console.log("Nothing to release: no pending changeset bumps the game's version.");
		return;
	}
	if (succeeds("git", ["rev-parse", "--verify", "--quiet", `refs/tags/${p.tag}`])) throw new Error(`tag ${p.tag} already exists`);
	console.log(`\nReleasing ${p.tag}${dryRun ? " (dry run: nothing is published)" : ""}\n\n${releaseNotes(p)}`);

	let assets: string[];
	try {
		step(changesetterBin(root, platform), ["release", "--no-commit"]);
		if (!readFileSync(join(root, "project.godot"), "utf8").includes(`config/version="${p.version}"`)) {
			throw new Error(`changesetter did not set config/version to ${p.version}`);
		}
		assets = build(p);
	} catch (err) {
		restoreTree();
		throw err;
	}
	if (dryRun) {
		restoreTree();
		console.log(`\nDry run done. Built:\n  ${assets.join("\n  ")}\n  ${imageTags(p.version).join("\n  ")}\nRun without --dry-run to publish.`);
		return;
	}
	publish(p, assets);
	console.log(`\nReleased ${p.tag}: ${capture("gh", ["release", "view", p.tag, "--json", "url", "--jq", ".url"])}\nImage: ${IMAGE}:${p.version}`);
}

try {
	await main();
} catch (err) {
	console.error(err instanceof Error ? err.message : err);
	exit(1);
}
