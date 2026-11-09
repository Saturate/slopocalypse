// changesetter: versions and changelog from `.changeset/*.md` files. A pinned release binary
// lives in tools/changesetter/ (git-ignored), fetched by tools/get-changesetter.ts.
import { join } from "node:path";

export const CHANGESETTER_VERSION = "0.5.1";

export interface ChangesetterAsset {
	file: string;
	sha256: string;
}

// Release assets do not ship checksum files; these were computed from the published archives.
const ASSETS: Readonly<Record<string, ChangesetterAsset>> = {
	"win32-x64": { file: "changesetter-x86_64-pc-windows-msvc.zip", sha256: "3d9e72a744138dbda859c7c444d1aba7f2e12b8a332c27fc86891bd3248d5092" },
	"linux-x64": { file: "changesetter-x86_64-unknown-linux-gnu.tar.gz", sha256: "473a950d5f6f55f130d20eca285b8acf1653ef9179a6110029eb4ca416e476f6" },
	"linux-arm64": { file: "changesetter-aarch64-unknown-linux-gnu.tar.gz", sha256: "db59fbe98d4f225c81433f0a545986ab448bd85b5b60b3210b14a55574e76ea5" },
	"darwin-arm64": { file: "changesetter-aarch64-apple-darwin.tar.gz", sha256: "ba988b5288bfd7de90d9baad82ee132acb3eaf38e02ea40362b6b76a40b454ab" },
	"darwin-x64": { file: "changesetter-x86_64-apple-darwin.tar.gz", sha256: "854418c3c768baa172b06d1436e2a0fd2e2cb368c665f37b3f15dff6419b97e1" },
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
