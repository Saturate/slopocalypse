# Notes

Running notes: playtest feedback, findings, known issues and ideas for later. Decisions with lasting impact also go in the spec folder's ROADMAP.

## Phase 0 findings

### Car handling

- Built on `VehicleBody3D` + 4 `VehicleWheel3D` on Jolt (#8). Works out of the box once three traps are handled: it drives along +Z, a sleeping body ignores engine force, and suspension damping needs whole-unit values.
- Current tune (car.json): 900 kg, 2200 engine force on the rear wheels, top speed 22 m/s, 30 degree steering. 0 to 10 m/s in under 3 s on flat ground, stops from about 15 m/s within 30 m.
- Not yet felt by a human: Checkpoint A playtest decides whether to keep `VehicleBody3D` or try raycast wheels.

### Netcode feel

### Harder than expected

- `tar` under Git Bash is GNU tar and cannot extract to `C:\...` paths; `tools/get-godot.ts` calls System32 `tar.exe` on Windows.

### Recommendation

## Known issues

- Cover boxes are axis-aligned on slopes, so one corner digs in and the far end can lift (visual review, #7). Fine for greybox; align to the terrain normal when the real map arrives.
- Car chase camera is rigidly parented to the car, so speed and turns are hard to read (visual review, #8). A smoothed follow camera with lag and FOV kick is a candidate after the Checkpoint A playtest.
- The box car has no front or back shape, so its heading is hard to read from outside.
- Grass, rocks and trees stay floating where the ground was dug away; the scatter doesn't know about digging yet (#30). Move scenery to VoxelInstancer, which removes instances on edits.
- Dust puffs are hard-edged spheres; soft particles come with the art pass (#38).
- Cover blocks are plain boxes: no bevels, planks or concrete detail (visual review, #34). Replace with proper prop meshes when the generated map adds buildings (#32).
- The view model can still clip into walls when standing right against them; it renders on its own light layer but not yet on top. Fix with a view-model shader or SubViewport when it bothers playtesters.
- Contact sheets shrink frames to 640x360, so thin HUD lines and short tracers can vanish; check HUD with a single full-size frame (`--sheet 1`).
- The player capsule has no walk bob or sway, so movement is hard to read in captures. Arrives with weapon motion in Phase 1.
- Solo runs through its own server process (#12), so anything not networked is missing in solo too. Remote state has no smoothing yet, so other players and the car (even your own, while driving) may look steppy, and the car responds a round trip late; driver-side car physics is the follow-up to #14.
- Guns from parts (#63): `modules/weapons/data/parts.json` holds parts (slot, provides, mounts, markers, stats) and builds; Rust `weapons_core::parts` validates and computes stats; `GunAssembly` builds the model. Every instance equips `default_build`; per-player builds need the server to send them (#66). Part meshes (#64) are extruded side profiles, lofted curves and toothed rails, 2k to 6k triangles per gun (a test keeps the budget); optics have glass. Rough: no underbarrel or tactical slots yet, weight does nothing yet, the stock and grip are flat-sided extrusions with strips rather than sculpted, and in first person the support sleeve is a big flat tan shape in the lower left.
- ADS (#62): right mouse. The aim modifier turns and moves the shoulders so the held weapon's `Sight` marker sits `ads_eye_relief` in front of the camera, and the head leans onto the stock for others. Rough: the receiver and rail fill the bottom of the screen while aimed; the near elbow flares out in third person; no ADS sway, breathing or inertia yet; ADS time is one value in player.json until part stats (#63) feed it. Spread multiplier is GDScript; move to the Rust weapon rules with #63.
- One gun, true first person: you see your own arms and the same rifle everyone else sees. In first person the shoulders are held by the camera like a view model (`hip_sight` in the aim modifier), so arms and gun turn with the view and looking down never shows the shoulders from above; others see the animated pose. Rough: the support forearm reads pale and flat close to the camera (sun and flash); the red dot's tube looks like a black ball from behind; there's no weapon bob or sway of its own yet. The `shoot` capture's long bursts climb over the dummy from recoil, so only the first shot hits; that's the capture, not a bug.
- Body v2 (realistic proportions): the plate carrier still reads back-heavy from the side because the arms hide the chest pouches; the face is a plain box; the stock rides at cheek height when crouched and aiming up; the slide reads a bit like kneeling.
- Body animation (#48 rig): the walk cycle's front leg reaches forward only a little, so a single frame can look like a heel lift; crouch lean reads mild on the deep torso block; the rifle stock sits just ahead of the shoulder in run and aim down; the right hand is hidden behind the receiver from the side. Clips are generated in `05_player_body.gd`, so tune the pose functions there. No reload or throw animation yet: reload isn't replicated to other clients.
- Health and death (#91): players have 100 health (player.json), synced; at zero they drop (hidden, not hittable, still), their backpack spills where they fell, and they respawn near the spawn after `respawn_seconds`. Guns are kept. Friendly fire is off (`friendly_fire` in weapons.json). HUD: health bar, red edge flash when hit, death screen with countdown. Rough: no healing yet (#93), no fall damage, no death camera or ragdoll, the dead player's camera just stays put.
- Inventory (#83): Tab. A 10x6 backpack grid; items take w x h cells (`modules/inventory/data/items.json`, item ids are part ids), drag to move, R turns while dragging, the drop spot previews green or red with the same Rust rules (`inventory_core`) the server checks. The server holds every inventory and sends each owner theirs after a change; everyone starts with a kit of spare parts. Other modules use `count`, `server_give`, `server_take` and `inventory.changed`. Rough: not saved (resets with the server), tiles are coloured blocks with names, no item icons yet, no equipment panel for the two guns, Loot (#84): a few piles of parts lie near the spawn; E picks up what you face within reach (the press is claimed so it never also enters the car), dragging a tile out of the backpack drops it in front of you; gun parts lie as their own models. Loot is server-spawned and replicated, and not saved. Modding (#85) offers only parts in the inventory plus the fitted ones; Apply takes fitted parts out and puts removed ones back, refusing (and undoing) if they do not fit.
- Handgun and weapon slots (#82): everyone carries a primary (rifle) and a secondary (pistol); 1 and 2 switch (server decides, `Intent:weapon_slot` syncs), drawing takes `draw_seconds`, and the pistol is semi-auto (`fire_mode` on the receiver). Receivers can name their own required slots (`requires`), where they are held (`hold`), their first-person hip point (`hip_sight`) and ADS eye distance (`eye_relief`). Hands follow each gun's `GripR` / `GripL` markers through the hand IK. Modding (B) edits whichever gun is drawn. Rough: the holstered gun is hidden rather than slung or holstered, no switching animation, the big first-person forearms cover a lot of the view with the pistol out, and in third person the aimed pistol sits close to the face.
- Modding screen (#66): B in game. Parts are swapped on a draft with a turning preview and a now/new stat table; Apply sends the build to the server, which checks it with the Rust rules and replays `weapons.build_changed` to everyone (late joiners get a catch-up), so others see your gun. The new gun starts with an empty magazine and a reload, so a swap is never a free top-up. A free mouse now stops the player (pause panel, modding screen). Rough: every part is offered (no inventory yet), you can mod anywhere, even mid-fight (outposts or a bench should gate it later), builds reset when the server restarts, and refused builds are only logged until the journal (#11).
- Scopes (#65, reworked after playtest): a magnified optic zooms the whole view by its magnification once it is up to the eye, and `ScopeView` draws the scope picture over it (black outside a round lens, duplex reticle, red centre dot); the gun model hides while it is up. The first version drew a picture-in-picture lens, which read badly in play. Try builds with `-- --build=ar_dmr` or the modding screen. Rough: one fixed 4x scope; no zeroing, breathing sway or scope shadow when the eye is off-centre.
- Main menu (#69): a windowed game opens to Solo / Host a game / Join a friend; failed or dropped connections come back to it with the reason, and Esc in game has Resume / Leave to menu / Quit. Hosting runs the same local server as solo but on every interface at the chosen port; it still quits once everyone has left, and if the host leaves first while friends are still in, it keeps running headless until they leave. Joins give up after about 8 s. Rough: the menu is a plain panel on a dark background; no world behind it. Esc pauses nothing (it's multiplayer), it only shows the panel.
- The solo server writes its log to `user://logs/solo-server.log` (the path is printed at startup). Look there when something works with a dedicated server but not in solo.

## Later

- Scenario tests step physics in real time (16 s for five player tests). Consider a faster physics tick or Engine.time_scale in tests once the suite grows.
