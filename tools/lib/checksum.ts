import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";

export function expectedSha512(sums: string, fileName: string): string {
	for (const line of sums.split(/\r?\n/)) {
		const match = /^([0-9a-f]{128})\s+\*?(.+)$/.exec(line.trim());
		if (match?.[2] === fileName && match[1] !== undefined) {
			return match[1];
		}
	}
	throw new Error(`${fileName} is not listed in the SHA512 sums`);
}

export async function verifySha512(file: string, expected: string): Promise<void> {
	const hash = createHash("sha512");
	for await (const chunk of createReadStream(file)) {
		hash.update(chunk);
	}
	const actual = hash.digest("hex");
	if (actual !== expected) {
		throw new Error(`checksum mismatch for ${file}: expected ${expected}, got ${actual}`);
	}
}
