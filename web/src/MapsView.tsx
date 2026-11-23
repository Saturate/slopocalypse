import { useCallback, useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { DEFAULT_LAYERS, get, isMapList, isRecipe, isRenderResult, LAYERS, post, type Layer, type Region, type RenderResult } from "./api.ts";

// The world-generation viewer (#448): a recipe and seed rendered on the server, its layers,
// stats and a hover readout, and an editor to render changed numbers. The map fills the
// window; zooming in fetches the part in view at full detail. Saving recipes is for the local
// viewer: a server's files are its own.

const PANEL_KEY = "slop.maps.panel";
// Pixels of the whole-map render; close-ups come on top of it.
const OVERVIEW_PIXELS = 768;

function readPanel(): boolean {
	try {
		return localStorage.getItem(PANEL_KEY) !== "closed";
	} catch {
		return true;
	}
}

function writePanel(open: boolean): void {
	try {
		localStorage.setItem(PANEL_KEY, open ? "open" : "closed");
	} catch {
		// Private windows and blocked storage: the panel just opens next time.
	}
}

type Edited = { map: string; recipe: Record<string, unknown> };

export function MapsView() {
	const [maps, setMaps] = useState<string[]>([]);
	const [map, setMap] = useState("");
	const [seed, setSeed] = useState(1);
	const [layers, setLayers] = useState<Layer[]>([...DEFAULT_LAYERS]);
	const [stored, setStored] = useState("");
	const [recipeText, setRecipeText] = useState("");
	// An edited recipe belongs to the map it was edited on; switching maps drops it.
	const [edited, setEdited] = useState<Edited | null>(null);
	const [result, setResult] = useState<RenderResult | null>(null);
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState("");
	const [panel, setPanel] = useState(readPanel);

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

	// The body for any render of what is chosen now; a close-up adds its region.
	const ask = useCallback(
		(pixels: number, region?: Region) => ({
			map,
			seed,
			pixels,
			layers,
			...(edited === null ? {} : { recipe: edited.recipe }),
			...(region === undefined ? {} : { region }),
		}),
		[map, seed, layers, edited],
	);

	// Stepping seeds asks for renders faster than they finish: each new one aborts the last,
	// so the server never starts renders nobody waits for, and only the newest is shown.
	useEffect(() => {
		if (map === "" || (edited !== null && edited.map !== map)) return;
		const abort = new AbortController();
		setBusy(true);
		setError("");
		post("/admin/api/v1/maps/render", ask(OVERVIEW_PIXELS), isRenderResult, abort.signal)
			.then(setResult)
			.catch((e: unknown) => abort.signal.aborted || setError(message(e)))
			.finally(() => abort.signal.aborted || setBusy(false));
		return () => abort.abort();
	}, [ask, map, edited]);

	// Arrow keys step through seeds, unless typing.
	useEffect(() => {
		const onKey = (e: KeyboardEvent) => {
			if (typing(e.target)) return;
			if (e.key === "ArrowLeft") setSeed((s) => Math.max(0, s - 1));
			if (e.key === "ArrowRight") setSeed((s) => s + 1);
		};
		addEventListener("keydown", onKey);
		return () => removeEventListener("keydown", onKey);
	}, []);

	const detail = useCallback(
		(region: Region, pixels: number, signal: AbortSignal) => post("/admin/api/v1/maps/render", ask(pixels, region), isRenderResult, signal),
		[ask],
	);

	const applyEdit = () => {
		try {
			const parsed: unknown = JSON.parse(recipeText);
			if (!isRecipe(parsed)) throw new Error("the recipe must be a JSON object");
			setEdited({ map, recipe: parsed });
		} catch (e) {
			setError(message(e));
		}
	};

	const togglePanel = () => {
		setPanel((open) => {
			writePanel(!open);
			return !open;
		});
	};

	return (
		<div className={panel ? "maps" : "maps closed"}>
			<div className="bar">
				<select
					value={map}
					aria-label="Map recipe"
					onChange={(e) => {
						setEdited(null);
						setMap(e.target.value);
					}}
				>
					{maps.map((m) => (
						<option key={m}>{m}</option>
					))}
				</select>
				<span className="seed">
					<button onClick={() => setSeed((s) => Math.max(0, s - 1))} title="Previous seed (←)" aria-label="Previous seed">
						◀
					</button>
					<input type="number" min={0} value={seed} aria-label="Seed" onChange={(e) => setSeed(Math.max(0, Math.floor(Number(e.target.value) || 0)))} />
					<button onClick={() => setSeed((s) => s + 1)} title="Next seed (→)" aria-label="Next seed">
						▶
					</button>
				</span>
				{edited !== null ? <span className="dim">edited recipe</span> : null}
				{error !== "" ? <span className="error">{error}</span> : null}
				<button className="push" onClick={togglePanel} aria-expanded={panel}>
					{panel ? "Hide panel ▸" : "◂ Show panel"}
				</button>
			</div>
			<MapCanvas result={result} busy={busy} detail={detail} />
			{panel ? (
				<aside>
					<section>
						<h2>Layers</h2>
						<div className="checks">
							{LAYERS.map((l) => (
								<label key={l}>
									<input type="checkbox" checked={layers.includes(l)} onChange={(e) => setLayers((ls) => (e.target.checked ? [...ls, l] : ls.filter((x) => x !== l)))} /> {l}
								</label>
							))}
						</div>
					</section>
					<section>
						<h2>Stats</h2>
						<dl className="stats">
							{Object.entries(result?.stats.summary ?? {}).map(([k, v]) => (
								<div key={k}>
									<dt>{k}</dt>
									<dd>{v}</dd>
								</div>
							))}
						</dl>
					</section>
					<section>
						<h2>Recipe</h2>
						<textarea value={recipeText} spellCheck={false} aria-label="Recipe JSON" onChange={(e) => setRecipeText(e.target.value)} />
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
					</section>
				</aside>
			) : null}
		</div>
	);
}

function message(e: unknown): string {
	return e instanceof Error ? e.message : String(e);
}

function typing(target: EventTarget | null): boolean {
	return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement;
}

// Where the view looks: the world point at the canvas centre and metres per screen pixel.
type View = { cx: number; cz: number; mpp: number };
type Shown = { region: Region; img: HTMLImageElement };

// A close-up is fetched once the view is this much sharper than the overview, this long after
// the view stops moving.
const DETAIL_FROM = 1.5;
const DETAIL_WAIT_MS = 350;
// Close-ups come in two passes, a quick coarse one then a finer one: the server draws every
// pixel from noise, about 15 s for 1024 square, so the finer pass stops at 512.
const DETAIL_PASSES = [256, 512];
const ZOOM_STEP = 1.6;
// Closest zoom: a quarter metre a screen pixel.
const MIN_MPP = 0.25;

const LEGEND: { label: string; colour: string; dot?: boolean }[] = [
	{ label: "City", colour: "rgb(217, 38, 26)" },
	{ label: "Town", colour: "rgb(242, 140, 26)" },
	{ label: "Camp", colour: "#fff", dot: true },
	{ label: "Road", colour: "rgb(46, 46, 51)" },
	{ label: "Tunnel", colour: "rgb(158, 77, 191)" },
	{ label: "Bridge", colour: "rgb(140, 217, 255)" },
	{ label: "Water", colour: "rgb(61, 115, 148)" },
	{ label: "Farm", colour: "rgb(140, 92, 46)" },
	{ label: "Water tower", colour: "rgb(242, 217, 51)" },
	{ label: "Antenna", colour: "rgb(217, 217, 230)" },
	{ label: "Lookout", colour: "rgb(191, 115, 217)" },
	{ label: "Cabin", colour: "rgb(153, 31, 31)" },
];

function loadImage(path: string): Promise<HTMLImageElement> {
	return new Promise((resolve, reject) => {
		const img = new Image();
		img.onload = () => resolve(img);
		img.onerror = () => reject(new Error(`could not load ${path}`));
		img.src = new URL(path, window.location.origin).toString();
	});
}

// A round length for the scale bar near `metres`: 1, 2 or 5 times a power of ten.
function niceLength(metres: number): number {
	const power = 10 ** Math.floor(Math.log10(metres));
	const lead = metres / power;
	return (lead >= 5 ? 5 : lead >= 2 ? 2 : 1) * power;
}

type Detail = (region: Region, pixels: number, signal: AbortSignal) => Promise<RenderResult>;

// The render on a canvas filling its box: drag or touch to pan, wheel or pinch to zoom, the
// buttons too; double-click fits. Zoomed in, the part in view is fetched at full detail.
function MapCanvas({ result, busy, detail }: { result: RenderResult | null; busy: boolean; detail: Detail }) {
	const box = useRef<HTMLDivElement>(null);
	const canvas = useRef<HTMLCanvasElement>(null);
	const base = useRef<Shown | null>(null);
	const close = useRef<Shown | null>(null);
	const view = useRef<View>({ cx: 0, cz: 0, mpp: 1 });
	const pointers = useRef(new Map<number, { x: number; y: number }>());
	const [hover, setHover] = useState("");
	const [scale, setScale] = useState({ px: 0, label: "" });
	const [fetching, setFetching] = useState(false);
	const settle = useRef<ReturnType<typeof setTimeout> | null>(null);
	const inFlight = useRef<AbortController | null>(null);
	// The latest way to fetch a close-up (it changes with the seed, map and layers); kept in a
	// ref so the drawing callbacks stay the same and a new overview is only handled once.
	const fetchDetail = useRef(detail);
	fetchDetail.current = detail;

	// Whatever close-up is waiting or on its way is for a view that is gone.
	const cancelDetail = () => {
		if (settle.current !== null) clearTimeout(settle.current);
		settle.current = null;
		inFlight.current?.abort();
		inFlight.current = null;
		setFetching(false);
	};

	const size = () => {
		const c = canvas.current;
		return c ? { w: c.clientWidth, h: c.clientHeight } : { w: 1, h: 1 };
	};

	// The view's centre stays over the map, so panning never leaves only empty space in view.
	const keepOnMap = (v: View): View => {
		const whole = base.current;
		if (!whole) return v;
		const r = whole.region;
		return { ...v, cx: Math.min(Math.max(v.cx, r.left), r.left + r.size), cz: Math.min(Math.max(v.cz, r.top), r.top + r.size) };
	};

	const draw = useCallback(() => {
		const c = canvas.current;
		const ctx = c?.getContext("2d");
		if (!c || !ctx) return;
		const { w, h } = size();
		c.width = Math.round(w * devicePixelRatio);
		c.height = Math.round(h * devicePixelRatio);
		ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
		ctx.clearRect(0, 0, w, h);
		const v = view.current;
		for (const shown of [base.current, close.current]) {
			if (!shown) continue;
			const r = shown.region;
			// The overview keeps its pixels crisp; a close-up drawn larger than it was rendered is
			// smoothed, which reads as terrain rather than blocks.
			ctx.imageSmoothingEnabled = shown === close.current;
			ctx.drawImage(shown.img, (r.left - v.cx) / v.mpp + w / 2, (r.top - v.cz) / v.mpp + h / 2, r.size / v.mpp, r.size / v.mpp);
		}
		const metres = niceLength(v.mpp * 120);
		setScale({ px: metres / v.mpp, label: metres >= 1000 ? `${metres / 1000} km` : `${metres} m` });
	}, []);

	// After the view settles: the part in view, sharper than the overview, fetched and drawn
	// over it. A newer view aborts the fetch still running.
	const sharpen = useCallback(() => {
		cancelDetail();
		settle.current = setTimeout(() => {
			const whole = base.current;
			if (!whole) return;
			const v = view.current;
			const overviewMpp = whole.region.size / whole.img.width;
			if (v.mpp * DETAIL_FROM > overviewMpp) return;
			const { w, h } = size();
			const side = Math.min(whole.region.size, Math.max(32, Math.max(w, h) * v.mpp * 1.15));
			const region: Region = {
				left: Math.min(Math.max(v.cx - side / 2, whole.region.left), whole.region.left + whole.region.size - side),
				top: Math.min(Math.max(v.cz - side / 2, whole.region.top), whole.region.top + whole.region.size - side),
				size: side,
			};
			const wanted = Math.max(64, Math.round((side / v.mpp) * Math.min(devicePixelRatio, 2)));
			const passes = DETAIL_PASSES.map((p) => Math.min(p, wanted)).filter((p, i, all) => all.indexOf(p) === i);
			const abort = new AbortController();
			inFlight.current = abort;
			setFetching(true);
			const run = async () => {
				for (const pixels of passes) {
					const r = await fetchDetail.current(region, pixels, abort.signal);
					const img = await loadImage(r.image);
					if (abort.signal.aborted) return;
					close.current = { region: r.region, img };
					draw();
				}
			};
			run()
				.catch(() => {
					// A failed or aborted close-up leaves what is shown.
				})
				.finally(() => abort.signal.aborted || setFetching(false));
		}, DETAIL_WAIT_MS);
	}, [draw]);

	const fit = useCallback(() => {
		const whole = base.current;
		if (!whole) return;
		const { w, h } = size();
		view.current = { cx: whole.region.left + whole.region.size / 2, cz: whole.region.top + whole.region.size / 2, mpp: whole.region.size / Math.min(w, h) };
		cancelDetail();
		close.current = null;
		draw();
	}, [draw]);

	// Zooms by `factor` keeping the world point under screen (sx, sy) where it is.
	const zoom = useCallback(
		(factor: number, sx?: number, sy?: number) => {
			const whole = base.current;
			if (!whole) return;
			const { w, h } = size();
			const x = sx ?? w / 2;
			const y = sy ?? h / 2;
			const v = view.current;
			const mpp = Math.min(Math.max(v.mpp / factor, MIN_MPP), (whole.region.size / Math.min(w, h)) * 2);
			const wx = v.cx + (x - w / 2) * v.mpp;
			const wz = v.cz + (y - h / 2) * v.mpp;
			view.current = keepOnMap({ cx: wx - (x - w / 2) * mpp, cz: wz - (y - h / 2) * mpp, mpp });
			draw();
			sharpen();
		},
		[draw, sharpen],
	);

	// A new render (map, seed, layers or recipe changed): the overview is replaced and the
	// close-up dropped; the view stays where it was unless this is the first.
	useEffect(() => {
		if (result === null) return;
		let current = true;
		loadImage(result.image)
			.then((img) => {
				if (!current) return;
				const first = base.current === null;
				base.current = { region: result.region, img };
				cancelDetail();
				close.current = null;
				if (first) fit();
				else {
					draw();
					sharpen();
				}
			})
			.catch(() => {
				// The overview stays as it was; the next render tries again.
			});
		return () => {
			current = false;
		};
	}, [result, fit, draw, sharpen]);

	useEffect(() => {
		const el = box.current;
		if (!el) return;
		const watch = new ResizeObserver(() => draw());
		watch.observe(el);
		return () => watch.disconnect();
	}, [draw]);

	// React attaches wheel listeners as passive, so preventDefault there cannot stop the page
	// scrolling while zooming; a listener of our own can.
	useEffect(() => {
		const c = canvas.current;
		if (!c) return;
		const onWheel = (e: WheelEvent) => {
			e.preventDefault();
			const rect = c.getBoundingClientRect();
			zoom(Math.exp(-e.deltaY * 0.0015), e.clientX - rect.left, e.clientY - rect.top);
		};
		c.addEventListener("wheel", onWheel, { passive: false });
		return () => c.removeEventListener("wheel", onWheel);
	}, [zoom]);

	useEffect(() => {
		const onKey = (e: KeyboardEvent) => {
			if (typing(e.target)) return;
			if (e.key === "+" || e.key === "=") zoom(ZOOM_STEP);
			if (e.key === "-") zoom(1 / ZOOM_STEP);
			if (e.key === "0") fit();
		};
		addEventListener("keydown", onKey);
		return () => removeEventListener("keydown", onKey);
	}, [zoom, fit]);

	useEffect(
		() => () => {
			inFlight.current?.abort();
			if (settle.current !== null) clearTimeout(settle.current);
		},
		[],
	);

	const readout = (sx: number, sy: number) => {
		const grid = result?.stats.grid;
		if (!grid) return;
		const { w, h } = size();
		const v = view.current;
		const x = v.cx + (sx - w / 2) * v.mpp;
		const z = v.cz + (sy - h / 2) * v.mpp;
		const u = (x - grid.left) / grid.size;
		const t = (z - grid.top) / grid.size;
		if (u < 0 || t < 0 || u >= 1 || t >= 1) return setHover("");
		const k = Math.min(grid.cells - 1, Math.floor(t * grid.cells)) * grid.cells + Math.min(grid.cells - 1, Math.floor(u * grid.cells));
		const zone = grid.kinds[grid.zones[k] ?? -1] ?? "";
		setHover(`x ${x.toFixed(0)}  z ${z.toFixed(0)}  ${(grid.heights[k] ?? 0).toFixed(1)} m  ${zone}`);
	};

	const onDown = (e: ReactPointerEvent<HTMLCanvasElement>) => {
		e.currentTarget.setPointerCapture(e.pointerId);
		pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
	};

	const onMove = (e: ReactPointerEvent<HTMLCanvasElement>) => {
		const rect = e.currentTarget.getBoundingClientRect();
		const was = pointers.current.get(e.pointerId);
		if (!was) {
			readout(e.clientX - rect.left, e.clientY - rect.top);
			return;
		}
		const other = [...pointers.current.entries()].find(([id]) => id !== e.pointerId)?.[1];
		if (other !== undefined) {
			// Pinch: zoom by how much the two fingers spread, about the point between them.
			const before = Math.hypot(was.x - other.x, was.y - other.y);
			const after = Math.hypot(e.clientX - other.x, e.clientY - other.y);
			if (before > 0) zoom(after / before, (e.clientX + other.x) / 2 - rect.left, (e.clientY + other.y) / 2 - rect.top);
		} else {
			const v = view.current;
			view.current = keepOnMap({ ...v, cx: v.cx - (e.clientX - was.x) * v.mpp, cz: v.cz - (e.clientY - was.y) * v.mpp });
			draw();
			sharpen();
		}
		pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
	};

	const onUp = (e: ReactPointerEvent<HTMLCanvasElement>) => {
		pointers.current.delete(e.pointerId);
	};

	return (
		<div className="view" ref={box}>
			<canvas ref={canvas} onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp} onPointerLeave={() => setHover("")} onDoubleClick={fit} />
			<div className="zoom">
				<button onClick={() => zoom(ZOOM_STEP)} title="Zoom in (+)" aria-label="Zoom in">
					+
				</button>
				<button onClick={() => zoom(1 / ZOOM_STEP)} title="Zoom out (−)" aria-label="Zoom out">
					−
				</button>
				<button onClick={fit} title="Fit the map (0, or double-click)" aria-label="Fit the map">
					⤢
				</button>
			</div>
			{busy ? <div className="badge top">Rendering…</div> : fetching ? <div className="badge top">Sharpening…</div> : null}
			<div className="foot">
				{hover !== "" ? <div className="badge">{hover}</div> : null}
				{scale.px > 0 ? (
					<div className="scalebox">
						{scale.label}
						<div className="scale" style={{ width: `${scale.px}px` }} />
					</div>
				) : null}
			</div>
			<ul className="legend">
				{LEGEND.map((l) => (
					<li key={l.label}>
						<span className={l.dot ? "swatch dot" : "swatch"} style={{ background: l.colour }} />
						{l.label}
					</li>
				))}
			</ul>
		</div>
	);
}
