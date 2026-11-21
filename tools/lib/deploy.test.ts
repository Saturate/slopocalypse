import assert from "node:assert/strict";
import { test } from "node:test";
import { checkScript, installScript, quote, serverIsUp, systemdUnit, webOptions, type DeployTarget } from "./deploy.ts";

const target: DeployTarget = { dir: "/opt/slopocalypse", port: 7777, user: "slopocalypse", keep: 3, openFirewall: false, web: null };

test("the service runs the headless server on the chosen port as its own user", () => {
	const unit = systemdUnit({ ...target, port: 9000 });
	assert.match(unit, /^User=slopocalypse$/m);
	assert.match(unit, /^ExecStart=\/opt\/slopocalypse\/current\/Slopocalypse\.x86_64 --headless -- --server=9000 --save=\/opt\/slopocalypse\/saves\/world\.db$/m);
	assert.match(unit, /^Restart=on-failure$/m);
	assert.match(unit, /^Environment=HOME=\/opt\/slopocalypse\/home$/m);
});

test("install unpacks a new release, points current at it and restarts", () => {
	const s = installScript(target, "20261107-1200", "/tmp/slopocalypse.tar.gz");
	const order = ["tar -xzf", "ln -sfn", "systemctl daemon-reload", "systemctl restart slopocalypse"].map((step) => s.indexOf(step));
	assert.ok(order.every((i) => i >= 0), s);
	assert.deepEqual([...order].sort((a, b) => a - b), order);
	assert.match(s, /releases\/20261107-1200/);
	assert.doesNotMatch(s, /ufw/);
});

test("the firewall is opened only when asked", () => {
	assert.match(installScript({ ...target, openFirewall: true }, "s", "/tmp/t"), /ufw allow 7777\/udp/);
});

test("quoting survives spaces and quotes", () => {
	assert.equal(quote("it's here"), `'it'\\''s here'`);
});

test("up means active and listening on the port", () => {
	const journal = "Nov 07 slopocalypse[1]: [INFO] net: server listening on port 7777";
	assert.equal(serverIsUp("active\n", journal, 7777), true);
	assert.equal(serverIsUp("failed\n", journal, 7777), false);
	assert.equal(serverIsUp("active\n", journal, 9000), false);
	assert.match(checkScript(target), /journalctl -u slopocalypse/);
});

test("the web page is off unless asked for, and only non-default flags are passed", () => {
	assert.doesNotMatch(systemdUnit(target), /--web/);
	assert.match(systemdUnit({ ...target, web: { port: 7777, bind: "*" } }), /world\.db --web$/m);
	assert.match(systemdUnit({ ...target, web: { port: 8080, bind: "127.0.0.1" } }), /world\.db --web --web-port=8080 --web-bind=127\.0\.0\.1$/m);
});

test("web options come from --web, --web-port and --web-bind, and bad ones are refused", () => {
	assert.equal(webOptions(["--host", "me@box"], 7777), null);
	assert.deepEqual(webOptions(["--web"], 7777), { port: 7777, bind: "*" });
	assert.deepEqual(webOptions(["--web-bind", "127.0.0.1"], 9000), { port: 9000, bind: "127.0.0.1" });
	assert.deepEqual(webOptions(["--web-port", "8080"], 7777), { port: 8080, bind: "*" });
	assert.throws(() => webOptions(["--web-port", "http"], 7777), /web-port/);
	assert.throws(() => webOptions(["--web-bind", "localhost"], 7777), /web-bind/);
});

test("the firewall opens the web port only for a page on every address", () => {
	const open = { ...target, openFirewall: true };
	assert.match(installScript({ ...open, web: { port: 8080, bind: "*" } }, "s", "/tmp/t"), /ufw allow 8080\/tcp/);
	assert.doesNotMatch(installScript({ ...open, web: { port: 8080, bind: "127.0.0.1" } }, "s", "/tmp/t"), /tcp/);
});
