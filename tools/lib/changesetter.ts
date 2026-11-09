// changesetter: versions and changelog from `.changeset/*.md` files. A pinned release binary
// lives in tools/changesetter/ (git-ignored), fetched by tools/get-changesetter.ts.
import { join } from "node:path";

export const CHANGESETTER_VERSION = "0.5.2";

export interface ChangesetterAsset {
	file: string;
	sha256: string;
}

// Release assets do not ship checksum files; these were computed from the published archives.
const ASSETS: Readonly<Record<string, ChangesetterAsset>> = {
	"win32-x64": { file: "changesetter-x86_64-pc-windows-msvc.zip", sha256: "4c2741d27ebd26c0627c6936ad2dd59f034202f971f40593cce3728e3fdde229" },
	"linux-x64": { file: "changesetter-x86_64-unknown-linux-gnu.tar.gz", sha256: "bef485c3c32c3bffb208018137588da33c5672254d64939905fa455f29fc251a" },
	"linux-arm64": { file: "changesetter-aarch64-unknown-linux-gnu.tar.gz", sha256: "6264b08a43bb7109d1f6ce94f2f60cb0e6c217723f373fd6f80fa887c6632ef0" },
	"darwin-arm64": { file: "changesetter-aarch64-apple-darwin.tar.gz", sha256: "2162f69c0eff55b6100e4c8a094edf1a19888ca66b49009f546fa46472a6665d" },
	"darwin-x64": { file: "changesetter-x86_64-apple-darwin.tar.gz", sha256: "acfe8250ffc3edaa6707659bea4d40017e16427baef3086a61cd7fa6fabe5d19" },
};

export function changesetterAsset(os: string, arch: string): ChangesetterAsset {
	const asset = ASSETS[`${os}-${arch}`];
	if (asset === undefined) throw new Error(`no changesetter ${CHANGESETTER_VERSION} build for ${os}-${arch}`);
	return asset;
}

export function changesetterUrl(asset: ChangesetterAsset): string {
	return `https://github.com/Saturate/changesetter/releases/download/changesetter%40v${CHANGESETTER_VERSION}/${asset.file}`;
}

export function changesetterDir(root: string): string {
	return join(root, "tools", "changesetter");
}

export function changesetterBin(root: string, os: string): string {
	return join(changesetterDir(root), os === "win32" ? "changesetter.exe" : "changesetter");
}
