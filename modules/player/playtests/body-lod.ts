// Other bodies posed less often far off or out of view (#365, PR #399, decision 0019): Bo
// watches Ana at 10, 25 and 60 m and with his back to her, and counts how often his game
// poses her body against how often it poses his own. Then at night Ana walks across with a
// lit glowstick and her armband, and dies 25 m off; her ragdoll must fall and come to rest.
import { parseVec3, playtest, sleep, type Game, type Session, type Vec3 } from "../../../tools/lib/play.ts";

// modules/player/data/body_lod.json: every frame within near_distance, then mid_rate, far_rate,
// off_screen_rate poses a second.
const BANDS = [
	{ metres: 10, what: "near, in view", rate: "every frame" },
	{ metres: 25, what: "mid, in view", rate: 30 },
	{ metres: 60, what: "far, in view", rate: 15 },
] as const;
const OFF_SCREEN_RATE = 10;
const COUNT_MS = 3000;

// Poses a second of `bodyPath`'s animator in game `g`, and of `g`'s own player over the same time.
async function poseRates(g: Game, bodyPath: string, ownPath: string): Promise<{ other: number; own: number }> {
	const read = async (): Promise<[number, number]> => [Number(await g.node(`${bodyPath}/BodyAnimator`).get("poses")), Number(await g.node(`${ownPath}/BodyAnimator`).get("poses"))];
	const [o0, s0] = await read();
	const t0 = Date.now();
	await sleep(COUNT_MS);
	const [o1, s1] = await read();
	const seconds = (Date.now() - t0) / 1000;
	return { other: (o1 - o0) / seconds, own: (s1 - s0) / seconds };
}

// Out through the camp's gate onto open ground: players spawn facing it (world.json camp).
const OUT_OF_CAMP = 30;

// `metres` along `ahead` from `from`, on the ground.
async function along(s: Session, from: Vec3, ahead: readonly [number, number], metres: number, side = 0): Promise<Vec3> {
	return s.onGround(from[0] + ahead[0] * metres - ahead[1] * side, from[2] + ahead[1] * metres + ahead[0] * side);
}

async function placeAnaAhead(s: Session, home: Vec3, ahead: readonly [number, number], metres: number): Promise<void> {
	await s.teleport("Ana", await along(s, home, ahead, metres));
	await s.lookAt("Bo", "Ana");
}

export default playtest({ title: "Body LOD: far and off-screen bodies posed less often, still whole", needs: ["glowsticks", "inventory", "daytime", "weapons"], screen: true }, async (t) => {
	const s = await t.session({ clients: ["Ana", "Bo"], time: "day", args: ["--flags=enemies:off"] });
	const bo = s.client("Bo");
	const ana = s.client("Ana");
	const anaPath = (await s.player("Ana")).path;
	const boPath = (await s.player("Bo")).path;
	const start = await s.position("Bo");
	// The body faces -Z: rotation.y is the yaw of the way the spawn points, toward the gate.
	const yaw = parseVec3(await s.server.node(boPath).get("rotation"))?.[1] ?? 0;
	const ahead = [-Math.sin(yaw), -Math.cos(yaw)] as const;
	const home = await along(s, start, ahead, OUT_OF_CAMP);
	await s.teleport("Bo", home);

	for (const band of BANDS) {
		await t.step(`Ana ${band.metres} m in front of Bo (${band.what})`, async () => {
			await placeAnaAhead(s, home, ahead, band.metres);
			const r = await poseRates(bo, anaPath, boPath);
			t.note(`Bo's game: Ana posed ${r.other.toFixed(1)} a second, Bo's own body ${r.own.toFixed(1)} (expected ${band.rate})`);
			if (band.rate === "every frame") t.expect(r.other, "Ana's poses a second against Bo's own").toBeGreaterThan(r.own * 0.9);
			else {
				// Never more often than the band allows (a frame of slack), and not stalled.
				t.expect(r.other, "Ana's poses a second").toBeLessThan(Math.min(band.rate, r.own) + 2);
				t.expect(r.other, "Ana's poses a second").toBeGreaterThan(Math.min(band.rate, r.own) * 0.6);
			}
		});
	}

	await t.step("Bo turns his back on Ana at 25 m", async () => {
		await placeAnaAhead(s, home, ahead, 25);
		const behind = await along(s, home, ahead, -20);
		await s.lookAt("Bo", [behind[0], behind[1] + 1.6, behind[2]]);
		const r = await poseRates(bo, anaPath, boPath);
		t.note(`Bo's game: Ana behind him posed ${r.other.toFixed(1)} a second, Bo's own ${r.own.toFixed(1)}`);
		t.expect(r.other, "Ana's poses a second out of view").toBeLessThan(OFF_SCREEN_RATE + 2);
		t.expect(r.other, "Ana's poses a second out of view").toBeGreaterThan(OFF_SCREEN_RATE * 0.6);
		const own = await poseRates(ana, anaPath, anaPath);
		t.expect(own.own, "Ana's own game: her body posed every frame").toBeGreaterThan(20);
	});

	await t.step("Bo's game: Ana wears her armband", async () => {
		t.expect(await bo.node(`${anaPath}/Body/Skeleton/Band`).exists(), "Ana's armband in Bo's game").toBe(true);
	});

	await t.step("night: Ana walks across 25 m off with a lit glowstick", async () => {
		await s.setTime("night");
		await s.give("Ana", "glowstick");
		await s.action("Ana", "glowstick");
		await t.expect.poll(async () => (await bo.find(`${anaPath}/*Glowstick*/Light`, "OmniLight3D", 5)).length, { what: "the stick light on Ana in Bo's game", timeout: 10_000 }).toBe(1);
		await s.teleport("Ana", await along(s, home, ahead, 25, 5));
		const mid = await along(s, home, ahead, 25);
		await s.lookAt("Bo", [mid[0], mid[1] + 1.2, mid[2]]);
		// Facing across Bo's view, to his left.
		await s.look("Ana", yaw + Math.PI / 2);
		await s.intent("Ana", { move: [0, 1] });
		await sleep(800);
		await bo.screenshot("ana-walking-25m-night", {
			expect: "Night, open ground. About 25 m ahead a person walks sideways across the view (legs apart mid-stride or passing), holding a gun, with a small glowing blue stick on the chest and a glow round it. The glow sits on the chest, not floating off the body or left behind.",
		});
		await sleep(700);
		await bo.screenshot("ana-walking-25m-night-2", {
			expect: "The same person a moment later, a little further along (to the left), still with the blue glow on the chest and a different leg position.",
		});
		await s.intent("Ana", { move: [0, 0] });
	});

	await t.step("Ana dies 25 m off; her ragdoll falls and comes to rest", async () => {
		await s.setTime("day");
		// A little past her, so his own gun does not cover where she falls.
		await s.lookAt("Bo", "Ana", { yawOffset: 0.15 });
		await s.kill("Ana");
		const corpse = await t.expect.poll(async () => (await bo.find("*Corpse*", "Node3D", 5))[0], { what: "Bo's game: a ragdoll of Ana", timeout: 10_000 }).toSatisfy((v) => v !== undefined, "to exist");
		if (corpse !== undefined) await t.expect.poll(() => bo.node(corpse.path).get("_settled"), { what: "Bo's game: Ana's ragdoll at rest", timeout: 15_000 }).toBe(true);
		await bo.screenshot("ana-ragdoll-25m", {
			expect: "Day, open ground. About 25 m ahead, a little right of the middle, a person's body lies on the ground (limbs on the ground, not standing or floating, not stretched or twisted apart).",
		});
	});
});
