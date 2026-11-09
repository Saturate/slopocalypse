# Slopocalypse

Persistent open-world shooter, solo or with friends: gear you can lose, low-poly voxel 3D, a homemade modular car, outposts as save points, a dedicated authoritative server. Built almost entirely by AI agents as an open experiment (see `README.md`).

## Pinned versions

- Godot 4.7.2-stable, Forward+, Jolt physics, 60 physics ticks per second. Never use a system Godot; `node tools/get-godot.ts` installs the pinned build into `tools/godot/` (git-ignored).
- Node.js 24 for tooling. TypeScript runs directly through Node's type stripping, so only erasable syntax: no `enum`, `namespace` or constructor parameter properties.
- Rust 1.95.0 (pinned in `rust-toolchain.toml`, MSVC on Windows) with godot-rust gdext `godot = 0.5.5`.

When an engine API detail is uncertain, check the Godot 4.7 docs or the installed engine instead of guessing, and say so. Models often produce Godot 3 syntax.

This file is for every coding agent (Codex, Cursor, Copilot, Gemini CLI, Claude Code, Aider and the rest) and for people. Two playbooks live in `.claude/skills/` (Claude Code loads them as skills; any other agent should just read them as Markdown):

- `.claude/skills/godot-conventions/SKILL.md`: read it before writing GDScript, scenes, builders, modules or gdext code. It holds the how-to and the silent-failure list.
- `.claude/skills/visual-review/SKILL.md`: after any visible change, capture, then have a fresh agent or subagent with no context judge the images without seeing the code. If your tool has no subagents, start a new session for the review, or ask a person.

Agent tooling note: in some agent shells on Windows (seen with Claude Code's Bash tool), backslashes inside Bash heredocs (including `python -` and `node -e`) get collapsed, turning `"\n"` into a real newline. Write code that contains backslashes with the Edit or Write tools, not through the shell.

## Commands

| What | Command |
| --- | --- |
| Install Godot | `node tools/get-godot.ts` (`--force` reinstalls) |
| Fast gate (while coding) | `npm run check` (TypeScript, tool tests, Godot import, parse check of changed scripts, unit tests) |
| Full gate (before every commit and merge) | `npm run check:full` (adds gate self-tests, all scripts, all test folders) |
| Tool tests only | `npm run test:tools` |
| First setup | `npm ci && node tools/get-godot.ts && node tools/get-addons.ts && node tools/get-changesetter.ts` (Rust via rustup; the toolchain file installs the pinned version) |
| Add a changeset | `tools/changesetter/changesetter add --package slopocalypse --bump patch -m "What changed, for players"` (`--bump none` for tooling, docs and tests; `minor` for new features) |
| Release | `gh workflow run release` (maintainer only: changesetter bumps `config/version` and writes `CHANGELOG.md` on a release branch, Windows and Linux build in parallel, then main moves to the release commit, it is tagged `vX.Y.Z`, the GitHub Release gets both zips and `ghcr.io/saturate/slopocalypse-server:X.Y.Z` and `:latest` are pushed; a failed build publishes nothing). Local fallback: `node tools/release.ts [--dry-run]` (Windows, Docker, `gh auth refresh -s write:packages`) |
| Build scenes | `node tools/build-scenes.ts` (runs `modules/*/builders/*.gd`; commit the `.tscn` output) |
| Capture for review | `node tools/capture.ts --setup res://modules/<id>/capture/<name>.gd --out screenshots/<name>.png --frames 120 --sheet 6` (opens a window; then follow `visual-review`) |
| Portable game zip | `node tools/export.ts [--connect HOST[:PORT],...]` (ships the addresses in the menu's server list; fetches export templates once, builds release, smoke-tests the exported game; output in `build/`) |
| Dedicated server | `node tools/server.ts [--port 7777]` (headless; clients join with `-- --connect=HOST:7777`; saves to `user://saves/world.db`, `-- --save=PATH` or `--no-save` to change that) |
| Deploy server to your Linux box | `node tools/deploy.ts --host user@server --zip <linux build> [--port 7777] [--open-firewall]` (installs a systemd service over ssh; `--ci` builds Linux on the `server-build` workflow instead; `--dry-run` prints the remote script) |
| Server Docker image | `docker build -t slopocalypse-server .` then `docker run -d -p 7777:7777/udp -v slopocalypse-data:/data slopocalypse-server` (builds the Linux export inside the container; save, logs and journals in the `/data` volume) |
| Server + two clients locally | `node tools/run-local.ts` |
| Voxel asset library | `node tools/library.ts` (or "Asset library" in the main menu): every voxel model the kit makes, with live parameters and the pixel filter |
| Build Rust extensions | `node tools/build-rust.ts` (`--release` for exports); the gate does this before Godot imports |
| Open editor | `tools/godot/Godot_v4.7.2-stable_win64.exe -e --path .` (Windows; other OSes use their binary in `tools/godot/`) |

CI: `.github/workflows/check.yml` runs the full gate on Linux, Windows and macOS for every pull request and push to main; the local `npm run check:full` stays the gate you run before pushing. `release.yml` and `server-build.yml` are manual: start them only when the maintainer asks.

Planned, added by their issues: `tools/journal` (#11), `tools/soak` (#15).

## Architecture rules

1. **Modules.** Each feature lives in `modules/<name>/` with its own scenes, scripts, data, tests and a `module.json` (`id`, `depends_on`, `flag`). Modules talk only through `EventBus` signals or a small public API script.
2. **Deletable.** Removing a module is deleting its folder and its flag. The gate boots the game with every optional module off.
3. **Feature flags.** `Features` reads `data/features.json`; a module with its flag off is never loaded. Flags can be overridden on the command line.
4. **Entities from components.** Scenes composed of small component nodes with values from data or `Resource` files. No ECS framework.
5. **Dedicated server decides, clients replay.** The server is a headless process of the same project with no player, camera, audio or UI. State changes run in `server_*` functions; clients send `request_*` RPCs. Every visible effect has a replay path to clients. Solo play starts a local server process; there is no offline code path. Client-only code lives in scripts the server never loads.
6. **Scenes from builders.** Entity, prefab and UI scenes come from `extends SceneTree` builder scripts that validate node counts before saving. Never hand-edit a generated `.tscn`. The world map is edited in the Godot editor.
7. **No magic numbers.** Gameplay values live in `data/` and are read through `Data`. `TWEAKING.md` maps them for players; an exported build reads `tweaks/<res path>` beside the executable first, so keep it up to date when adding a data file or field.
8. **Cross-platform.** Clients on Windows, macOS, Linux; server on Linux and Windows. Tooling is TypeScript on Node; engine-side helpers are GDScript launched by Node. Game code uses `res://` and `user://` paths only.
9. **Language split.** Rust for pure rules over data, anything that must match on server and client, hot paths, and logic that wants exhaustive tests (inventory, car stats, saves, mission rolls, faction/noise/heat rules, world ticking, server validation). GDScript for nodes, scenes, input, cameras, UI, audio, feel and module wiring. Rust is a pure crate (no `godot` dependency, `cargo test`) plus a thin gdext binding. When unsure, start in GDScript and move a rule to Rust once it settles.
10. **Rust stays deletable.** A module's crates live in `modules/<name>/rust/core` (pure, `cargo test`, `unsafe` denied) and `modules/<name>/rust/gd` (cdylib binding; crate-level `#![allow(unsafe_code)]` because gdext's entry is an `unsafe impl`). The module ships `<name>.gdextension` pointing at `bin/<os>/<profile>/`, which `tools/build-rust.ts` fills (git-ignored). Deleting the folder removes the Rust side too. `modules/example/` is the template.
11. **Server journals every event.** Requests (accepted or rejected with reason), state changes, replays, connects, disconnects and authority changes go through one event pipeline that writes an append-only NDJSON journal per session. An event type without a journal schema fails the gate.

## Core autoloads

| Autoload | Script | Use |
| --- | --- | --- |
| `Log` | `core/log.gd` | `Log.info(&"category", "message")`; `warn`, `error` push to the engine log. Tests that expect errors wrap them in `Log.begin_capture()` / `Log.end_capture()` and read them with `LogCapture.text()`. |
| `Data` | `core/data.gd` | `Data.load_json(path)` and `Data.require(path, dict, {field: TYPE_*})`. JSON numbers are always `TYPE_FLOAT`. |
| `Features` | `core/features.gd` | `Features.is_enabled(&"flag")`. Flags in `data/features.json`; per run `-- --flags=car:off` or `-- --all-optional-off`. |
| `Net` | `core/net.gd` | Session mode from the command line: `--server[=PORT]`, `--connect=HOST[:PORT]`, `--solo`; a windowed run with none of these (and no `--bot`/`--net-report-after`) shows the main menu (`core/main_menu.gd`). `Net.leave(reason)` returns to it. Clients say who they are on connect (`PlayerProfile`: name plus per-install key, `--name=` overrides); the server emits `peer_joined` only after that and `Net.identity_of(peer)` returns it; `peer_leaving` fires before `peer_left`, `stopping` before a server quits on its own, `Net.server_kick(peer, reason)` sends someone back to the menu. `Net.has_local_player()`, `Net.local_peer_id()`, `peer_joined` / `peer_left`. Server-spawned things go through a `MultiplayerSpawner` in their module. |
| `EventBus` | `core/event_bus.gd` | `subscribe(&"topic", handler)`, `publish(&"topic", payload)`. Topics are named `module.event`. |

Shared components live in `core/components/`: `HealthComponent` (`server_apply_damage`, `died` and `damaged` signals, `HealthComponent.find_on(collider)`).

A module is `modules/<id>/module.json` (`id`, `depends_on`, `flag`, `entry`) plus an entry script extending `Node`; `core/boot.gd` instances it under `/root/Boot/Modules/<id>`. An empty `flag` means always on. Use `modules/example/` as the template.

## Code style

- GDScript: static types everywhere; typed helpers (`absf`, `clampf`, `lerpf`, `maxi`) so `:=` infers. `snake_case` files and functions, `PascalCase` classes, `_private` members. One responsibility per script.
- TypeScript: strict, no casts (narrow instead), no `any`.
- Rust: `cargo fmt`, `clippy -D warnings`, no `unsafe` without asking.
- Comments explain why, never what.
- Never describe a system by naming another game ("Tarkov inventory", "DayZ hunger"), in code, comments, docs, issues or PRs. Models and people picture different things from a name. Say what the system is and specify it: the rules, numbers and behaviour (e.g. "grid inventory: items take a w x h block of cells, rotate 90 degrees, may not overlap"). When a request names a game, translate it into that kind of spec first and confirm it if the details are unclear.

## Workflow

- Work goes spec, then plan, then build in small vertical slices with tests first, then commit and PR. The maintainer drives this with personal Claude Code skills (see `CLAUDE.md`); with any other tool, follow the same steps.
- Specs and plans stay out of the repo; the issue holds what is agreed.
- GitHub issues are the live task list (milestone per phase). One branch per issue, named `issue-<n>-<slug>`; commits and PRs reference the issue.
- Every branch adds a changeset (`.changeset/*.md`, see Commands); the full gate fails without one. Write it for players, as one line of what they will notice ("Trees are cut where you shoot them"), not as a commit message. `none` for changes players never see. Never edit `config/version` or `CHANGELOG.md` by hand, and never run a release (`changesetter release`, `tools/release.ts` or the `release` workflow) unless the maintainer asks.
- Agents say who they are. Every issue, PR and comment an agent writes ends with a line `Made by: <model> in <tool>, <steered by a person | on its own>` (e.g. `Made by: Claude Opus 5.5 in Claude Code, steered by a person`). Add the `by:agent` label (`by:human` when a person wrote it) if you have access; outside contributors can't set labels, so the `Made by:` line is what counts. Use the model name you actually are; if you don't know it, say so instead of guessing. Commits keep the attribution trailer your tool adds; if it adds none, add `Assisted-by: <model> in <tool>`.
- The merge gate is `npm run check:full` run locally, then the `check` workflow green on the pull request; PRs are merged after both pass.
- Write a failing test first wherever behaviour is testable. Feel is checked by playtest and recorded in `NOTES.md`.
- Tool and test runs that start a server pass `--save=<temp file>` or `--no-save`, never the player's own world.
- Never trust a Godot exit code alone: headless runs can exit 0 after a script error, and gdUnit4 passes tests that only `push_error`. The gate scans logs and fails on any `ERROR:`, `Error:` or `SCRIPT ERROR` line not allow-listed in `tools/lib/gate.ts`.
- GDScript tests live in `tests/unit`, `tests/scenario`, `tests/net` (and the same under each module). The fast gate runs only `unit` folders. Godot does not deliver input events headless, so tests drive intent components, never simulated key presses.
- Ask before: adding any dependency (npm, Cargo, Godot addon), changing architecture rules or the module layout, changing the save or journal format, `unsafe` Rust.
- Do not add features beyond the current issue; put ideas in `NOTES.md` under "Later".
- Record every third-party asset and vendored code in `assets/LICENSES.md`. The project is AGPL-3.0-or-later (`LICENSE`), so only bring in code and assets under licences compatible with it (MIT, BSD, Apache-2.0, MPL-2.0, Zlib, CC0, CC BY, CC BY-SA); ask before anything else. Contributions come in under `CLA.md`, and the name is covered by `TRADEMARKS.md`.
- After a task, report what changed, how it was tested, what is rough, and what to playtest.
