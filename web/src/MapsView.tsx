import { useCallback, useEffect, useRef, useState, type MouseEvent } from "react";
import { get, isMapList, isRecipe, isRenderResult, LAYERS, post, type Layer, type RenderResult } from "./api.ts";

// The world-generation viewer (#448): a recipe and seed rendered on the server, its layers,
// stats and a hover readout, pan and zoom, and an editor to render changed numbers. Saving
// recipes is for the local viewer: a server's files are its own.
export function MapsView() {
	const [maps, setMaps] = useState<string[]>([]);
	const [map, setMap] = useState("");
	const [seed, setSeed] = useState(1);
	const [pixels, setPixels] = useState(512);
	const [layers, setLayers] = useState<Layer[]>([...LAYERS]);
	const [stored, setStored] = useState("");
	const [recipeText, setRecipeText] = useState("");
	// An edited recipe belongs to the map it was edited on; switching maps drops it.
	const [edited, setEdited] = useState<{ map: string; recipe: Record<string, unknown> } | null>(null);
	const [result, setResult] = useState<RenderResult | null>(null);
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState("");

	useEffect(() => {
		get("/admin/api/v1/maps", isMapList)
			.then((list) => {
				setMaps(list.maps);
				setMap((m) => m || list.maps[0] || "");
			})
			.catch((e: unknown) => setError(message(e)));
	}, []);

	useEffect(() => {
		if (map === "") return;
		get(`/admin/api/v1/maps/${encodeURIComponent(map)}`, isRecipe)
			.then((r) => {
				const text = JSON.stringify(r, null, 2);
				setStored(text);
				setRecipeText(text);
				setEdited(null);
			})
			.catch((e: unknown) => setError(message(e)));
	}, [map]);

	// Stepping seeds asks for renders faster than they finish: each new one aborts the last,
	// so the server never starts renders nobody waits for (it skips requests whose connection
	// is gone), and only the newest answer is shown.
	useEffect(() => {
		if (map === "" || edited?.map !== undefined && edited.map !== map) return;
		const abort = new AbortController();
		setBusy(true);
		setError("");
		const body = { map, seed, pixels, layers, ...(edited === null ? {} : { recipe: edited.recipe }) };
		post("/admin/api/v1/maps/render", body, isRenderResult, abort.signal)
			.then(setResult)
			.catch((e: unknown) => abort.signal.aborted || setError(message(e)))
			.finally(() => abort.signal.aborted || setBusy(false));
		return () => abort.abort();
	}, [map, seed, pixels, layers, edited]);

	// Arrow keys step through seeds, unless typing.
	useEffect(() => {
		const onKey = (e: KeyboardEvent) => {
			if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
			if (e.key === "ArrowLeft") setSeed((s) => Math.max(0, s - 1));
			if (e.key === "ArrowRight") setSeed((s) => s + 1);
		};
		addEventListener("keydown", onKey);
		return () => removeEventListener("keydown", onKey);
	}, []);

	const applyEdit = () => {
		try {
			const parsed: unknown = JSON.parse(recipeText);
			if (!isRecipe(parsed)) throw new Error("the recipe must be a JSON object");
			setEdited({ map, recipe: parsed });
		} catch (e) {
			setError(message(e));
		}
	};

	return (
		<div className="maps">
			<MapCanvas result={result} busy={busy} />
			<aside>
				<section>
					<h2>Map</h2>
					<div className="row">
						<select
							value={map}
							onChange={(e) => {
								setEdited(null);
								setMap(e.target.value);
							}}
						>
							{maps.map((m) => (
								<option key={m}>{m}</option>
							))}
						</select>
						<button onClick={() => setSeed((s) => Math.max(0, s - 1))} title="Previous seed (←)">
							◀
						</button>
						<input type="number" min={0} value={seed} onChange={(e) => setSeed(Math.max(0, Math.floor(Number(e.target.value) || 0)))} />
						<button onClick={() => setSeed((s) => s + 1)} title="Next seed (→)">
							▶
						</button>
					</div>
					<label className="row">
						Size
						<select value={pixels} onChange={(e) => setPixels(Number(e.target.value))}>
							{[256, 512, 1024].map((p) => (
								<option key={p} value={p}>
									{p}
								</option>
							))}
						</select>
					</label>
				</section>
				<section>
					<h2>Layers</h2>
					<div className="row">
						{LAYERS.map((l) => (
							<label key={l}>
								<input type="checkbox" checked={layers.includes(l)} onChange={(e) => setLayers((ls) => (e.target.checked ? [...ls, l] : ls.filter((x) => x !== l)))} /> {l}
							</label>
						))}
					</div>
				</section>
				<section>
					<h2>Stats</h2>
					<table>
						<tbody>
							{Object.entries(result?.stats.summary ?? {}).map(([k, v]) => (
								<tr key={k}>
									<td>{k}</td>
									<td>{v}</td>
								</tr>
							))}
						</tbody>
					</table>
				</section>
				<section>
					<h2>Recipe</h2>
					<textarea value={recipeText} spellCheck={false} onChange={(e) => setRecipeText(e.target.value)} />
					<div className="row">
						<button onClick={applyEdit}>Render with these values</button>
						<button
								onClick={() => {
									setRecipeText(stored);
									setEdited(null);
								}}
							>
								Back to stored
							</button>
					</div>
					<p className="dim">Edits render without saving. Save tuned recipes from the local viewer (node tools/map-viewer.ts).</p>
					{edited !== null ? <p className="dim">Showing an edited recipe.</p> : null}
					{error !== "" ? <p className="error">{error}</p> : null}
				</section>
			</aside>
		</div>
	);
}

function message(e: unknown): string {
	return e instanceof Error ? e.message : String(e);
}

// The render on a canvas: drag to pan, wheel to zoom about the cursor, hover for x, z,
// height and zone from the stats grid.
function MapCanvas({ result, busy }: { result: RenderResult | null; busy: boolean }) {
	const canvas = useRef<HTMLCanvasElement>(null);
	const image = useRef<HTMLImageElement | null>(null);
	const view = useRef({ x: 0, y: 0, scale: 1 });
	const drag = useRef<{ x: number; y: number } | null>(null);
	const [hover, setHover] = useState("");

	const draw = useCallback(() => {
		const c = canvas.current;
		const ctx = c?.getContext("2d");
		if (!c || !ctx) return;
		c.width = c.clientWidth * devicePixelRatio;
		c.height = c.clientHeight * devicePixelRatio;
		ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
		ctx.imageSmoothingEnabled = false;
		ctx.clearRect(0, 0, c.width, c.height);
		const img = image.current;
		const v = view.current;
		if (img) ctx.drawImage(img, v.x, v.y, img.width * v.scale, img.height * v.scale);
	}, []);

	const fit = useCallback(() => {
		const c = canvas.current;
		const img = image.current;
		if (!c || !img) return;
		const scale = Math.min(c.clientWidth, c.clientHeight) / img.width;
		view.current = { scale, x: (c.clientWidth - img.width * scale) / 2, y: (c.clientHeight - img.height * scale) / 2 };
		draw();
	}, [draw]);

	useEffect(() => {
		if (result === null) return;
		const img = new Image();
		let current = true;
		img.onload = () => {
			if (!current) return;
			const first = image.current === null || image.current.width !== img.width;
			image.current = img;
			if (first) fit();
			else draw();
		};
		img.src = new URL(result.image, window.location.origin).toString();
		return () => {
			current = false;
		};
	}, [result, fit, draw]);

	// React attaches wheel listeners as passive, so preventDefault there cannot stop the page
	// scrolling while zooming; a listener of our own can.
	useEffect(() => {
		const c = canvas.current;
		if (!c) return;
		const onWheel = (e: WheelEvent) => {
			e.preventDefault();
			const rect = c.getBoundingClientRect();
			const mx = e.clientX - rect.left;
			const my = e.clientY - rect.top;
			const f = Math.exp(-e.deltaY * 0.0015);
			const v = view.current;
			v.x = mx - (mx - v.x) * f;
			v.y = my - (my - v.y) * f;
			v.scale *= f;
			draw();
		};
		c.addEventListener("wheel", onWheel, { passive: false });
		return () => c.removeEventListener("wheel", onWheel);
	}, [draw]);

	useEffect(() => {
		addEventListener("resize", draw);
		return () => removeEventListener("resize", draw);
	}, [draw]);

	const onMove = (e: MouseEvent<HTMLCanvasElement>) => {
		const v = view.current;
		if (drag.current) {
			v.x = e.clientX - drag.current.x;
			v.y = e.clientY - drag.current.y;
			draw();
		}
		const img = image.current;
		const grid = result?.stats.grid;
		if (!img || !grid) return;
		const rect = e.currentTarget.getBoundingClientRect();
		const px = (e.clientX - rect.left - v.x) / v.scale / img.width;
		const py = (e.clientY - rect.top - v.y) / v.scale / img.height;
		if (px < 0 || py < 0 || px >= 1 || py >= 1) return setHover("");
		const i = Math.min(grid.cells - 1, Math.floor(px * grid.cells));
		const j = Math.min(grid.cells - 1, Math.floor(py * grid.cells));
		const k = j * grid.cells + i;
		const zone = grid.kinds[grid.zones[k] ?? -1] ?? "";
		setHover(`x ${(grid.left + px * grid.size).toFixed(0)}  z ${(grid.top + py * grid.size).toFixed(0)}  height ${(grid.heights[k] ?? 0).toFixed(1)} m  ${zone}`);
	};

	return (
		<div className="view">
			<canvas
				ref={canvas}
				onMouseDown={(e) => (drag.current = { x: e.clientX - view.current.x, y: e.clientY - view.current.y })}
				onMouseUp={() => (drag.current = null)}
				onMouseLeave={() => (drag.current = null)}
				onMouseMove={onMove}
				onDoubleClick={fit}
			/>
			{busy ? <div className="badge top">Rendering…</div> : null}
			{hover !== "" ? <div className="badge bottom">{hover}</div> : null}
		</div>
	);
}
