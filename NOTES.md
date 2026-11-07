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
- One gun, true first person: you see your own arms and the same rifle everyone else sees, shifted lower right for your view only. Rough: the support forearm reads pale and flat close to the camera (sun and flash); the red dot's tube looks like a black ball from behind; there's no weapon bob or sway of its own yet. The `shoot` capture's long bursts climb over the dummy from recoil, so only the first shot hits; that's the capture, not a bug.
- Body v2 (realistic proportions): the plate carrier still reads back-heavy from the side because the arms hide the chest pouches; the face is a plain box; the stock rides at cheek height when crouched and aiming up; the slide reads a bit like kneeling.
- Body animation (#48 rig): the walk cycle's front leg reaches forward only a little, so a single frame can look like a heel lift; crouch lean reads mild on the deep torso block; the rifle stock sits just ahead of the shoulder in run and aim down; the right hand is hidden behind the receiver from the side. Clips are generated in `05_player_body.gd`, so tune the pose functions there. No reload or throw animation yet: reload isn't replicated to other clients.
- Scopes (#65): optics with `magnification` above 1 get a picture-in-picture lens (`ScopeView`, local player only): a SubViewport camera at the `Objective` marker renders at the lens' angle divided by the magnification, drawn on the `Lens` marker with a duplex reticle; it renders only while aiming. Optics set their own `eye_relief` through `marker_meta`. Mouse turning slows by the magnification while scoped. Try builds with `-- --build=ar_dmr` (dev hook until #66; solo passes it to its server). Rough: one fixed 4x scope; no zeroing, parallax or scope shadow; the reticle is black and gets lost on dark trees; world labels must sit on `RenderLayers.MAIN_VIEW_ONLY` or they show magnified.
- Main menu (#69): a windowed game opens to Solo / Host a game / Join a friend; failed or dropped connections come back to it with the reason, and Esc in game has Resume / Leave to menu / Quit. Hosting runs the same local server as solo but on every interface at the chosen port; it still quits once everyone has left, and if the host leaves first while friends are still in, it keeps running headless until they leave. Joins give up after about 8 s. Rough: the menu is a plain panel on a dark background; no world behind it. Esc pauses nothing (it's multiplayer), it only shows the panel.
- The solo server writes its log to `user://logs/solo-server.log` (the path is printed at startup). Look there when something works with a dedicated server but not in solo.

## Later

- Scenario tests step physics in real time (16 s for five player tests). Consider a faster physics tick or Engine.time_scale in tests once the suite grows.
