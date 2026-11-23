// The dedicated server's arguments from tools/server.ts's own: the port, and everything after
// `--` passed to the game unchanged (--web, --no-save, --save=PATH). Without the passthrough
// `-- --no-save` was dropped silently and a test server wrote the player's own world.
export function serverArgs(argv: readonly string[]): { port: string; game: string[] } {
	const split = argv.indexOf("--");
	const own = split >= 0 ? argv.slice(0, split) : argv;
	const at = own.indexOf("--port");
	const joined = own.find((a) => a.startsWith("--port="));
	const port = joined !== undefined ? joined.slice("--port=".length) : at >= 0 ? own[at + 1] : "7777";
	if (port === undefined || !/^\d+$/.test(port) || Number(port) < 1 || Number(port) > 65535) throw new Error(`--port needs a number from 1 to 65535, got ${port ?? "nothing"}`);
	return { port, game: [`--server=${port}`, ...(split >= 0 ? argv.slice(split + 1) : [])] };
}
