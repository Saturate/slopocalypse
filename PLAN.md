# Outpost: plan

Companion to `SPEC.md`. The spec says *what*; this file says *in what order, with which decisions, and what could go wrong*. Phases 1–7 are a roadmap only — each gets a detailed plan (approved before coding) when it starts, informed by what the previous phase taught us.

## Decisions so far

| Decision | Choice | Why / notes |
| --- | --- | --- |
| Engine | Godot **4.7.2** stable (18 Aug 2026), portable in `tools/godot/` (git-ignored, self-contained mode) | Pinned so everyone runs the same build. Unity only if the Phase 0 spike fails badly. |
| Physics | Jolt (built in, default for new 4.x projects) | Check `VehicleBody3D` works well on Jolt in the spike; docs don't cover it. |
| Language | GDScript, static typing everywhere | C# only if the spike shows a clear need. |
| Tests | GUT **9.7.x** (supports 4.7), vendored in `addons/gut/` | Pure-GDScript project. Godot headless can exit 0 on failure, so the runner parses output too. |
| Test command | `tools/test.ps1` (PowerShell) | No `make` on Windows. |
| Repo | Private GitHub repo, git LFS for binary assets | Watch the LFS storage/bandwidth quota once real art lands. |
| Platform | Windows first | Scripts are PowerShell; keep Linux in mind for later CI. |
| Online play | Tailscale (or ZeroTier) virtual LAN for the prototype | Host-based ENet needs an open port; a VPN avoids port forwarding. Keep transport behind one `Net` module so GodotSteam/relay can replace it later. |

Still open (from the spec, §9): death harshness, permanent NPC death, map size and off-road driving, code/asset licence.

## Roadmap

| Phase | Goal | Key risk to watch | Decide before starting |
| --- | --- | --- | --- |
| 0 Spike | Skeleton, tests, terrain + capsule + box car + gun, host/join | Car feel on Jolt; netcode ergonomics | — |
| 1 Greybox + shooting | Fun gunplay vs one scav | Navmesh on large terrain; hit-reg under host authority | Terrain approach (heightmap mesh vs Terrain3D plugin) |
| 2 Car (slots) | Part-based car, fuel, noise, damage, save | Compound collider + CoM changes destabilising handling | Wheel model (built-in vs raycast), from spike notes |
| 3 Loot / death / outposts | Grid inventory, corpse, claim, respawn, save/load | Save format growing ad hoc | Save schema v1; death rule default |
| 4 Emergent AI | Noise, visibility, factions, drone, walker, heat, events | Perf of AI near players; abstract ticking of far camps | Sim radius; event scheduler shape |
| 5 Base + NPCs | NPC records, needs, timed missions with world effects | Balancing; offline-time handling on load | Permanent NPC death? |
| 6 Co-op hardening | 2 then 4 players, 30 min no desync | Driver-owned car + passengers; late join; inventory races | Online transport (stay on Tailscale or move to Steam/relay) |
| 7 Friends-ready | Art, audio, menus, tuned map | Asset import consistency | Import convention sign-off with art teammate |

Note: co-op is not "added" in Phase 6. Every phase uses the host-authoritative path from day one (single-player = host + one local client); Phase 6 is about hardening and scale.

## Phase 0: detailed plan (awaiting approval)

Goal: answer "is Godot right for this?" cheaply, and leave a skeleton every later phase builds on.

1. **Repo and project setup**
   - `project.godot` (Forward+ renderer, Jolt), folder layout from SPEC §4.
   - `CLAUDE.md`: SPEC §3 and §8, pinned engine version, commands (`tools/test.ps1`, `tools/run_two.ps1`, `tools/screenshot.ps1`).
   - `NOTES.md` (feel feedback, decisions, known issues, "later"), `assets/LICENSES.md`.
   - `tools/get-godot.ps1`: downloads and SHA512-verifies the pinned Godot into `tools/godot/`, so friends/teammates can bootstrap.
2. **Core autoloads**
   - `Log` (categorised, levels, no silent failures), `EventBus`, `Data` (loads `data/*.json`, validates required fields, fails loudly).
   - Empty stubs with snapshot/restore signatures: `NoiseBus`, `WorldState`, `SaveSystem`.
   - `data/tuning.json` and `data/items.json` with just what the spike needs (player speeds, one rifle, car tuning).
3. **Headless tests**
   - Vendor GUT 9.7.x (record licence in `assets/LICENSES.md` / third-party list).
   - `tools/test.ps1`: run `--import` once, then GUT headless; parse the summary; non-zero exit on any failure, parse error or missing summary.
   - First tests: smoke test, `Data` loads and rejects bad JSON, weapon stat lookup.
4. **Spike scene**
   - Terrain chunk (~256 m, heightmap mesh + `HeightMapShape3D`), a few boxes for cover.
   - Capsule first-person controller (walk, sprint, crouch, jump), values from `tuning.json`.
   - Box car on `VehicleBody3D` + 4 `VehicleWheel3D`; enter/exit; if handling is poor, try a quick raycast-wheel variant and compare.
   - One hitscan rifle (damage, RoF, mag, reload, spread from data), a dummy target with health and a hit marker.
5. **Networking**
   - Main menu: Host / Join (IP field, default 127.0.0.1). ENet behind a small `Net` module.
   - `MultiplayerSpawner` for players; `MultiplayerSynchronizer` for transforms.
   - Client sends fire *requests*; host raycasts and applies damage (host-authoritative).
   - Car: driver's peer gets multiplayer authority while driving; host does a basic speed/position sanity check.
   - `tools/run_two.ps1` launches host + client windows side by side.
   - Automated net test: headless host + client, client moves and shoots the dummy, both report the same dummy health and player position (within tolerance).
6. **Screenshot tool** — `tools/screenshot.ps1 <scene> <out.png>` renders a scene and saves a PNG for review.
7. **Findings** — `NOTES.md`: car handling, netcode feel, anything harder than expected, and a continue/switch recommendation.

**Done when:** `tools/test.ps1` passes from a clean clone, two instances connect and see each other move and shoot, and the `NOTES.md` findings are written. Then you playtest it.

**Branching:** `main` holds approved work; Phase 0 goes on `phase-0/spike` with small commits, merged via PR.

**Not in Phase 0:** inventory, AI, saves, real car parts, art, internet play testing (LAN/localhost only).
