// A small Model Context Protocol server: JSON-RPC 2.0 messages, one per line over stdio.
// Only what tools need: initialize, ping, tools/list, tools/call. Written by hand so the
// project needs no MCP library.

export interface Tool {
	name: string;
	description: string;
	inputSchema: Record<string, unknown>;
}

export type Content = { type: "text"; text: string } | { type: "image"; data: string; mimeType: string };

export interface CallResult {
	content: Content[];
	isError?: boolean;
}

export type CallTool = (name: string, args: Record<string, unknown>) => Promise<CallResult>;

export const PROTOCOL_VERSION = "2025-06-18";

interface Message {
	id?: string | number | null;
	method?: string;
	params?: unknown;
}

function isRecord(v: unknown): v is Record<string, unknown> {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

function reply(id: Message["id"], result: unknown): Record<string, unknown> {
	return { jsonrpc: "2.0", id: id ?? null, result };
}

function fail(id: Message["id"], code: number, message: string): Record<string, unknown> {
	return { jsonrpc: "2.0", id: id ?? null, error: { code, message } };
}

// The response to one incoming line, or undefined for notifications.
export async function handleLine(line: string, tools: readonly Tool[], call: CallTool, server: { name: string; version: string }): Promise<Record<string, unknown> | undefined> {
	let msg: unknown;
	try {
		msg = JSON.parse(line);
	} catch {
		return fail(null, -32700, "parse error");
	}
	if (!isRecord(msg) || typeof msg["method"] !== "string") return fail(null, -32600, "invalid request");
	const id = msg["id"];
	const isNotification = id === undefined;
	const rid = typeof id === "string" || typeof id === "number" ? id : null;
	const params = isRecord(msg["params"]) ? msg["params"] : {};
	switch (msg["method"]) {
		case "initialize": {
			const asked = params["protocolVersion"];
			return reply(rid, {
				protocolVersion: typeof asked === "string" ? asked : PROTOCOL_VERSION,
				capabilities: { tools: {} },
				serverInfo: server,
			});
		}
		case "ping":
			return reply(rid, {});
		case "tools/list":
			return reply(rid, { tools });
		case "tools/call": {
			const name = params["name"];
			const args = isRecord(params["arguments"]) ? params["arguments"] : {};
			if (typeof name !== "string" || !tools.some((t) => t.name === name)) return fail(rid, -32602, `unknown tool ${String(name)}`);
			try {
				return reply(rid, await call(name, args));
			} catch (err) {
				return reply(rid, { content: [{ type: "text", text: err instanceof Error ? err.message : String(err) }], isError: true });
			}
		}
		default:
			if (isNotification) return undefined;
			return fail(rid, -32601, `method not found: ${msg["method"]}`);
	}
}
