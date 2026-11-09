// MCP server for running Slopocalypse games: lets any agent harness inspect and drive a game
// started with `-- --debug-api`. Register it as a stdio server: `node tools/mcp/server.ts`
// (.mcp.json does this for Claude Code).
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { env, platform, stdin, stdout } from "node:process";
import { createInterface } from "node:readline";
import { ApiError, discover, godotUserDir, pickTarget, rpc, type Game } from "../lib/debug-api.ts";
import { handleLine, type CallResult, type Tool } from "../lib/mcp.ts";

const userDir = godotUserDir(platform, env, homedir());

const TARGET = { type: "string", description: "Which game: a pid, or \"client\" / \"server\". Default: the client, if one is running." };

const TOOLS: Tool[] = [
	{ name: "list_games", description: "Running games with the debug API on (started with `-- --debug-api`): pid, role (client or server) and whether they answer.", inputSchema: { type: "object", properties: {} } },
	{ name: "game_state", description: "Session (mode, peers), players and their positions, loaded modules, fps and the newest performance sample.", inputSchema: { type: "object", properties: { target: TARGET } } },
	{ name: "game_perf", description: "The newest performance sample: frame times (mean, p95, worst), physics and process time, nodes, memory, draw calls, network bytes, custom monitors.", inputSchema: { type: "object", properties: { target: TARGET } } },
	{
		name: "find_nodes",
		description: "Find nodes in the scene tree by name or path pattern (* and ? wildcards) and optional class.",
		inputSchema: { type: "object", properties: { pattern: { type: "string" }, type: { type: "string", description: "Godot class, e.g. RigidBody3D" }, limit: { type: "number" }, target: TARGET }, required: ["pattern"] },
	},
	{ name: "get_node", description: "A node's class, script, stored properties (as Godot value strings), children and global position.", inputSchema: { type: "object", properties: { path: { type: "string" }, target: TARGET }, required: ["path"] } },
	{
		name: "set_property",
		description: "Set a node property from a Godot value string, e.g. Vector3(0, 5, 0) or true.",
		inputSchema: { type: "object", properties: { path: { type: "string" }, property: { type: "string" }, value: { type: "string" }, target: TARGET }, required: ["path", "property", "value"] },
	},
	{
		name: "publish_event",
		description: "Publish an EventBus event in the game (topics are module.event, e.g. admin.set_hour). Server-side events go to the server target.",
		inputSchema: { type: "object", properties: { topic: { type: "string" }, payload: { type: "object" }, target: TARGET }, required: ["topic"] },
	},
	{ name: "screenshot", description: "What the client's window shows right now, as an image.", inputSchema: { type: "object", properties: { target: TARGET } } },
	{ name: "tail_log", description: "The last lines of the game's log file.", inputSchema: { type: "object", properties: { lines: { type: "number" }, target: TARGET } } },
];

const METHOD: Record<string, string> = { game_state: "state", game_perf: "perf", find_nodes: "find_nodes", get_node: "node", set_property: "set", publish_event: "publish", tail_log: "log" };

function text(value: unknown): CallResult {
	return { content: [{ type: "text", text: typeof value === "string" ? value : JSON.stringify(value, null, 2) }] };
}

function target(args: Record<string, unknown>): string | number | undefined {
	const t = args["target"];
	return typeof t === "string" || typeof t === "number" ? t : undefined;
}

function game(args: Record<string, unknown>): Game {
	const games = discover(userDir);
	if (games.length === 0) throw new ApiError(`no game with the debug API is running (start one with \`-- --debug-api\`; looked in ${userDir})`);
	const g = pickTarget(games, target(args));
	if (g === undefined) throw new ApiError(`no game matches ${String(target(args))}; running: ${games.map((x) => `${x.pid} (${x.role})`).join(", ")}`);
	return g;
}

async function call(name: string, args: Record<string, unknown>): Promise<CallResult> {
	if (name === "list_games") {
		const games = await Promise.all(
			discover(userDir).map(async (g) => {
				const alive = await rpc(g, "ping", {}, 1500).then(
					() => true,
					() => false,
				);
				return { pid: g.pid, role: g.role, port: g.port, alive };
			}),
		);
		return text(games.length > 0 ? games : `none running (start one with \`-- --debug-api\`; looked in ${userDir})`);
	}
	if (name === "screenshot") {
		const shot = await rpc(game(args), "screenshot");
		const path = typeof shot === "object" && shot !== null ? Reflect.get(shot, "path") : undefined;
		if (typeof path !== "string") throw new ApiError("the game did not return a screenshot path");
		return { content: [{ type: "image", data: readFileSync(path).toString("base64"), mimeType: "image/png" }, { type: "text", text: path }] };
	}
	const { target: _drop, ...params } = args;
	return text(await rpc(game(args), METHOD[name] ?? name, params));
}

const lines = createInterface({ input: stdin });
lines.on("line", (line) => {
	if (line.trim() === "") return;
	void handleLine(line, TOOLS, call, { name: "slopocalypse", version: "1.0.0" }).then((res) => {
		if (res !== undefined) stdout.write(JSON.stringify(res) + "\n");
	});
});
