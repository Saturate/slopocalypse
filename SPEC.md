# Outpost: project spec for Claude Code

Working title: Outpost. A persistent open-world co-op shooter for 2 to 4 friends. Tarkov-style gear and risk, BattleBit-style low-poly 3D, a homemade modular car for travel, outposts as save points, and an emergent, rule-driven world.

How to use this file: save it in the project root as `SPEC.md`, put the "Conventions" and "Working agreement" sections into `CLAUDE.md`, then work through the phases one at a time using the kickoff prompts at the end. Do not ask for the whole game at once.

---

## 1. Vision

- Persistent open world, no extraction and no raid instances. The world keeps running and saves its state.
- You build a homemade car, drive out, explore and fight scavs, drones and robots, and loot gear under Tarkov-style risk.
- Outposts you claim along the way are save points, respawn points and stashes. They can be attacked and lost.
- A main base hosts NPC survivors who need supplies, run abstract missions on timers, and can die.
- Emergent play comes from a few simple interacting rules (noise, factions, heat, fuel), not scripted quests.
- Audience: the developer and friends. Fun and likeable matters more than polish. The repo is closed for now.

## 2. Prototype scope

In scope for the prototype:
- One small hand-built map, a few kilometres across (size to be tuned).
- Hitscan guns, a grid inventory, a modular car, outposts with save and respawn.
- Three enemy types: scav raider, scout drone, walker robot.
- A main base with fixed build slots and a handful of NPCs with simple jobs.
- Host-based co-op for 2 players, then 4.

Out of scope for now:
- Dedicated servers, PvP, anti-cheat, matchmaking.
- Procedural maps, multiple biomes, free-form base building, full ballistics.
- Runtime LLM features. Use LLMs offline for content text only.

## 3. Tech and conventions

Defaults chosen (change only after the Phase 0 spike says otherwise):
- Engine: Godot 4.x, one pinned stable version recorded in `CLAUDE.md`. Use Jolt physics if the pinned version supports it.
- Language: GDScript with static typing everywhere. Use C# only if the spike shows a clear need.
- Networking: Godot high-level multiplayer. One player hosts. The host is authoritative for all gameplay state. Clients send inputs and requests.
- Single-player is the same code path as co-op: a host with one local client. Do not write a separate offline path.
- Data-driven content: items, enemies, buildings, car parts, missions and tuning values live in JSON or resource files under `data/`. No magic numbers in gameplay code.
- Art: grey boxes and primitives first. Final models come later from a teammate. Agree an import convention (scale in metres, forward axis, pivot at base, one shared humanoid skeleton, naming `type_name_variant`).

Code conventions:
- Small, focused scenes and scripts. One responsibility per script.
- Global systems as autoloads: `EventBus`, `NoiseBus`, `WorldState`, `SaveSystem`, `Data` (loads the data files).
- Gameplay state changes go through host-side functions, never straight from UI or client code.
- Every system exposes a plain-data snapshot for saving and for network sync.
- Log with a simple categorised logger. No silent failures.

## 4. Repository layout

```
/project.godot
/CLAUDE.md          working agreement and commands
/SPEC.md            this file
/NOTES.md           running notes: feel feedback, decisions, known issues
/data/              items.json, enemies.json, car_parts.json, buildings.json, missions.json, tuning.json
/scenes/            world, player, car, enemies, outposts, ui
/scripts/           core (autoloads), player, car, ai, inventory, outposts, npcs, net
/tests/             automated tests and scenario scripts
/assets/            placeholder and final art, audio (with a LICENSES.md listing every source)
/tools/             helper scripts (headless test runner, screenshot capture)
```

## 5. Core systems

### 5.1 World and persistence
- One hand-built region with roads, 6 to 10 points of interest, a main base site and 3 to 5 outpost sites.
- World state saved by the host: claimed and destroyed outposts, cars (with their parts), cleared and rebuilt camps, loot state, NPC records, time of day.
- Versioned save format (`save_version` field), JSON on disk. Saves happen at outposts and on clean exit. Include a migration hook even if empty.

### 5.2 Player and guns
- First-person controller: walk, sprint, crouch, jump, lean optional later.
- Hitscan weapons with data-driven stats: damage, rate of fire, magazine, reload time, recoil pattern, spread, range.
- Procedural weapon motion (kick, sway, bob). Hit markers, impact effects, sound hooks.
- Start with 3 weapons: pistol, rifle, shotgun.

### 5.3 Inventory
- Tarkov-style grid with item rotation, containers (pockets, rig, backpack), a car boot and outpost stashes.
- Item definition in data: id, size (w, h), weight, stack rules, category, tags.
- Transfers between containers are host-validated. Weight affects stamina or speed (simple first version).
- Death: respawn at the last outpost. Carried gear stays on a corpse for a limited time and can be recovered. Make the rule tunable (all, half or none lost).

### 5.4 The car
Staged build system:
- Stage 1 (slots): a chassis with fixed sockets for engine, four wheels, four armour plates (front, back, left, right), a roof rack and a fuel tank. Each part in `car_parts.json` has mass, health, stats and a noise value.
- Stage 2 (snapped parts, later): parts snap to attach points or a grid.
- Physics: one rigid body with compound colliders. Mass and centre of mass are computed from the installed parts. Arcade-style handling. Wheels may use raycast or built-in vehicle wheels. No free-form joints in the prototype.
- Stats derived from parts: top speed, acceleration, handling, fuel use, noise, armour.
- Fuel is consumed while driving. Engine noise is emitted to `NoiseBus`.
- Damage removes or disables parts without new physics bodies. A car can be wrecked, abandoned or stolen.
- The boot is a mobile container.
- Co-op: one driver and up to three passengers. The driver's client simulates the car physics, and the host sanity-checks speed and position.
- A car saves as: chassis id, list of (socket, part id, health), fuel, position.

### 5.5 Outposts (save points)
- Claim a site with a build kit. A claimed outpost sets the respawn point, triggers a world save, and provides a small stash and workbench.
- Limit of active outposts (default 3, tunable).
- Upgrades via build slots: walls, a turret slot, an NPC guard.
- Heat: player activity near or from an outpost raises its heat. Higher heat attracts scav and machine attacks. Attacks can disable or destroy an outpost.

### 5.6 Main base and NPCs
- The main base is the largest outpost with fixed build slots (workbench, stash, medic bay, armoury, barracks, watchtower).
- NPCs are data records: name, skills, health, morale, needs (food, ammo, medicine, rest). No full 3D agents except a few idle figures later.
- Missions are abstract: pick a mission at a real point of interest, assign a crew and gear, wait a timer, roll an outcome from skill versus difficulty, with a chance of injury or death. Success can change the world (for example, clear a camp).
- Players can run the same mission in person for better outcomes.

### 5.7 Emergent layer
Keep these rules small and observable. Provide a debug overlay for them.
- `NoiseBus`: gunfire, engines and explosions emit noise events with position, loudness and type. Enemies react within range.
- Visibility: simple line-of-sight and light checks for detection.
- Factions: a relation table (scavs, machines, players). Machines and scavs can be hostile to each other.
- Loot respawns slowly. Camps rebuild over time.
- Random events: a drone sweep, a scav convoy. A simple event scheduler picks one now and then.
- Simulate AI only near players. Far camps are stored as data and ticked abstractly.

### 5.8 Enemies

| Enemy | Role | Reacts to | Notes |
| --- | --- | --- | --- |
| Scav raider | Human-like looter holding camps | Sight, gunfire, loot, nearby outposts | Patrol, investigate, engage, take cover, flee at low health |
| Scout drone | Spotting and alarm | Engine noise, light, movement | Flies a patrol path, alerts nearby enemies |
| Walker robot | Heavy ground unit | Alarm calls, noise | Slow, armoured, weak points, drops rare parts |

Use a behaviour tree or state machine per type, navmesh pathing, and a shared alert system. Keep AI deterministic and host-side.

---

## 6. Phases and acceptance criteria

Each phase is about 4 to 6 weeks at roughly 10 hours a week, less with more hours or help. Every phase ends in a playable build and a short note in `NOTES.md`.

**Phase 0: Spike and setup (a few days)**
- Project skeleton, folder layout, `CLAUDE.md`, a single command that runs all tests headlessly.
- A terrain chunk, a capsule player, a drivable box car, one hitscan gun, one dummy target.
- Host and join from a second local instance and see both players move.
- Done when: the tests run from one command, two instances can connect, and `NOTES.md` records how the car handled and how netcode felt in this engine, with a recommendation to continue or switch engines.

**Phase 1: Greybox world and shooting**
- A small terrain chunk with cover, a first-person controller, three weapons, one scav with patrol, shoot and flee behaviour.
- Done when: a scripted test can spawn a player and a scav, kill the scav and be killed, and the shooting is fun enough to repeat in a playtest.

**Phase 2: Homemade car (slot version)**
- Chassis, four wheels, four armour sockets, engine, fuel tank, boot container.
- Stats derived from parts, fuel use, engine noise to `NoiseBus`, part damage.
- Done when: swapping armour visibly changes handling and speed, running out of fuel stops the car, and a car round-trips through save and load.

**Phase 3: Loot, death and outposts**
- Grid inventory, stashes, corpse loot, outpost claiming, save and respawn.
- Done when: you can claim an outpost, die, respawn there, recover your gear from the corpse, quit and reload with the world intact.

**Phase 4: Emergent AI**
- Noise bus, visibility checks, faction table, drone and walker, camp respawn, heat and attacks on outposts, one random event.
- Done when: a loud engine pulls a drone, the drone alerts a camp, and in a playtest at least a few unscripted situations happen that you would tell friends about.

**Phase 5: Base and NPCs**
- Main base slots, NPC records and needs, timed missions at real map locations, world effects of success.
- Done when: an NPC can be sent on a mission, may die, and the outcome changes the map state, with all of it saved.

**Phase 6: Co-op**
- Harden host-authoritative sync: players, inventory, enemies, loot, outposts, and the car with driver-owned physics.
- Done when: 2 players, then 4, can drive together, fight, loot, claim an outpost and save, with no obvious desync across a 30 minute session.

**Phase 7: Friends-ready build**
- Art pass using the agreed import convention, audio pass, three enemy types polished, one tuned map, basic menus.
- Done when: friends ask to play again.

---

## 7. Testing and verification

- Pick one test framework (GUT or gdUnit4 are common choices for Godot) and wire it to a single headless command, for example `make test`.
- Unit tests: inventory rules, car stat computation, save and load round-trips, mission outcome rolls (with a fixed random seed).
- Scenario scripts: spawn player and enemy, fire shots, drive a fixed route, claim an outpost, save, reload, compare state.
- Screenshots: a tool script that renders a scene and saves a PNG so Claude can look at results.
- Network test: a script that starts a host and a client locally and checks key state matches after a scripted sequence.
- Never mark a phase done without running the tests and reporting the results.

## 8. Working agreement for Claude

- Work one phase at a time. Before coding, write a short plan and wait for approval.
- Make small commits with clear messages. Use a branch per feature.
- Keep values in `data/`, not in code. Keep systems modular and testable.
- Do not add features beyond the current phase. Put ideas in `NOTES.md` under "later".
- Record every asset source and licence in `assets/LICENSES.md`, including generated and paid assets.
- When something is uncertain (engine API, version differences), check the pinned version's documentation instead of guessing, and say so.
- After finishing a task, report: what changed, what was tested and how, what is still rough, and what to playtest.
- Ask before big architecture changes, before changing the save format, and before adding a dependency.

## 9. Defaults chosen and open questions

Defaults assumed in this spec (tell Claude if you want any of them changed):
- Godot 4 and GDScript, host-authoritative co-op, JSON saves, hitscan weapons, slot-based car building first.
- Respawn at the last outpost, with corpse loot recoverable for a limited time.
- A limit of 3 active outposts, plus one main base.

Open questions to settle during or after Phase 0:
- Godot or Unity, based on the spike.
- How harsh death should be (all, half or none of carried gear lost).
- Whether NPC deaths are permanent.
- How big the first map is, and whether the car can leave roads.
- Licence for code and assets if the repo is ever opened.

---

## 10. Kickoff prompts

**Prompt for Phase 0 (paste into Claude Code):**

> Read `SPEC.md` fully. We are starting Phase 0, the spike and setup. First write a short plan covering project skeleton, folder layout, `CLAUDE.md` (put sections 3 and 8 of the spec there, and pin the engine version you are using), a single headless test command, and the spike items: a terrain chunk with a capsule player, a drivable box car, one hitscan gun with a dummy target, and host and join between two local instances. Do not start coding until I approve the plan. When done, write findings in `NOTES.md` about car handling, netcode feel and anything in this engine that made the work harder than expected, and recommend whether to continue with this engine.

**Prompt for Phase 1 (after Phase 0 is approved):**

> We are starting Phase 1 from `SPEC.md`: greybox world and shooting. Use the existing data-driven setup and keep the host-authoritative structure from Phase 0. Plan first, then implement: a small terrain chunk with cover, a first-person controller, three weapons from `data/`, and one scav with patrol, investigate, engage and flee behaviour. Add tests that spawn a player and a scav, kill the scav, and be killed. Report what you built, how you tested it, what feels rough, and what I should playtest.
