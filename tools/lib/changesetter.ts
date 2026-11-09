// changesetter: versions and changelog from `.changeset/*.md` files. A pinned release binary
// lives in tools/changesetter/ (git-ignored), fetched by tools/get-changesetter.ts.
import { join } from "node:path";

export const CHANGESETTER_VERSION = "0.5.0";

export interface ChangesetterAsset {
	file: string;
	sha256: string;
}

// Release assets do not ship checksum files; these were computed from the published archives.
const ASSETS: Readonly<Record<string, ChangesetterAsset>> = {
	"win32-x64": { file: "changesetter-x86_64-pc-windows-msvc.zip", sha256: "6e83e604772e3a1afce9b2daed0f8eb84344acfc15c49c08a0bbdaa71e1364be" },
	"linux-x64": { file: "changesetter-x86_64-unknown-linux-gnu.tar.gz", sha256: "775c10689184dd70fdc2a65bb3f0dd25c57489c5d626b59ce9c686d2e8027172" },
	"linux-arm64": { file: "changesetter-aarch64-unknown-linux-gnu.tar.gz", sha256: "dca7c7aebfee0b5c7681ef391b17cbfc6a1483b3433d0075fdeda52d90f0cb68" },
	"darwin-arm64": { file: "changesetter-aarch64-apple-darwin.tar.gz", sha256: "87a6a89563e9b3cc8a4e9cc5d51b434102456123bb35dc092326f4e06ea7af24" },
	"darwin-x64": { file: "changesetter-x86_64-apple-darwin.tar.gz", sha256: "7a021c66a4020d91385e7bf9d05c89993582ec8c865009540dadfc916a1eb20e" },
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
