import assert from "node:assert/strict";
import { test } from "node:test";
import { handleLine, type CallTool, type Tool } from "./mcp.ts";

const tools: Tool[] = [{ name: "echo", description: "says it back", inputSchema: { type: "object" } }];
const call: CallTool = async (name, args) => {
	if (args["boom"] === true) throw new Error("it broke");
	return { content: [{ type: "text", text: `${name}:${JSON.stringify(args)}` }] };
};
const server = { name: "test", version: "1" };

test("initialize answers with the client's protocol version and tool support", async () => {
	const res = await handleLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}', tools, call, server);
	assert.deepEqual(res, { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: server } });
});

test("notifications get no reply", async () => {
	assert.equal(await handleLine('{"jsonrpc":"2.0","method":"notifications/initialized"}', tools, call, server), undefined);
});

test("tools are listed and called", async () => {
	const list = await handleLine('{"jsonrpc":"2.0","id":2,"method":"tools/list"}', tools, call, server);
	assert.deepEqual(list?.["result"], { tools });
	const res = await handleLine('{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"a":1}}}', tools, call, server);
	assert.deepEqual(res?.["result"], { content: [{ type: "text", text: 'echo:{"a":1}' }] });
});

test("a failing tool is a tool error, not a protocol error", async () => {
	const res = await handleLine('{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{"boom":true}}}', tools, call, server);
	assert.deepEqual(res?.["result"], { content: [{ type: "text", text: "it broke" }], isError: true });
});

test("unknown tools, unknown methods and bad JSON are JSON-RPC errors", async () => {
	const tool = await handleLine('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope"}}', tools, call, server);
	assert.equal((tool?.["error"] as { code: number }).code, -32602);
	const method = await handleLine('{"jsonrpc":"2.0","id":6,"method":"resources/list"}', tools, call, server);
	assert.equal((method?.["error"] as { code: number }).code, -32601);
	const bad = await handleLine("{nope", tools, call, server);
	assert.equal((bad?.["error"] as { code: number }).code, -32700);
});
