// Pieces of tools/deploy.ts that are pure text, so they can be tested without a server.

export interface DeployTarget {
	// Install folder on the server; releases/<stamp> and a `current` link live inside it.
	dir: string;
	port: number;
	// System user the service runs as; created if missing.
	user: string;
	// Releases kept on disk so a bad deploy can be rolled back by hand.
	keep: number;
	openFirewall: boolean;
}

export const SERVICE = "outpost";
export const LINUX_EXE = "Outpost.x86_64";

// A shell-safe single-quoted word.
export function quote(value: string): string {
	return `'${value.replaceAll("'", `'\\''`)}'`;
}

export function systemdUnit(t: DeployTarget): string {
	return [
		"[Unit]",
		"Description=Outpost dedicated server",
		"After=network-online.target",
		"Wants=network-online.target",
		"",
		"[Service]",
		`User=${t.user}`,
		`WorkingDirectory=${t.dir}/current`,
		// user:// resolves under HOME; keep it inside the install folder, not a login home.
		`Environment=HOME=${t.dir}/home`,
		// The save sits beside the releases, so upgrades and rollbacks keep everyone's gear.
		`ExecStart=${t.dir}/current/${LINUX_EXE} --headless -- --server=${t.port} --save=${t.dir}/saves/world.db`,
		"Restart=on-failure",
		"RestartSec=3",
		"",
		"[Install]",
		"WantedBy=multi-user.target",
		"",
	].join("\n");
}

// Runs on the server over ssh (bash -s), after the tarball has been copied to `tarball`.
export function installScript(t: DeployTarget, stamp: string, tarball: string): string {
	const dir = quote(t.dir);
	const rel = quote(`${t.dir}/releases/${stamp}`);
	return [
		"set -euo pipefail",
		// Root logs in without sudo; everyone else needs it for /opt and systemd.
		'if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi',
		`id -u ${quote(t.user)} >/dev/null 2>&1 || $SUDO useradd --system --home-dir ${dir} --shell /usr/sbin/nologin ${quote(t.user)}`,
		`$SUDO mkdir -p ${rel} ${quote(`${t.dir}/home`)} ${quote(`${t.dir}/saves`)}`,
		`$SUDO tar -xzf ${quote(tarball)} -C ${rel}`,
		`$SUDO chmod +x ${quote(`${t.dir}/releases/${stamp}/${LINUX_EXE}`)}`,
		`$SUDO ln -sfn ${rel} ${quote(`${t.dir}/current`)}`,
		`$SUDO chown -R ${quote(t.user)} ${quote(`${t.dir}/home`)} ${quote(`${t.dir}/saves`)}`,
		`rm -f ${quote(tarball)}`,
		`$SUDO tee /etc/systemd/system/${SERVICE}.service >/dev/null <<'UNIT'`,
		systemdUnit(t).trimEnd(),
		"UNIT",
		"$SUDO systemctl daemon-reload",
		`$SUDO systemctl enable ${SERVICE} >/dev/null 2>&1`,
		`$SUDO systemctl restart ${SERVICE}`,
		...(t.openFirewall ? [`if command -v ufw >/dev/null 2>&1; then $SUDO ufw allow ${t.port}/udp; fi`] : []),
		// Oldest releases go; `current` always points at a kept one.
		`cd ${quote(`${t.dir}/releases`)} && ls -1 | sort | head -n -${t.keep} | xargs -r $SUDO rm -rf`,
		"",
	].join("\n");
}

// Runs on the server after the restart: is it up and listening?
export function checkScript(t: DeployTarget): string {
	return [
		"set -uo pipefail",
		'if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi',
		"sleep 6",
		`systemctl is-active ${SERVICE}`,
		`$SUDO journalctl -u ${SERVICE} -n 40 --no-pager`,
		"",
	].join("\n");
}

// The journal shows Godot's log; the server prints this once ENet is bound.
export function serverIsUp(active: string, journal: string, port: number): boolean {
	return active.trim().split("\n")[0] === "active" && journal.includes(`server listening on port ${port}`);
}
