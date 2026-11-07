# Outpost

Persistent open-world co-op shooter for 2 to 4 friends: Tarkov-style gear and risk, low-poly 3D, a homemade modular car, outposts as save points, a dedicated authoritative server.

## Pinned versions

- Godot 4.7.2-stable, Forward+, Jolt physics, 60 physics ticks per second. Never use a system Godot; `node tools/get-godot.ts` installs the pinned build into `tools/godot/` (git-ignored).
- Node.js 24 for tooling. TypeScript runs directly through Node's type stripping, so only erasable syntax: no `enum`, `namespace` or constructor parameter properties.
- Rust 1.95.0 (pinned in `rust-toolchain.toml`, MSVC on Windows) with godot-rust gdext `godot = 0.5.5`.

When an engine API detail is uncertain, check the Godot 4.7 docs or the installed engine instead of guessing, and say so. Models often produce Godot 3 syntax.

Load the `godot-conventions` project skill (`.claude/skills/godot-conventions/`) before writing GDScript, scenes, builders, modules or gdext code. It holds the how-to and the silent-failure list. After any visible change, use the `visual-review` skill: capture, then a fresh subagent judges the images without seeing the code.

Agent tooling note: in this environment, backslashes inside Bash heredocs (including `python -` and `node -e`) get collapsed, turning `"\n"` into a real newline. Write code that contains backslashes with the Edit or Write tools, not through the shell.

## Commands

| What | Command |
| --- | --- |
| Install Godot | `node tools/get-godot.ts` (`--force` reinstalls) |
| Fast gate (while coding) | `npm run check` (TypeScript, tool tests, Godot import, parse check of changed scripts, unit tests) |
| Full gate (before every commit and merge) | `npm run check:full` (adds gate self-tests, all scripts, all test folders) |
| Tool tests only | `npm run test:tools` |
| First setup | `npm ci && node tools/get-godot.ts && node tools/get-addons.ts` (Rust via rustup; the toolchain file installs the pinned version) |
| Build scenes | `node tools/build-scenes.ts` (runs `modules/*/builders/*.gd`; commit the `.tscn` output) |
| Capture for review | `node tools/capture.ts --setup res://modules/<id>/capture/<name>.gd --out screenshots/<name>.png --frames 120 --sheet 6` (opens a window; then use the `visual-review` skill) |
| Portable game zip | `node tools/export.ts [--connect HOST[:PORT]]` (fetches export templates once, builds release, smoke-tests the exported game; output in `build/`) |
| Dedicated server | `node tools/server.ts [--port 7777]` (headless; clients join with `-- --connect=HOST:7777`) |
| Server + two clients locally | `node tools/run-local.ts` |
| Build Rust extensions | `node tools/build-rust.ts` (`--release` for exports); the gate does this before Godot imports |
| Open editor | `tools/godot/Godot_v4.7.2-stable_win64.exe -e --path .` (Windows; other OSes use their binary in `tools/godot/`) |

CI (`.github/workflows/check.yml`) is manual-only for now to save Actions minutes: `gh workflow run check`.

Planned, added by their issues: `tools/journal` (#11), `tools/soak` (#15).

## Architecture rules

1. **Modules.** Each feature lives in `modules/<name>/` with its own scenes, scripts, data, tests and a `module.json` (`id`, `depends_on`, `flag`). Modules talk only through `EventBus` signals or a small public API script.
2. **Deletable.** Removing a module is deleting its folder and its flag. The gate boots the game with every optional module off.
3. **Feature flags.** `Features` reads `data/features.json`; a module with its flag off is never loaded. Flags can be overridden on the command line.
4. **Entities from components.** Scenes composed of small component nodes with values from data or `Resource` files. No ECS framework.
5. **Dedicated server decides, clients replay.** The server is a headless process of the same project with no player, camera, audio or UI. State changes run in `server_*` functions; clients send `request_*` RPCs. Every visible effect has a replay path to clients. Solo play starts a local server process; there is no offline code path. Client-only code lives in scripts the server never loads.
6. **Scenes from builders.** Entity, prefab and UI scenes come from `extends SceneTree` builder scripts that validate node counts before saving. Never hand-edit a generated `.tscn`. The world map is edited in the Godot editor.
7. **No magic numbers.** Gameplay values live in `data/` and are read through `Data`.
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
| `Net` | `core/net.gd` | Session mode from the command line: `--server[=PORT]`, `--connect=HOST[:PORT]`, or solo. `Net.has_local_player()`, `Net.local_peer_id()`, `peer_joined` / `peer_left`. Server-spawned things go through a `MultiplayerSpawner` in their module. |
| `EventBus` | `core/event_bus.gd` | `subscribe(&"topic", handler)`, `publish(&"topic", payload)`. Topics are named `module.event`. |

Shared components live in `core/components/`: `HealthComponent` (`server_apply_damage`, `died` and `damaged` signals, `HealthComponent.find_on(collider)`).

A module is `modules/<id>/module.json` (`id`, `depends_on`, `flag`, `entry`) plus an entry script extending `Node`; `core/boot.gd` instances it under `/root/Boot/Modules/<id>`. An empty `flag` means always on. Use `modules/example/` as the template.

## Code style

- GDScript: static types everywhere; typed helpers (`absf`, `clampf`, `lerpf`, `maxi`) so `:=` infers. `snake_case` files and functions, `PascalCase` classes, `_private` members. One responsibility per script.
- TypeScript: strict, no casts (narrow instead), no `any`.
- Rust: `cargo fmt`, `clippy -D warnings`, no `unsafe` without asking.
- Comments explain why, never what.

## Workflow

- Work follows the Saturate/agents skills: `/spec`, `/plan`, `/build` (incremental-implementation plus tdd), `commit`, `make-pr`, `evaluating-dependencies`.
- Specs and plans live in `~/.claude/specs/outpost/`, never in the repo. The game design doc is `~/.claude/specs/outpost/DESIGN.md`.
- GitHub issues are the live task list (milestone per phase). One branch per issue, named `issue-<n>-<slug>`; commits and PRs reference the issue.
- The merge gate is `npm run check:full` run locally; PRs are merged after it passes.
- Write a failing test first wherever behaviour is testable. Feel is checked by playtest and recorded in `NOTES.md`.
- Never trust a Godot exit code alone: headless runs can exit 0 after a script error, and gdUnit4 passes tests that only `push_error`. The gate scans logs and fails on any `ERROR:`, `Error:` or `SCRIPT ERROR` line not allow-listed in `tools/lib/gate.ts`.
- GDScript tests live in `tests/unit`, `tests/scenario`, `tests/net` (and the same under each module). The fast gate runs only `unit` folders. Godot does not deliver input events headless, so tests drive intent components, never simulated key presses.
- Ask before: adding any dependency (npm, Cargo, Godot addon), changing architecture rules or the module layout, changing the save or journal format, `unsafe` Rust.
- Do not add features beyond the current issue; put ideas in `NOTES.md` under "Later".
- Record every third-party asset and vendored code in `assets/LICENSES.md`.
- After a task, report what changed, how it was tested, what is rough, and what to playtest.
