# Tweaking Outpost

Every gameplay number lives in a JSON file. Change it, start the game again, play.

- **From the project:** edit the file under `modules/<id>/data/` (or `data/`) directly.
- **In the portable zip:** copy the file from `defaults/` into `tweaks/` at the same path and edit the copy. It replaces the built-in file; delete it to go back. The game logs `using the tweaked copy` when it picks one up.
- **Multiplayer:** the server decides damage, health, enemies, drones, loot and crates, so tweak on the machine that hosts. Give friends the same `tweaks/` folder so gun parts and feel match.
- **Bad values fail loudly:** a missing field or a wrong type is logged with the file and field name, and that feature stays off instead of misbehaving.

JSON numbers are plain numbers (`2.5`), pairs like `[min, max]` are ranges the game rolls within, and `seconds` are seconds.

## Where things live

| To change | File | Fields |
| --- | --- | --- |
| Which features are on (enemies, drones, car, audio, ...) | `data/features.json` | `flags` |
| Player health and respawn | `modules/player/data/player.json` | `max_health`, `respawn_seconds`, `respawn_spread` |
| Movement: speeds, jump, slide, vault, mantle | `modules/player/data/player.json` | `walk_speed`, `sprint_speed`, `crouch_speed`, `jump_velocity`, `slide_*`, `vault_*`, `mantle_*` |
| Camera and mouse | `modules/player/data/player.json` | `fov`, `fov_sprint_bonus`, `bob_amplitude`, `mouse_sensitivity` |
| Aiming down sights | `modules/player/data/player.json` | `ads_speed_multiplier`, `ads_seconds`, `ads_eye_relief` |
| Keys | `player.json`, `weapons.json`, `items.json`, `car.json` | `bindings` (Godot key names: `"W"`, `"Tab"`, `"Shift"`) |
| Recoil feel, ADS spread and zoom, draw time | `modules/weapons/data/weapons.json` | `rifle`: `kick_back`, `recoil_recovery`, `ads_spread_multiplier`, `ads_zoom`, `draw_seconds` |
| Friendly fire | `modules/weapons/data/weapons.json` | `friendly_fire` (`true` lets you hurt each other) |
| Demolition charge | `modules/weapons/data/weapons.json` | `charge`: `damage`, `radius`, `fuse_seconds`, `cooldown_seconds` |
| Gun stats (damage, fire rate, recoil, spread, reload, magazine, range, zoom) | `modules/weapons/data/parts.json` | each part's `stats`; the receiver holds the base values, other parts add `*_pct` changes and `ergonomics` |
| What guns you start with | `modules/weapons/data/parts.json` | `default_build`, `default_secondary`, `builds` |
| New gun parts or builds | `modules/weapons/data/parts.json` and `modules/inventory/data/items.json` | a part needs an entry in both (stats there, grid size and name here); meshes are code |
| Backpack size, starting kit | `modules/inventory/data/items.json` | `grid`, `starting_kit` |
| Item sizes and names | `modules/inventory/data/items.json` | `items` |
| Medkit healing | `modules/inventory/data/items.json` | `items.medkit.use`: `heal`, `seconds` |
| What enemies carry | `modules/inventory/data/items.json` | `npc_loot`: `rolls`, `items` (weights) |
| Crates: how many, where, refill, contents | `modules/inventory/data/items.json` | `crates`: `count`, `distance`, `seed`, `refill_seconds`, `rolls`, `items` |
| Loot piles at the spawn | `modules/inventory/data/items.json` | `loot` |
| Enemy numbers and timing | `modules/enemies/data/enemies.json` | `first_spawn_seconds`, `max_alive`, `squad_size`, `squad_respawn_seconds`, `spawn_distance`, `corpse_seconds` |
| Enemy difficulty | `modules/enemies/data/enemies.json` | `max_health`, `reaction_seconds`, `aim_error_degrees` (`[at first, once settled]`), `aim_settle_seconds`, `damage_scale`, `burst_shots`, `burst_pause_seconds` |
| Enemy senses | `modules/enemies/data/enemies.json` | `sight_range`, `sight_cone_degrees`, `hearing_range`, `chase_seconds`, `forget_seconds` |
| Enemy look | `modules/enemies/data/enemies.json` | `uniform_tint` (`[r, g, b]`, 0 to 1) |
| Drone | `modules/drones/data/drones.json` | `max_health`, `speed`, `orbit_*`, `respawn_seconds`, `max_drones`, `dive_*`, `crash_*` |
| Car handling | `modules/car/data/car.json` | `engine_force`, `top_speed`, `brake_force`, `max_steer_degrees`, `suspension_*`, `friction_slip` |
| Sound volumes and ranges | `modules/audio/data/audio.json` | `volume_db` (per sound, in dB: `-6` is about half as loud), `shot_range`, `footstep_range` |
| Training dummies | `modules/training/data/training.json` | `max_health`, `respawn_seconds`, `dummies` |
| Saving: where, how often | `modules/persistence/data/persistence.json` | `file` (the save; `--save=PATH` on the server wins), `autosave_seconds`, `hold_seconds` (how long a returning player waits in the air for ground) |
| The map: length, width, hills | `modules/world/data/world.json` | `length`, `width`, `behind` (metres behind the spawn), `height_amplitude`, `noise_frequency`, `seed`, `cover` |
| The road | `modules/world/data/world.json` | `road`: `offset` (how far beside the spawn it starts), `half_width`, `blend` (how wide the levelled ground beside it is), `wander` and `wander_frequency` (how much it winds), `smoothing`, `max_grade` (steepest climb per metre) |
| Biomes down the road | `modules/world/data/world.json` | `stages`: a list of `{at: metres down the road, forest, dry, rock, hills}`; values blend between neighbouring stages |
| Trees, rocks, grass | `modules/world/data/world.json` | `scatter`: `trees_per_hectare`, `rocks_per_hectare`, `grass_per_m2`, `variants` (how many different models of each), `load_distance` (how far ahead scenery appears), `tree_detail_distance`, `grass_distance` |
| Craters and falling through | `modules/world/data/world.json` | `voxel.max_dig_depth` (deepest a crater goes under the ground), `rescue_depth` (this far under the ground counts as fallen through: you are put back on top) |
| Waiting for ground | `modules/player/data/player.json` | `hold_seconds` (a respawned or rescued player is held still until there is ground under them, at most this long) |

## Good first tweaks

- Enemies too hard: raise `reaction_seconds`, raise both `aim_error_degrees`, lower `damage_scale`.
- Want more fights: raise `max_alive`, lower `squad_respawn_seconds` and `first_spawn_seconds`.
- Loot too rare: raise `npc_loot.rolls` and `crates.rolls`, lower `crates.refill_seconds`.
- Dying too costly: give a bigger `starting_kit`, or lower `respawn_seconds`.
- Guns feel weak: raise the receiver's `damage` in `parts.json`, or lower everyone's `max_health`.

## The save

The server keeps everyone's gear in an SQLite file: `world.db` in the Godot user folder under `saves/` (on Windows `%APPDATA%\Godot\app_userdata\Outpost\saves\`), or wherever `--save=` points. Solo and hosted games share that one world. Open it with any SQLite viewer (DB Browser for SQLite) while the server is off to look or fix things: `players`, `player_items` and `player_builds` per name, `world_loot` and `crates` for the world. Delete the file for a fresh world. Start a server with `--no-save` to play without touching it.
