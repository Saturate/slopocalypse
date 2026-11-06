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
- Cover blocks are plain boxes: no bevels, planks or concrete detail (visual review, #34). Replace with proper prop meshes when the generated map adds buildings (#32).
- Rifle view model is placeholder boxes seen a little side-on; arms and a proper pose come with #29.
- Contact sheets shrink frames to 640x360, so thin HUD lines and short tracers can vanish; check HUD with a single full-size frame (`--sheet 1`).
- The player capsule has no walk bob or sway, so movement is hard to read in captures. Arrives with weapon motion in Phase 1.

## Later

- Scenario tests step physics in real time (16 s for five player tests). Consider a faster physics tick or Engine.time_scale in tests once the suite grows.
