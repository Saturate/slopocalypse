// Glowsticks at night (#447, PR #529): Ana is given a glowstick and cracks it; the server
// lights it, it leaves her gear, and Bo's game shows the stick and its light on her chest.
// Her own view leaves her gun out of her stick's light; Bo still sees her lit from 30 m; a
// stick she drops lies on the ground as a stick.
import { playtest, type Game, type Shot, type Vec3 } from "../../../tools/lib/play.ts";
import type { Region } from "../../../tools/lib/png.ts";

// GlowstickView names the holder on a carrier's chest "Glowstick", with the light inside it.
const STICK = "Glowstick";
// Bo looks this far left of Ana (radians), so the crosshair is not on her chest...
const LOOK_PAST = 0.12;
// ...which puts her right of the middle of his view, about here.
const AROUND_ANA: Region = { x: 0.5, y: 0.3, w: 0.25, h: 0.35 };
// RenderLayers.FIRST_PERSON: your own arms and gun, which your own stick's light leaves out.
const FIRST_PERSON = 1 << 18;

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

	await t.step("Ana's own stick leaves her gun out of its light", async () => {
		const own = s.client("Ana");
		const self = (await own.state()).players.find((x) => x.local);
		if (self === undefined) throw new Error("Ana's game has no local player");
		const lights = await t.expect.poll(() => own.find(`${self.path}/*${STICK}*/Light`, "OmniLight3D", 5), { what: "Ana's own stick light in her game", timeout: 10_000 }).toSatisfy((v) => v.length === 1, "to be one");
		const light = lights[0];
		if (light !== undefined) t.expect(Number(await own.node(light.path).get("light_cull_mask")) & FIRST_PERSON, "her own light on her first-person layer").toBe(0);
		t.expect((await own.find(`${self.path}/*${STICK}*/ViewLight`, "OmniLight3D", 5)).length, "faint tint lights on her own gun").toBe(1);
		// Away from the mission board she stood against, on open ground 4 m from Bo.
		const at = await s.position("Bo");
		await s.teleport("Ana", [at[0], at[1] + 1, at[2] - 4]);
		await s.lookAt("Ana", [at[0], at[1], at[2]]);
		await own.screenshot("night-own-view", {
			expect: "Ana's own first-person view at night, looking a little down toward Bo: her rifle at the hip is dark with at most a faint blue tint, not flooded in flat blue; the ground just ahead of her has a soft blue light on it that fades over a few metres.",
		});
	});

	await t.step("Bo sees Ana lit from 30 m", async () => {
		const ana = await s.position("Ana");
		await s.teleport("Bo", [ana[0], ana[1] + 1, ana[2] + 30]);
		await s.lookAt("Bo", "Ana", { yawOffset: LOOK_PAST / 4 });
		await bo.screenshot("night-lit-30m", { expect: "Night, open ground: about 30 m off, a little right of the middle, a small bright blue light on a person's chest stands out clearly against the dark." });
	});

	await t.step("Ana drops it and it lies on the ground as a stick", async () => {
		await s.action("Ana", "glowstick_drop");
		await t.expect
			.poll(async () => {
				const st = await s.server.call("glowsticks:server_state");
				const ground: unknown = typeof st === "object" && st !== null ? Reflect.get(st, "ground") : undefined;
				return Array.isArray(ground) ? ground.length : 0;
			}, { what: "sticks on the ground on the server" })
			.toBe(1);
		const ana = await s.position("Ana");
		await s.teleport("Ana", [ana[0] + 20, ana[1] + 1, ana[2]]);
		await s.teleport("Bo", [ana[0], ana[1] + 1, ana[2] + 4]);
		await s.lookAt("Bo", [ana[0], ana[1], ana[2]]);
		await bo.screenshot("night-dropped-stick", { expect: "Night, looking down at the ground a few metres ahead: a small blue glowing stick lies on the ground with a soft blue glow and a pool of blue light round it; the stick's shape is clear, not just a round blob." });
	});
});
