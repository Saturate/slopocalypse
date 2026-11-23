// Glowsticks when things change under them (#447 after PR #538): Ana walks out with a lit
// stick, switches to her pistol and back with it lit (the new gun must stay out of her own
// stick's light, like the rifle), fires each, then dies with it lit. Dead, her stick should
// leave her body and lie glowing where she fell, in her own game and Bo's; back at the
// spawn she has none, and the dropped one still burns.
import { playtest, type Game, type Session, type Vec3 } from "../../../tools/lib/play.ts";

// GlowstickView: the holder on a carrier's chest, and a stick lying on the ground.
const STICK = "Glowstick";
const GROUND_VIEW = "/root/Boot/Modules/glowsticks/View";
// RenderLayers.FIRST_PERSON: your own arms and gun, which your own stick's light leaves out.
const FIRST_PERSON = 1 << 18;
// Bo looks this far left of Ana (radians), so the crosshair is not on what the shot is about.
const LOOK_PAST = 0.12;

const field = (o: unknown, key: string): unknown => (typeof o === "object" && o !== null ? Reflect.get(o, key) : undefined);

async function selfPath(g: Game): Promise<string> {
	const self = (await g.state()).players.find((p) => p.local);
	if (self === undefined) throw new Error(`${g.name}'s game has no local player`);
	return self.path;
}

// Sticks on the ground on the server, as [id, position] pairs.
async function groundSticks(s: Session): Promise<{ id: number; at: Vec3 }[]> {
	const ground = field(await s.server.call("glowsticks:server_state"), "ground");
	if (!Array.isArray(ground)) return [];
	return ground.map((g: unknown) => {
		const at = Array.isArray(g) ? g[1] : undefined;
		return { id: Array.isArray(g) ? Number(g[0]) : 0, at: Array.isArray(at) && at.length === 3 ? [Number(at[0]), Number(at[1]), Number(at[2])] : [0, 0, 0] };
	});
}

// In one game: the stick lights on a person (by their node path), and the ground sticks.
async function stickLights(g: Game, personPath: string): Promise<string[]> {
	return (await g.find(`${personPath}/*${STICK}*/Light`, "OmniLight3D", 5)).map((f) => f.path);
}
// Ground sticks are GlowstickView's own children; one re-laid in a new colour is added
// while the old is still queued for deletion, so it may not get the name "GroundGlowstick".
async function groundLights(g: Game): Promise<string[]> {
	return (await g.find(`${GROUND_VIEW}/*/Light`, "OmniLight3D", 10)).map((f) => f.path);
}

// Ana's own game: every mesh in her hands, and whether each is on the first-person layer only.
async function heldLayers(ana: Game, path: string): Promise<number[]> {
	const meshes = await ana.find(`${path}/Body/Skeleton/WeaponAttachment/*`, "GeometryInstance3D", 100);
	return Promise.all(meshes.map(async (m) => Number(await ana.node(m.path).get("layers"))));
}

export default playtest({ title: "Glowstick: switching guns with it lit, and dying with it lit", needs: ["glowsticks", "inventory", "daytime", "weapons"] }, async (t) => {
	// Soldiers off: one of theirs could show or drop a glowstick too, and a fight would spoil it.
	const s = await t.session({ clients: ["Ana", "Bo"], time: "night", args: ["--flags=enemies:off"] });
	const ana = s.client("Ana");
	const bo = s.client("Bo");
	const anaInfo = await s.player("Ana");
	const anaPath = anaInfo.path;

	await t.step("Ana walks out to 8 m in front of Bo", async () => {
		const home = await s.position("Bo");
		const bo0 = await s.onGround(home[0], home[2] + 4);
		await s.teleport("Bo", bo0);
		await s.teleport("Ana", await s.onGround(bo0[0] + 2, bo0[2] - 2));
		await s.walkTo("Ana", [bo0[0], bo0[1], bo0[2] - 8]);
		await s.lookAt("Bo", "Ana", { yawOffset: LOOK_PAST });
		await s.lookAt("Ana", "Bo");
	});

	await t.step("Ana cracks a glowstick", async () => {
		await s.give("Ana", "glowstick");
		await s.action("Ana", "glowstick");
		await t.expect
			.poll(() => s.server.call("glowsticks:lit_of", anaInfo.peerId), { what: "the server's lit stick for Ana" })
			.toSatisfy((v) => field(v, "shown") === true && Number(field(v, "left")) > 0, "to be shown and burning");
		if (!t.headless) await t.expect.poll(() => stickLights(bo, anaPath), { what: "the stick light on Ana in Bo's game", timeout: 10_000 }).toSatisfy((v) => v.length === 1, "to be one");
	});

	for (const [action, slot, gun] of [
		["weapon_2", 1, "pistol"],
		["weapon_1", 0, "rifle"],
	] as const) {
		await t.step(`Ana draws her ${gun} with the stick lit`, async () => {
			await s.action("Ana", action);
			await t.expect.poll(() => s.server.node(`${anaPath}/Intent`).get("weapon_slot"), { what: `the server's drawn slot for Ana` }).toBe(slot);
			const lit = await s.server.call("glowsticks:lit_of", anaInfo.peerId);
			t.expect(field(lit, "shown"), "the stick still out on the server after the switch").toBe(true);
			await t.expect.poll(() => ana.node(`${anaPath}/Head/Camera/Weapon_${slot === 1 ? "secondary" : "primary"}`).get("active"), { what: `Ana's own game: the ${gun} drawn` }).toBe(true);
			if (!t.headless) {
				// The gun model is rebuilt on a draw; each new mesh is moved to the layer a frame later.
				const layers = await t.expect.poll(() => heldLayers(ana, anaPath), { what: `the meshes of Ana's ${gun} in her own game`, timeout: 10_000 }).toSatisfy((v) => v.length > 0 && v.every((l) => l === FIRST_PERSON), "to be on the first-person layer only");
				t.note(`${layers.length} meshes in Ana's hands with the ${gun}`);
				const own = await stickLights(ana, anaPath);
				t.expect(own.length, "Ana's own stick light after the switch").toBe(1);
				const light = own[0];
				if (light !== undefined) t.expect(Number(await ana.node(light).get("light_cull_mask")) & FIRST_PERSON, "her own light still leaves her first-person layer out").toBe(0);
				const tint = await ana.find(`${anaPath}/*${STICK}*/ViewLight`, "OmniLight3D", 5);
				t.expect(tint.length, "the faint tint light on her gun").toBe(1);
				if (tint[0] !== undefined) t.expect(await ana.node(tint[0].path).get("visible"), "the tint light switched on").toBe(true);
			}
			// Into the ground a few metres ahead of her, away from Bo.
			const at = await s.position("Ana");
			const fired = await s.fire("Ana", [at[0] + 3, at[1], at[2] - 3], { shots: 2 });
			t.expect(fired, `rounds out of Ana's ${gun}`).toBeGreaterThan(1);
			await s.lookAt("Ana", "Bo");
			await ana.screenshot(`own-view-${gun}`, {
				expect: `Ana's own first-person view at night, looking toward another person (Bo) a few metres off. She holds a ${gun}${gun === "pistol" ? " (a small handgun)" : " (a long gun)"}; it is dark with at most a faint pale-blue tint, not lit up in strong flat blue. The ground just ahead has a soft blue light on it that fades over a few metres.`,
			});
		});
	}

	let fell: Vec3 = [0, 0, 0];
	await t.step("Ana dies with the stick lit", async () => {
		const full = await s.health("Ana");
		t.expect(full, "Ana's health before").toBeGreaterThan(0);
		fell = await s.position("Ana");
		// Eyes on the ground just ahead: a dead player's view stays as it was, and the stick
		// falls at her feet.
		await s.lookAt("Ana", [fell[0], fell[1], fell[2] + 0.7]);
		await s.kill("Ana");
		t.expect(await s.health("Ana"), "Ana's health after").toBe(0);
		t.expect(await s.server.call("glowsticks:lit_of", anaInfo.peerId), "Ana's lit stick on the server").toEqual({});
		const ground = await t.expect.poll(() => groundSticks(s), { what: "sticks on the ground on the server" }).toSatisfy((v) => v.length === 1, "to be one");
		const stick = ground[0];
		if (stick !== undefined) t.expect(Math.hypot(stick.at[0] - fell[0], stick.at[2] - fell[2]), "metres from where Ana fell to the dropped stick").toBeLessThan(1.5);
	});

	if (!t.headless) {
		await t.step("both games: the stick leaves her body and lies lit where she fell", async () => {
			for (const g of [bo, ana]) {
				await t.expect.poll(() => stickLights(g, anaPath), { what: `${g.name}'s game: a stick light on Ana's body`, timeout: 10_000 }).toEqual([]);
				const lights = await t.expect.poll(() => groundLights(g), { what: `${g.name}'s game: stick lights on the ground`, timeout: 10_000 }).toSatisfy((v) => v.length === 1, "to be one");
				if (lights[0] !== undefined) t.expect(await g.node(lights[0]).get("visible"), `${g.name}'s game: the ground stick's light switched on`).toBe(true);
				const onCorpse = await g.find(`*Corpse*${STICK}*`, "", 5);
				t.expect(onCorpse.length, `${g.name}'s game: glowstick nodes on Ana's ragdoll`).toBe(0);
			}
			t.expect((await ana.find(`${anaPath}/*${STICK}*/ViewLight`, "OmniLight3D", 5)).length, "Ana's game: the tint light for her own gun").toBe(0);
			// Before the respawn (respawn_seconds) takes her view away.
			await ana.screenshot("dead-ana-own-view", {
				expect: "Ana's own view just after she died at night, looking steeply down at the ground at her feet, with a death message over it. A small blue glowing stick lies on the ground in view, lighting the ground round it in blue. No gun in view.",
			});
			// The ragdoll falls from where she stood; a picture mid-fall shows a standing body.
			const corpse = (await bo.find("*Corpse*", "Node3D", 5))[0];
			t.expect(corpse !== undefined, "Bo's game: a ragdoll where Ana fell").toBe(true);
			if (corpse !== undefined) await t.expect.poll(() => bo.node(corpse.path).get("_settled"), { what: "Bo's game: Ana's ragdoll at rest", timeout: 10_000 }).toBe(true);
			const spot: Vec3 = [fell[0], fell[1] + 0.2, fell[2]];
			await s.lookAt("Bo", spot, { yawOffset: LOOK_PAST / 2 });
			await bo.screenshot("dead-ana-from-bo", {
				expect: "Bo's view at night, about 8 m off: a person's body lying on the ground a little right of the middle, and a small blue glowing stick lying on the ground next to it with a soft pool of blue light round it. Nothing glows on the body itself.",
			});
		});
	}

	await t.step("Ana comes back without it; the dropped one still burns", async () => {
		await s.server.waitFor("has Ana alive again", (st) => st.players.some((p) => p.playerName === "Ana" && !p.dead), 20_000);
		t.expect(await s.health("Ana"), "Ana's health after the respawn").toBeGreaterThan(0);
		t.expect(await s.server.call("glowsticks:lit_of", anaInfo.peerId), "Ana's lit stick on the server").toEqual({});
		t.expect((await groundSticks(s)).length, "sticks on the ground on the server").toBe(1);
		if (!t.headless) {
			t.expect(await stickLights(bo, anaPath), "Bo's game: a stick light on Ana").toEqual([]);
			t.expect((await groundLights(bo)).length, "Bo's game: stick lights on the ground").toBe(1);
		}
	});

	// A setting is per machine: colour-blind colours on Bo's game recolour the stick there only.
	if (!t.headless) {
		await t.step("Bo turns on colour-blind colours; only his game recolours the stick", async () => {
			const colour = async (g: Game): Promise<string> => {
				const light = (await groundLights(g))[0];
				return light === undefined ? "" : JSON.stringify(await g.node(light).get("light_color"));
			};
			await bo.setting("colour_blind", false);
			await ana.setting("colour_blind", false);
			const usual = await t.expect.poll(() => colour(bo), { what: "Bo's game: the ground stick's colour", timeout: 10_000 }).toSatisfy((v) => v !== "", "to be read");
			await t.expect.poll(() => colour(ana), { what: "Ana's game: the ground stick's colour", timeout: 10_000 }).toBe(usual);
			await bo.setting("colour_blind", true);
			const blind = await t.expect.poll(() => colour(bo), { what: "Bo's game: the ground stick's colour", timeout: 10_000 }).toSatisfy((v) => v !== "" && v !== usual, `to change from ${usual}`);
			t.note(`ground stick light colour: ${usual} usual, ${blind} colour-blind`);
			t.expect(await colour(ana), "Ana's game: the ground stick's colour").toBe(usual);
		});
	}
});
