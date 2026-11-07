import assert from "node:assert/strict";
import { test } from "node:test";
import { checkScript, installScript, quote, serverIsUp, systemdUnit, type DeployTarget } from "./deploy.ts";

const target: DeployTarget = { dir: "/opt/outpost", port: 7777, user: "outpost", keep: 3, openFirewall: false };

test("the service runs the headless server on the chosen port as its own user", () => {
	const unit = systemdUnit({ ...target, port: 9000 });
	assert.match(unit, /^User=outpost$/m);
	assert.match(unit, /^ExecStart=\/opt\/outpost\/current\/Outpost\.x86_64 --headless -- --server=9000$/m);
	assert.match(unit, /^Restart=on-failure$/m);
	assert.match(unit, /^Environment=HOME=\/opt\/outpost\/home$/m);
});

test("install unpacks a new release, points current at it and restarts", () => {
	const s = installScript(target, "20261107-1200", "/tmp/outpost.tar.gz");
	const order = ["tar -xzf", "ln -sfn", "systemctl daemon-reload", "systemctl restart outpost"].map((step) => s.indexOf(step));
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
	const journal = "Nov 07 outpost[1]: [INFO] net: server listening on port 7777";
	assert.equal(serverIsUp("active\n", journal, 7777), true);
	assert.equal(serverIsUp("failed\n", journal, 7777), false);
	assert.equal(serverIsUp("active\n", journal, 9000), false);
	assert.match(checkScript(target), /journalctl -u outpost/);
});
