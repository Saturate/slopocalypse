// Glowsticks at night (#447, PR #529): Ana is given a glowstick and cracks it; the server
// lights it, it leaves her gear, and Bo's game shows the stick and its light on her chest.
import { playtest, type Game, type Shot, type Vec3 } from "../lib/play.ts";
import type { Region } from "../lib/png.ts";

// GlowstickView names the holder on a carrier's chest "Glowstick", with the light inside it.
const STICK = "Glowstick";
// Bo looks this far left of Ana (radians), so the crosshair is not on her chest...
const LOOK_PAST = 0.12;
// ...which puts her right of the middle of his view, about here.
const AROUND_ANA: Region = { x: 0.5, y: 0.3, w: 0.25, h: 0.35 };

async function stickLights(bo: Game, anaPath: string): Promise<string[]> {
	const found = await bo.find(`${anaPath}/*${STICK}*/Light`, "OmniLight3D", 5);
	return found.map((f) => f.path);
}

export default playtest({ title: "Glowstick at night: Ana cracks one and Bo sees it", needs: ["glowsticks", "inventory", "daytime"] }, async (t) => {
	// Soldiers off: one of theirs could show a glowstick too, and a fight would spoil the view.
	const s = await t.session({ clients: ["Ana", "Bo"], time: "night", args: ["--flags=enemies:off"] });
	const ana = await s.player("Ana");
	const bo = s.client("Bo");

	await t.step("Ana stands 8 m in front of Bo in the dark", async () => {
		const at = await s.position("Bo");
		const spot: Vec3 = [at[0], at[1] + 1, at[2] - 8];
		await s.teleport("Ana", spot);
		await bo.waitFor("sees Ana there", (st) => st.players.some((p) => p.playerName === "Ana" && Math.hypot(p.at[0] - spot[0], p.at[2] - spot[2]) < 1.5));
		await s.lookAt("Bo", "Ana", { yawOffset: LOOK_PAST });
		await s.lookAt("Ana", "Bo");
	});

	let unlit: Shot | undefined;
	await t.step("before: no glowstick", async () => {
		if (!t.headless) t.expect(await stickLights(bo, ana.path), "glowstick lights on Ana in Bo's game").toEqual([]);
		unlit = await bo.screenshot("night-unlit", { expect: "Bo's view at night: dark, a person (Ana) a little right of the middle, about 8 m away, facing the camera, carrying no light. A small blue partner marker with her name may hang over her." });
	});

	await t.step("Ana gets a glowstick and cracks it", async () => {
		await s.give("Ana", "glowstick");
		t.expect(await s.count("Ana", "glowstick"), "glowsticks in Ana's gear").toBe(1);
		await s.action("Ana", "glowstick");
		await t.expect
			.poll(() => s.server.call("glowsticks:lit_of", ana.peerId), { what: "the server's lit stick for Ana" })
			.toSatisfy((v) => typeof v === "object" && v !== null && Reflect.get(v, "shown") === true && Number(Reflect.get(v, "left")) > 0, "to be shown and burning");
		t.expect(await s.count("Ana", "glowstick"), "glowsticks left in Ana's gear").toBe(0);
	});

	// A headless client draws nothing, so GlowstickView never starts there.
	if (t.headless) return;
	await t.step("Bo sees the lit stick on Ana's chest", async () => {
		const lights = await t.expect.poll(() => stickLights(bo, ana.path), { what: "glowstick lights on Ana in Bo's game", timeout: 10_000 }).toSatisfy((v) => v.length === 1, "to be one");
		const light = lights[0];
		if (light !== undefined) t.expect(await bo.node(light).get("visible"), "that light switched on (within the light budget)").toBe(true);
		const shot = await bo.screenshot("night-lit", {
			expect: "The same night view: the person right of the middle (Ana) now carries a small bright blue glowing stick on her chest, with a soft blue halo round it that stands out clearly against the dark. It does not light up the surroundings much.",
		});
		if (unlit !== undefined) {
			t.note(`mean brightness round Ana in Bo's view: ${unlit.luma(AROUND_ANA).toFixed(1)} unlit, ${shot.luma(AROUND_ANA).toFixed(1)} lit`);
			shot.brighterThan(unlit, { by: 60, minPixels: 12, region: AROUND_ANA, what: "the stick lights up pixels on Ana" });
		}
	});
});
