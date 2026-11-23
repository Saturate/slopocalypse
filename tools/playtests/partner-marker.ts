// Co-op partner marker (#447, PR #526): Ana sees a blue marker with Bo's name and distance
// through a building when he is out of sight at range, and none when he stands close by.
import { playtest, type Game, type PlayContext, type Session, type Vec3 } from "../lib/play.ts";
import type { Region } from "../lib/png.ts";

// The marker's colour (modules/coop_marker/data/coop_marker.json "colour").
const MARKER = "#5fb6ff";

interface Marker {
	name: string;
	distance: number;
	inSight: boolean;
	alpha: number;
	// The alpha it is drawn with now; it eases towards `alpha`.
	shown: number;
	ahead: boolean;
	at: [number, number];
}

async function markerFor(ana: Game, who: string): Promise<Marker | undefined> {
	const items = await ana.call("coop_marker:markers");
	if (!Array.isArray(items)) return undefined;
	for (const raw of items) {
		if (typeof raw !== "object" || raw === null || Reflect.get(raw, "name") !== who) continue;
		const at = Reflect.get(raw, "at");
		return {
			name: who,
			distance: Number(Reflect.get(raw, "distance")),
			inSight: Reflect.get(raw, "in_sight") === true,
			alpha: Number(Reflect.get(raw, "alpha")),
			shown: Number(Reflect.get(raw, "shown") ?? 0),
			ahead: Reflect.get(raw, "ahead") === true,
			at: Array.isArray(at) ? [Number(at[0]), Number(at[1])] : [0, 0],
		};
	}
	return undefined;
}

// The marker once Ana's camera has stopped turning: where it is drawn moves until then.
async function settled(t: PlayContext, ana: Game): Promise<Marker | undefined> {
	let last: Marker | undefined;
	return t.expect
		.poll(
			async () => {
				const was = last;
				last = await markerFor(ana, "Bo");
				return last !== undefined && was !== undefined && Math.hypot(last.at[0] - was.at[0], last.at[1] - was.at[1]) < 2 ? last : undefined;
			},
			{ what: "the marker's place on screen", interval: 100 },
		)
		.toSatisfy((v) => v !== undefined, "to hold still");
}

// A box round a point the markers drew, as fractions of the picture. The game draws its 2D
// layer at a base size scaled to the window (stretch "canvas_items", aspect "expand": the
// short side fits, the long side shows more), so the point is in those units.
async function around(ana: Game, at: readonly [number, number], halfW: number, halfH: number): Promise<Region> {
	const pair = (v: unknown): [number, number] => (Array.isArray(v) ? [Number(v[0]), Number(v[1])] : [1, 1]);
	const [winW, winH] = pair(await ana.node("/root").get("size"));
	const [baseW, baseH] = pair(await ana.node("/root").get("content_scale_size"));
	const scale = baseW > 0 && baseH > 0 ? Math.min(winW / baseW, winH / baseH) : 1;
	const w = winW / scale;
	const h = winH / scale;
	return { x: at[0] / w - halfW, y: at[1] / h - halfH, w: halfW * 2, h: halfH * 2 };
}

// Bo moved to `at`: Ana's marker for him when her game says he is out of sight, else nothing.
async function hiddenAt(t: { s: Session; ana: Game }, at: Vec3): Promise<Marker | undefined> {
	await t.s.teleport("Bo", at);
	// Ana's copy of Bo must have moved there before her sight check means anything.
	await t.ana.waitFor("sees Bo at the new spot", (st) => st.players.some((p) => p.playerName === "Bo" && Math.hypot(p.at[0] - at[0], p.at[2] - at[2]) < 1.5), 10_000);
	const m = await markerFor(t.ana, "Bo");
	return m !== undefined && !m.inSight ? m : undefined;
}

export default playtest({ title: "Co-op partner marker: through a building at range, hidden up close", needs: ["coop_marker"] }, async (t) => {
	// Soldiers off: a firefight at the spawn would fill the frame and could kill either of them.
	const s = await t.session({ clients: ["Ana", "Bo"], start: "city", time: "day", args: ["--flags=enemies:off"] });
	const ana = s.client("Ana");
	const home = await s.position("Ana");

	await t.step("Bo out of sight behind a building, 30 to 60 m away", async () => {
		let hidden: Marker | undefined;
		search: for (const range of [35, 50, 60]) {
			for (let i = 0; i < 12; i++) {
				const angle = (i / 12) * Math.PI * 2;
				const spot: Vec3 = [home[0] + Math.sin(angle) * range, home[1] + 1.5, home[2] + Math.cos(angle) * range];
				// Out of sight here and 2 m to either side across Ana's line of sight: a building,
				// not a post or a tree trunk that only hides his chest from one spot.
				const side: Vec3 = [Math.cos(angle) * 2, 0, -Math.sin(angle) * 2];
				const tries: Vec3[] = [-1, 1, 0].map((k) => [spot[0] + side[0] * k, spot[1], spot[2] + side[2] * k]);
				let all = true;
				for (const at of tries) {
					const m = await hiddenAt({ s, ana }, at);
					if (m === undefined) {
						all = false;
						break;
					}
					hidden = m;
				}
				if (all) break search;
				hidden = undefined;
			}
		}
		t.expect(hidden, "a spot 35 to 60 m from Ana where a building hides Bo").toBeTruthy();
		await s.lookAt("Ana", "Bo");
		await t.expect.poll(() => markerFor(ana, "Bo"), { what: "Ana's marker for Bo" }).toSatisfy((v) => v !== undefined && v.ahead && !v.inSight, "to be ahead and out of sight");
		const m = await settled(t, ana);
		t.expect(m?.alpha, "the marker's strength out of sight").toBeGreaterThan(0.9);
		await t.expect.poll(async () => (await markerFor(ana, "Bo"))?.shown ?? 0, { what: "the drawn marker" }).toBeGreaterThan(0.85);
		const shot = await ana.screenshot("bo-behind-building", {
			expect: `Ana's view, daytime in a town. A small blue downward-pointing chevron near the middle of the picture, with "Bo" and a distance of about ${Math.round(m?.distance ?? 0)} m written above it in blue with a dark outline, drawn over a building or wall. Bo himself is not visible: something solid stands between the camera and him.`,
		});
		if (m !== undefined) shot.hasColour({ colour: MARKER, tolerance: 45, minPixels: 20, region: await around(ana, m.at, 0.08, 0.14), what: "marker blue at the marker's spot" });
	});

	await t.step("Bo close by in plain view: no marker", async () => {
		const eye = await s.position("Ana");
		const self = (await ana.state()).players.find((p) => p.local);
		const rotation = self !== undefined ? await ana.node(self.path).get("rotation") : undefined;
		const yaw = Array.isArray(rotation) ? Number(rotation[1]) : 0;
		// Three metres along Ana's facing (Godot's forward is -Z), inside hide_near_m (4 m).
		const spot: Vec3 = [eye[0] - Math.sin(yaw) * 3, eye[1] + 0.5, eye[2] - Math.cos(yaw) * 3];
		await s.teleport("Bo", spot);
		await ana.waitFor("sees Bo close by", (st) => st.players.some((p) => p.playerName === "Bo" && Math.hypot(p.at[0] - spot[0], p.at[2] - spot[2]) < 1.5), 10_000);
		await s.lookAt("Ana", "Bo");
		await t.expect.poll(() => markerFor(ana, "Bo"), { what: "Ana's marker for Bo" }).toSatisfy((v) => v !== undefined && v.inSight, "to be in sight");
		const m = await settled(t, ana);
		t.expect(m?.distance, "Bo's distance from Ana's eye").toBeLessThan(4.5);
		t.expect(m?.alpha, "the marker's strength up close").toBe(0);
		await t.expect.poll(async () => (await markerFor(ana, "Bo"))?.shown ?? 1, { what: "the drawn marker" }).toBeLessThan(0.02);
		const shot = await ana.screenshot("bo-close", {
			expect: "Ana's view, daytime in a town. Another player (Bo, a soldier-like figure with a sky-blue armband) stands about three metres in front of the camera, fully visible. There is no blue chevron marker, no name and no distance label over him.",
		});
		if (m !== undefined) shot.lacksColour({ colour: MARKER, tolerance: 20, maxPixels: 15, region: await around(ana, m.at, 0.08, 0.14), what: "no marker blue above Bo's head" });
	});
});
