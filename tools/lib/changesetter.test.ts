import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { changesetterAsset, changesetterBin, changesetterUrl } from "./changesetter.ts";

test("every supported OS gets its own pinned archive", () => {
	assert.equal(changesetterAsset("win32", "x64").file, "changesetter-x86_64-pc-windows-msvc.zip");
	assert.equal(changesetterAsset("linux", "arm64").file, "changesetter-aarch64-unknown-linux-gnu.tar.gz");
	assert.equal(changesetterAsset("darwin", "arm64").file, "changesetter-aarch64-apple-darwin.tar.gz");
	assert.match(changesetterAsset("darwin", "x64").sha256, /^[0-9a-f]{64}$/);
});

test("an unsupported platform is an error, not a wrong binary", () => {
	assert.throws(() => changesetterAsset("win32", "arm64"), /no changesetter/);
});

test("downloads come from the tagged GitHub release", () => {
	assert.equal(
		changesetterUrl(changesetterAsset("linux", "x64")),
		"https://github.com/Saturate/changesetter/releases/download/changesetter%40v0.5.2/changesetter-x86_64-unknown-linux-gnu.tar.gz",
	);
});

test("the binary lives in tools/changesetter", () => {
	assert.equal(changesetterBin("/repo", "win32"), join("/repo", "tools", "changesetter", "changesetter.exe"));
	assert.equal(changesetterBin("/repo", "linux"), join("/repo", "tools", "changesetter", "changesetter"));
});
