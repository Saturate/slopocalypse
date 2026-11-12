# Tweaking Slopocalypse

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
| Player health and respawn | `modules/player/data/player.json` | `max_health`, `respawn_seconds`, `respawn_spread`, `back_to_spawn_cooldown_seconds` (Esc menu "Back to spawn": how long before you can use it again) |
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
| Mission kinds and their names, codename words | `modules/missions/data/missions.json` | `types` (each: `name`, `script`, `defaults` such as Smash & Grab's `strikes`), `codenames` (`first`, `second`) |
| Missions: what the board offers, distance, time, pay | `modules/missions/data/missions.json` | `missions` (each: `type`, `place`, `objective`, `distance` and `payout` ranges, `time_limit` for Smash & Grab, `guards` and `patrols` ranges for Clean Sweep), `offered`, `seed`, `starting_tokens` (what a new player starts with) |
| Strike zone: where, how big, the strike waves | `modules/missions/data/missions.json` | `zone` (`beyond_dropoff`, `radius`), `types.smash_and_grab.defaults.strikes` (`waves` of `{at, drones}`, `overtime_every`, `overtime_drones`, `max_flying`, `building_share`) |
| Soldiers' nerve: how brave, what scares them, when they hold, run or give up | `modules/enemies/data/enemies.json` | `fortitude` (`start` range, `step`, `steady_from`, `bands`, `ally_range`, `wounded_share`, `cornered_range`) |
| Soldiers using cover: how far they look, how long they peek and hide, calling you out | `modules/enemies/data/enemies.json` | `cover` (`search_radius`, `search_every`, `min_threat_distance`, `settle_distance` and `settle_seconds` (how close to its spot it edges when still in sight, and for how long), `peek_seconds`, `hide_seconds`, `bound_range`, `callout_range`, `body_radius` and `sweep_height` (how wide a lane and how high a step count as blocking the way to a spot), `detour_tries` (how many corners it tries for a way round)) |
| Being pinned by fire | `modules/enemies/data/enemies.json` | `suppression` (`near_miss` metres, `per_shot`, `explosion`, `decay` per second, `pinned` threshold, `pinned_aim_scale`) |
| Guards on posts: how far they look either side | `modules/enemies/data/enemies.json` | `post_scan_degrees`, `post_scan_seconds` |
| Mission buildings: how many, sizes (metres), spacing, how many strikes go for them | `modules/missions/data/missions.json` | `buildings`: `count`, `width`, `depth`, `wall_height`, `off_road`, `spread`, `gap`; breaking: `segment` (piece size), `segment_hp`, `blast_damage`, `blast_reach`; collapsing: `max_span` (roof pieces further than this many pieces from a wall still standing fall), `fall_seconds` (how long a falling piece takes to land), `fall_damage` (to anyone under it); `concrete_share`; `pad_margin` and `pad_blend` (the ground is levelled under each building and this far round it, easing back into the slope over `pad_blend` metres); a mission can set `buildings.material` (`wood`, `concrete` or `brick`) |
| Test range: its row of buildings, the charges it hands out, the range bot's timing | `modules/range/data/range.json` | `flags` (modules switched off on the range, so nothing hostile turns up); `mission.buildings.row` (per building `material`, `glass`, `width`, `depth`, `paint`), `gap`, `row_off_road`, `row_clear` (open ground round each); `stand_across` (where you are set down, metres across the road from the row); `gifts`; `bot` (`fire_seconds`, `aim_heights`, `charge_wait_seconds`, `settle_seconds`) |
| What each material takes (wood, glass, sheet metal, brick, mortar, concrete) | `modules/voxkit/data/materials.json` | per material: `bullet` and `blast` damage factors, `min_bullet_damage` (below it a round only chips), bullet `hole` size, `pass` (damage left after going through) and `thickness_max`, glass `breaks_whole`, `hits_to_break`, `crack`, `crack_opacity`; `pop_damage` (a brick in mortar comes out once rounds into it add up to this much damage, 0 never); `stick_chance` (the chance each brick touching one that comes out comes too, half that a step further); keep the order, voxels store positions in the list |
| Strike drones: dive delay, how far they hear shots | `modules/drones/data/drones.json` | `strike_dive_delay`, `strike_alert_radius`, `strike_hear_radius` |
| Mines and tripwires: how close sets them off, how hard they hit, spotting and disarming | `modules/missions/data/missions.json` | `hazards` (`trigger_radius`, `delay`, `blast_radius`, `damage`, `reveal_range`, `disarm_range`, `shot_radius`, `mine_ring`, `signs`); per mission `mines`, `tripwires`, and a `buildings` override |
| Home base: board and car spots, who rides | `modules/missions/data/missions.json` | `board.offset`, `transport.offset` (from the spawn), `home_radius`, `ride_home_reach`, `ride_fade_seconds` |
| Breaching charges: blast, range, which item they use | `modules/weapons/data/weapons.json` | `charge` (`radius`, `damage`, `range`, `cooldown_seconds`, `item`); keys in `modules/player/data/player.json` (`charge`, `detonate`) |
| Trader: what is for sale and for how much, what selling pays | `modules/trader/data/trader.json` | `stock` (`item`, `price`), `sell_share`, `unlisted_price`, `stall.offset` |
| What you come back with after dying | `modules/inventory/data/items.json` | `respawn_gear` (empty: nothing) |
| Bodies: how long they stay, colour | `modules/inventory/data/items.json` | `bodies`: `seconds`, `empty_seconds` (once searched empty), `colour` |
| Crate grid size | `modules/inventory/data/items.json` | `crates.grid` |
| Enemy numbers and timing | `modules/enemies/data/enemies.json` | `first_spawn_seconds`, `max_alive`, `squad_size`, `squad_respawn_seconds`, `spawn_distance`, `corpse_seconds` |
| Enemy difficulty | `modules/enemies/data/enemies.json` | `max_health`, `reaction_seconds`, `aim_error_degrees` (`[at first, once settled]`), `aim_settle_seconds`, `damage_scale`, `burst_shots`, `burst_pause_seconds` |
| Enemy senses | `modules/enemies/data/enemies.json` | `sight_range`, `sight_cone_degrees`, `hearing_range`, `chase_seconds`, `forget_seconds` |
| Enemy look | `modules/enemies/data/enemies.json` | `uniform_tint` (`[r, g, b]`, 0 to 1) |
| Drone | `modules/drones/data/drones.json` | `max_health`, `speed`, `orbit_*` (attack orbit), `calm_orbit_*` (how it circles before anyone provokes it), `aim_cone_degrees`, `aim_range`, `aim_seconds` (how long someone aims down sights at it before it turns angry), `calm_after_seconds`, `respawn_seconds`, `max_drones`, `dive_*`, `crash_*` |
| Car handling | `modules/car/data/car.json` | `engine_force`, `top_speed`, `brake_force`, `max_steer_degrees`, `high_speed_steer_share` (how much of the lock is left at top speed), `downforce` (extra grip that grows with speed), `suspension_*`, `friction_slip`, `roll_influence`, `flip_seconds` (how long on its roof or side before it rights itself) |
| Car camera | `modules/car/data/car.json` | `camera`: `distance`, `height`, `look_ahead`, `follow_rate` (higher follows tighter), `fov` and `fov_at_top_speed`, `orbit_sensitivity` (mouse), `orbit_return_seconds` (how soon it swings back behind) |
| Car looks | `modules/car/data/car.json` | `looks`: `paint` (0 rust red, 1 army green, 2 faded blue, 3 sand, 4 primer grey), `wear` (rust and mud, 0 to 1), `seed`; plus `length`, `width` |
| Sound volumes and ranges | `modules/audio/data/audio.json` | `volume_db` (per sound, in dB: `-6` is about half as loud), `shot_range`, `footstep_range`, `rotor_range`, `rotor_angry_pitch`, `rotor_angry_db` (the drone hum), `birds` (`min_seconds`/`max_seconds` between bird songs, `distance_min`/`distance_max`); `wind`, `bird`, `crickets` in `volume_db` are the ambience; surfaces: `surface_families` (which sound family each voxel material uses), `hit_*`, `break_*` and `collapse` in `volume_db`, `surface_hit_range`, `surface_break_range` |
| Rounds going through walls | `modules/weapons/data/weapons.json` and `modules/voxkit/data/materials.json` | `max_pass_throughs` (how many things one round may go through); per material `pass` (share of damage left after going through, 0 stops rounds), `thickness_max`, `min_bullet_damage` |
| Headshots | `modules/weapons/data/weapons.json` | `headshot.kills` (teams a headshot kills outright, `"enemies"` for guards), `headshot.multiplier` (damage times this for everyone else) |
| Training dummies | `modules/training/data/training.json` | `max_health`, `respawn_seconds`, `dummies` |
| Saving: where, how often | `modules/persistence/data/persistence.json` | `file` (the save; `--save=PATH` on the server wins), `autosave_seconds`, `hold_seconds` (how long a returning player waits in the air for ground) |
| The map: length, width, hills | `modules/world/data/world.json` | `length`, `width`, `behind` (metres behind the spawn), `height_amplitude`, `noise_frequency`, `seed`, `cover` (boxes near the spawn; empty now that it is in the tunnel) |
| The start: tunnel and mountain | `modules/world/data/world.json` | `start`: `portal_z` (where the tunnel mouth is; the spawn is at 0), `tunnel_end_z` (where the cave-in seals it), `collapse_length` (how deep the rubble is), `tunnel_half_width`, `tunnel_height`, `mountain_height`, `mountain_front` / `mountain_back` (how far in front of and behind the portal the mountain rises), `car_distance` and `car_side` (where the car waits outside) |
| The road | `modules/world/data/world.json` | `road`: `offset` (how far beside the spawn it runs; 0 puts the spawn on it), `half_width`, `blend` (how wide the levelled ground beside it is), `wander` and `wander_frequency` (how much it winds), `smoothing`, `max_grade` (steepest climb per metre) |
| Biomes down the road | `modules/world/data/world.json` | `stages`: a list of `{at: metres down the road, forest, dry, rock, hills}`; values blend between neighbouring stages |
| Trees, rocks, grass | `modules/world/data/world.json` | `scatter`: `trees_per_hectare`, `rocks_per_hectare`, `grass_per_m2`, `variants` (how many different models of each), `load_distance` (how far ahead scenery appears), `tree_detail_distance`, `grass_distance`, `tree_hits` (bullets to fell a tree), `tree_blast_reach` (explosions fell trees out to this many times their radius), `tree_fall_seconds`, `tree_collapse` (how much a fallen crown squashes, 0 to 1), `tree_wither_seconds` (how long a fallen top takes to dry out to bare branches) |
| Craters and falling through | `modules/world/data/world.json` | `voxel.max_dig_depth` (deepest a crater goes under the ground), `rescue_depth` (this far under the ground counts as fallen through: you are put back on top) |
| Voxel ground detail | `modules/world/data/world.json` | `voxel.lods` (`[[metres, voxel size], ...]`: finer blocks close by), `voxel.load_distance`, `voxel.collision_distance`, `voxel.builds_per_frame` (more loads ground faster but can hitch) |
| Flying debris (buildings, craters, trees) | `modules/world/data/debris.json` | `max_pieces` (most cubes flying at once; past it the oldest go first), `sources.<source>` for `building` (a wall or roof piece breaking), `building_chip` (a bullet hitting a wall), `crater`, `tree` (a bullet in a trunk), `tree_cut`, `tree_blast`, `tree_crown`, `brick` (a single brick knocked out), `glass_shards` (a pane of window, laminated or security glass going), `glass_bits` (tempered glass going): `count` (cubes), optional `size` (cube edge in metres, 0.12 when left out), `speed` (metres per second), `speed_jitter` (each cube's speed varies by up to this share), `angle_jitter_degrees` (how far each cube strays from the throw direction), `spin_max` (radians per second on each axis), `lifetime_seconds`; craters scale with their size: `count_per_m2` (between `count_min` and `count`) and `speed_per_metre` of radius on top of `speed` |
| Voxel corner shading (darker cracks, inside corners and holes) | `modules/voxkit/data/voxkit.json` | `corner_shading`: `on` (false turns it off, for comparing or if it clashes with the pixel filter), `levels` (brightness of a face corner from most crowded to open, 4 numbers from 0 to 1) |
| Leaning (Q / E) | `modules/player/data/player.json` | `lean_offset` (how far the eye moves, metres), `lean_degrees` (camera tilt), `lean_body_degrees` (how far others see the body tilt), `lean_seconds` |
| Waiting for ground | `modules/player/data/player.json` | `hold_seconds` (a respawned or rescued player is held still until there is ground under them, at most this long) |
| Admin panel (F2) | `modules/admin/data/admin.json` | `admins` (names or player keys allowed on a server; the panel shows your key; anyone on the server's own machine is an admin when `local_is_admin`), `toggle_key`, `spawn_ahead`, `teleport_ahead`, `squad_size`, `hours` (the time buttons) |
| Day and night | `modules/daytime/data/daytime.json` | `start_hour` (time when the server starts), `hour_seconds` (real seconds per game hour by day), `night_speed` (how many times faster the night passes), `sunrise`, `sunset`, `sun_max_elevation`, `moon_max_elevation`, `keys` (per hour: light colour and strength, sky colours, `ambient`, fog, `exposure`, `stars`) |
| Performance log (F3) | `modules/perf/data/perf.json` | `sample_seconds` (how often a line is written to `perf/` in the game's user folder), `spike_ms` (a frame slower than this gets its own line), `warmup_seconds` (no spike lines while loading), `keep_files` (older logs are deleted), `overlay_key` |

## Good first tweaks

- Enemies too hard: raise `reaction_seconds`, raise both `aim_error_degrees`, lower `damage_scale`.
- Want more fights: raise `max_alive`, lower `squad_respawn_seconds` and `first_spawn_seconds`.
- Loot too rare: raise `npc_loot.rolls` and `crates.rolls`, lower `crates.refill_seconds`.
- Dying too costly: give a bigger `starting_kit`, or lower `respawn_seconds`.
- Nights too long or too dark: raise `night_speed`, or raise `light_energy`, `ambient` and `exposure` in the night `keys`.
- Guns feel weak: raise the receiver's `damage` in `parts.json`, or lower everyone's `max_health`.

## The save

The server keeps everyone's gear in an SQLite file: `world.db` in the Godot user folder under `saves/` (on Windows `%APPDATA%\Godot\app_userdata\Slopocalypse\saves\`), or wherever `--save=` points. Solo and hosted games share that one world. Open it with any SQLite viewer (DB Browser for SQLite) while the server is off to look or fix things: `players`, `player_items` and `player_builds` per name, `world_loot` and `crates` for the world. Delete the file for a fresh world. Start a server with `--no-save` to play without touching it.
