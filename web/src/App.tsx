import { useEffect, useState } from "react";
import { get, isStatus, type Status } from "./api.ts";
import { MapsView } from "./MapsView.tsx";

type Tab = "status" | "maps" | "live";

const TABS: { id: Tab; label: string; ready: boolean }[] = [
	{ id: "status", label: "Status", ready: true },
	{ id: "maps", label: "Map viewer", ready: true },
	{ id: "live", label: "Live map", ready: false },
];

export function App() {
	const [tab, setTab] = useState<Tab>("status");
	return (
		<div className="app">
			<header>
				<h1>Slopocalypse admin</h1>
				<nav>
					{TABS.map((t) => (
						<button key={t.id} className={t.id === tab ? "on" : ""} disabled={!t.ready} onClick={() => setTab(t.id)} title={t.ready ? "" : "Coming next"}>
							{t.label}
						</button>
					))}
				</nav>
			</header>
			<main>{tab === "status" ? <StatusView /> : tab === "maps" ? <MapsView /> : <p className="dim">Coming next.</p>}</main>
		</div>
	);
}

// Polls the public status every few seconds.
function StatusView() {
	const [status, setStatus] = useState<Status | null>(null);
	const [error, setError] = useState("");
	useEffect(() => {
		let alive = true;
		const load = () =>
			get("/api/v1/status", isStatus)
				.then((s) => alive && (setStatus(s), setError("")))
				.catch((e: unknown) => alive && setError(e instanceof Error ? e.message : String(e)));
		void load();
		const timer = setInterval(load, STATUS_POLL_MS);
		return () => {
			alive = false;
			clearInterval(timer);
		};
	}, []);
	if (error !== "") return <p className="error">{error}</p>;
	if (status === null) return <p className="dim">Loading…</p>;
	return (
		<section>
			<p className="dim">
				Version {status.version} · up {Math.floor(status.uptime_seconds / 60)} min · {status.soldiers_alive} soldiers alive
			</p>
			<h2>Players online: {status.players.length}</h2>
			<ul>
				{status.players.map((p) => (
					<li key={p}>{p}</li>
				))}
			</ul>
			{status.mission ? (
				<p>
					On a mission: <b>{status.mission.codename}</b> · {status.mission.kind} · {status.mission.place} · pays {status.mission.pays}
				</p>
			) : null}
		</section>
	);
}

// The status changes slowly: every few seconds is plenty.
const STATUS_POLL_MS = 5000;
