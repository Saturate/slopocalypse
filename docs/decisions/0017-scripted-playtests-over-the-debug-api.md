# 0017. Scripted playtests drive real sessions over the debug API

Status: accepted
Date: 2026-11-22
Issue or PR: play-runner PR (slice 1)

## Context
Agents playtest until a person picks the game up, and every playtest agent hand-rolled its
own session: start a server, start clients, find their debug APIs, poke them, kill them. Waits
counted frames, which is what made tests flaky this week. Capture setups (`tools/capture.ts`)
build a staged scene, not the real game with a server and clients. We want scenarios as code
that run the real thing, check game state, and take screenshots a reviewer judges blind.

## Decision
- `node tools/play.ts <scenario>` runs `tools/playtests/<scenario>.ts`. A scenario is
  `export default playtest({ title, needs }, async (t) => ...)` and opens one session: a
  headless dedicated server with `--no-save` and named windowed clients, each with
  `--debug-api` and its own `--log-file`. A process's debug API file is matched by that log
  path, not by pid (on Windows the console launcher's pid is not the game's).
- Clients run with `--bot=playtest`, a bot name no module drives: no keyboard or mouse input is
  added, the mouse is never captured, and the run owns the player's intent. Helpers act on the
  server, which decides everything anyway: intents and one-shot actions are set on the
  server's `PlayerIntent`, look is `remote_look` with absolute yaw and pitch, teleports use the
  player module's `server_move_to`, time uses `daytime:server_set_hour`, items
  `inventory:server_give`. Each then waits until the server and the affected windows show it.
- Every wait is on the wall clock (`expect.poll`, `waitFor`), never on frames.
- Screenshots wait until the world is loaded and the terrain round the viewer is built, then go
  into `build/play/<scenario>/<time>/shots/` with the expectation text. `review.md` holds only
  the pictures and expectations, which is the hand-off to a reviewer that has not seen code or
  state checks. Cheap image checks (a colour in a region, pixels that got brighter between two
  shots) decode the PNG with a small hand-written decoder on `node:zlib`; no dependency.
- A run fails on a failed check, a failed image check, a thrown error, or any error line in any
  process's output (the gate's scan, plus a per-scenario allow-list).
- The debug API gains `get` (any property, script variables too, as text and plain JSON) and
  `call`, which reaches only the methods in `DebugHandler.CALLS`, written as
  `<node under /root/Boot/Modules>:<method>`. A NodePath argument is handed over as the node.
- Scenarios live in `tools/playtests/`, not in modules: they span modules, the TypeScript check
  already covers `tools/`, and the module layout stays as it is. A scenario declares the modules
  it is about (`needs`); with one switched off the run is skipped, not failed.

## Alternatives
- Arbitrary method calls or script eval through the debug API. Rejected: `call` on any node
  would reach `OS`, file and network methods through any object, and eval is code execution.
  The API is local (127.0.0.1), off unless `--debug-api` is given and token-protected, but an
  allow-list keeps what a playtest can do reviewable in one constant. Adding a method is a code
  change that a reviewer sees. Note that `set` (and now `call` arguments) parse values with
  `str_to_var`, which can build engine objects and load project resources; that was already
  true of `set` and is acceptable for a local, opt-in, token-protected tool.
- Simulated key presses (`Input.action_press`). Rejected: it needs the window focused and the
  mouse captured, which fights whoever sits at the machine, and headless runs ignore input.
- Driving intents on the client and letting it send them. Rejected: the client's own input
  script overwrites them every tick, and the server is the authority anyway.
- Per-module `playtests/` folders (deleted with their module). Would need a change to the module
  layout rules and the TypeScript project; open for the maintainer to decide.
- A playtest in the full gate. A headless run of `glowstick-night` takes about 7 s locally on a
  warm cache, but it starts three Godot processes on a shared port band and adds no check the
  module's scenario tests lack; not added yet.

## Consequences
- New helpers need either a property, an event, or an entry in `CALLS`; the last is the
  question to ask in review.
- Windowed runs open windows on the developer's screen and are not in the gate; they are for
  agents playtesting a change and for the reviewer hand-off.
- Revisit when scenarios need things the server alone cannot do (opening a UI screen, client
  settings), or when a headless scenario earns a place in the gate.
