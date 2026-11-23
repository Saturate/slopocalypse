# 0019. A module owns everything that names it

Status: accepted
Date: 2026-11-23
Issue or PR: module-ownership PR

## Context
Architecture rule 2 says removing a module is deleting its folder and its flag. Three places
broke that: playtest scenarios lived in `tools/playtests/` (0017 left per-module folders open
for the maintainer), the debug API kept a central `CALLS` list of other modules' methods
(`"glowsticks:server_state"`, `"car:occupied_seats"`), and `core/settings.gd` and
`core/ui/settings_screen.gd` spelled out module settings (`blood`, `compass`, `coop_marker`,
`colour_blind`) with a `Features.is_enabled` check each. Deleting `coop_marker` left a
scenario that could not run, an allow-list entry for a module that was gone, and core code
naming it. The maintainer approved the rule "a module owns everything that names it" on
2026-11-23.

## Decision
- **Playtests** live in `modules/<id>/playtests/<name>.ts`, in the module the scenario is
  about (`glowstick-night` and `glowstick-death` in `glowsticks`, `partner-marker` in
  `coop_marker`). `node tools/play.ts <name>` finds them across `modules/*/playtests/`
  (folders with a `module.json` only); a name used by two modules is an error, not a silent
  pick. Shared helpers stay in `tools/lib/play.ts`. `tsconfig.json` includes
  `modules/*/playtests/**/*.ts`, so the TypeScript check covers them.
- **Debug calls**: a module lists the methods on its entry node that the debug API's `call`
  may run, as `"debug_calls": ["lit_of", "server_state"]` in its `module.json`. The API
  reaches them as `<id>:<method>`. `DebugHandler` builds its allow-list from the manifests of
  the modules present; a module that is present but not loaded still answers "not loaded
  here". `server_*` calls stay refused on clients, and arguments still go through
  `str_to_var` with the result returned as plain JSON.
- **Player settings**: a module registers the settings it reads in its `module.json`:
  `"settings": [{"key": "compass", "type": "bool", "default": true, "label": "Compass",
  "order": 20}]`. `type` is `bool` for now (`ModuleLoader.SETTING_TYPES`); `order` places
  the row in the settings screen's toggle list under Fullscreen. `ModuleLoader` checks both
  fields when it reads a manifest, and a bad entry stops the module loading with an error.
  `Settings` reads the registrations from the manifests on first use, so the title's
  settings screen has them before any module loads. Core keeps only engine-wide settings
  (mouse, field of view, volume, fullscreen, UI scale, keys). A key core or another module
  already owns is an error.
- The settings screen builds one toggle per registered setting whose module's flag is on
  (`Settings.offered()`). A module that is off, or deleted, shows no row. A value in
  `settings.cfg` that no present module registers is kept and written back unchanged, so the
  file format is the same and putting a module back finds the player's choice. A value of
  the wrong type falls back to the default.
- The debug API's `setting` method takes exactly the settings the screen offers, checks the
  value's type against the registration and never saves.
- A tool test (`tools/lib/ownership.test.ts`, in the fast gate) fails when a playtest
  scenario sits outside `modules/<id>/playtests/`, a `.gd` file outside a module names one of
  that module's debug calls as `"<id>:<method>"`, or a file in `core/` names a module's
  setting key as a string. It does not look at EventBus topics, flags or public APIs, which
  are how modules are meant to name each other. The shared helpers in `tools/lib/play.ts`
  call declared methods (`player:server_move_to`, `world:is_ready_at`) on purpose: they use
  the allow-list, they do not make one, and a helper fails with "not callable" when its
  module is gone.
- `debug_calls` entries must be public names (no leading `_`, no duplicates), and at run time
  `call` refuses a listed method the module's own script does not declare, so a manifest (or
  a `tweaks/` copy of one) naming `call` or `set_script` cannot reopen every method.

## Alternatives
- Modules registering settings from their entry script at load (`Settings.register(...)`).
  Rejected: the settings screen opens from the title, before any module loads, so the rows
  would appear only in a session. The manifest is readable without loading the module.
- `debug_calls` as a constant on each module's entry script. Rejected for the same reason
  as settings and because listing it means loading every entry script; the manifest is
  plain JSON the test and the gate check read as text.
- Dropping settings of deleted modules from the file. Rejected: the player loses a choice
  for a module that may come back, and the file would change shape on save.
- A gate step of its own for the ownership check. The tool tests already run in both gates;
  a separate step would only change where the failure prints.

## Consequences
- Adding a playtest, a debug call or a setting is a change inside the module's folder; a
  reviewer sees new `debug_calls` entries in the module's `module.json` diff.
- Moving a module out of the tree leaves nothing behind that names it in these three places.
- Settings are bool toggles only. A slider or choice setting from a module needs a new
  `type` in `ModuleLoader.SETTING_TYPES` and a row builder on the screen.
- The ownership check matches strings. A core file naming a flag that is spelled like a
  setting key (`&"compass"`) would trip it; read such a failure before widening the check.
- Supersedes the "Scenarios live in `tools/playtests/`" and `DebugHandler.CALLS` /
  `DebugHandler.SETTINGS` parts of 0017.
