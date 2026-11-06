---
name: godot-conventions
description: Outpost's rules for writing Godot 4.7 GDScript, scenes, modules and gdext Rust, plus the engine quirks that fail silently. Use before writing or changing any .gd, .tscn, module.json, .gdextension or modules/*/rust code in this repo, when adding a module, component, builder or test, or when a Godot run behaves oddly (exit 0 with errors, missing nodes, random ids in scene diffs, autoload not found).
metadata:
  author: Saturate
  version: "1.0"
---

# Godot conventions for Outpost

Architecture rules live in `CLAUDE.md`; this skill is the how-to and the list of traps. Engine is pinned to Godot 4.7.2. When an API detail is uncertain, check the installed engine (a throwaway `-s` script printing `ClassDB.class_get_method_list(...)`) instead of recalling it. Models default to Godot 3 names; see [references/godot3-to-4.md](references/godot3-to-4.md).

## Adding a module

1. Copy `modules/example/` to `modules/<id>/`.
2. Edit `module.json`: `id`, `depends_on` (module ids), `flag` (empty string means always on), `entry` (script extending `Node`).
3. Add the flag to `data/features.json`.
4. Keep everything for the feature inside the folder: `scenes/`, `builders/`, `data/`, `tests/unit|scenario|net/`, `rust/`.
5. Talk to other modules only through `EventBus.publish(&"module.event", payload)` / `subscribe`, or a small public API script. Never `get_node` into another module.
6. Run `npm run check:full`. Then move the folder out of the project and run it again: it must stay green.

## Components

Entities are scenes made of small component nodes, one job each (`HealthComponent`, `NoiseEmitter`). Values come from `data/` through `Data`, never literals. A component finds siblings through exported `NodePath`s set by the builder, not by searching the tree.

Player, bot and network input all write to an intent component (move vector, look, fire, interact) that the controller reads. Headless Godot does not deliver `InputEvent`s, so tests set the intent directly; never simulate key presses.

## Server and client code

- State changes happen in `server_*` functions guarded by `multiplayer.is_server()`; clients call `request_*` RPCs.
- Without a network peer, Godot's `OfflineMultiplayerPeer` makes the local instance peer 1, so server code runs locally in unit tests.
- Rendering, audio, input and UI code lives in scripts the server never loads.

## Scenes come from builders

Entity, prefab and UI scenes are generated, never hand-edited:

```gdscript
extends SceneTree  # modules/<id>/builders/10_thing.gd

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Thing"
	# build children, set local transforms, set_script() before setting exported properties
	var result := SceneBuilder.pack_and_save(root, "res://modules/<id>/scenes/thing.tscn")
	root.free()
	if result.error != OK:
		push_error(result.message)
		quit(1)
		return
	quit(0)
```

- Run `node tools/build-scenes.ts` after changing a builder and commit the `.tscn`. The full gate fails if a rebuild changes any scene.
- Prefix builders with numbers (`10_`, `20_`) so leaf scenes build before scenes that instance them, and `load()` them (a `preload()` of a not-yet-built scene is a parse error).
- `SceneBuilder` handles owners, refuses to save if nodes would be dropped, does not inline instanced scenes, and rewrites Godot's random per-save ids so output is byte-identical.
- Builder scripts cannot name autoloads (`Log`, `Data`); use `root.get_node("Data")` or plain `push_error`.
- Nodes in a builder are outside the tree: `look_at()` and `global_*` silently do nothing useful. Set local transforms; use `Transform3D.looking_at()`.
- The hand-built world map (later phases) is the exception and is edited in the Godot editor.

## Rust

- Pure rules in `modules/<id>/rust/core` (no `godot` dependency, `cargo test`, `unsafe` denied).
- `modules/<id>/rust/gd` is a thin cdylib exposing core types with `#[derive(GodotClass)]` and `#[func]`. Crate-level `#![allow(unsafe_code)]` is only for gdext's `unsafe impl ExtensionLibrary`.
- The module ships `<id>.gdextension` with library paths under `res://modules/<id>/bin/<os>/<profile>/`; copy `modules/example/example.gdextension` and rename.
- `node tools/build-rust.ts` builds and copies libraries; the gate runs it before Godot imports. On Windows a running editor locks the DLL: close it before rebuilding.

## Tests

- `tests/unit` (fast gate), `tests/scenario` and `tests/net` (full gate), at the root and inside each module.
- gdUnit4: `extends GdUnitTestSuite`, `test_*` functions, `auto_free()` for nodes.
- Expected errors: wrap in `Log.begin_capture()` / `Log.end_capture()` and assert on `LogCapture.text(entries)`. An uncaptured `push_error` fails the gate even though gdUnit4 passes the test.
- Assert behaviour, never on-screen wording.

## Silent failures we have hit or guard against

| Symptom | Cause | What we do |
| --- | --- | --- |
| Godot exits 0 but something broke | Runtime `SCRIPT ERROR` only aborts that function; `push_error` never fails gdUnit4 | Gate scans logs for `SCRIPT ERROR`, `ERROR:`, `Error:` |
| `Identifier not found: Log` from `--check-only` | It compiles scripts without autoloads | Gate compiles inside a running project (`tools/gd/check_scripts.gd`) |
| Check script crashes Godot | Loading `check_scripts.gd` from itself segfaults | `tools/` scripts are excluded from the compile list |
| Scene diff every rebuild | 4.6+ writes random `unique_id` per node, random sub-resource ids | `SceneBuilder` rewrites both deterministically |
| Nodes missing from a saved scene | Node had no `owner` | `SceneBuilder.pack_and_save` counts before and after, refuses to save |
| 100 MB `.tscn` | Owning children of an instanced GLB inlines it | Ownership stops at nodes with `scene_file_path` |
| Exported property silently not set | `set()` before `set_script()` | Attach scripts first |
| Deleted module still errors on import | `.godot/extension_list.cfg` caches extensions | Gate rewrites the list before importing |
| Procedural mesh gets no shadows | Missing normals | `SurfaceTool.generate_normals()`; fix winding, do not disable culling |
| Raycasts miss terrain | Trimesh (`ConcavePolygonShape3D`) hits are unreliable | Heightmap shapes or analytic height queries |
| Imported model tanks FPS | `create_trimesh_shape()` on a mesh | Primitive collision shapes sized from the AABB |
| `:=` refuses to infer | Untyped call (`abs`, `load(...).instantiate()`) | Typed variants (`absf`, `clampf`) or an explicit type |
| Frame-rate dependent damping | `v *= (1 - drag)` per tick | `v *= exp(-rate * delta)` |
| Folder silently not imported | A `.gdignore` inside it | Only `tools/godot/` and `target/` carry one |
| Headless run hangs (macOS) | Fatal error shows a modal dialog | Every Godot call in tools has a timeout |
| Car drives backwards | `VehicleBody3D` drives along +Z, not Godot's usual -Z forward | Cars use +Z as the nose: steering wheels at +Z, camera at -Z turned round |
| Throttle does nothing on a parked car | A settled `RigidBody3D` sleeps and `engine_force` does not wake it | `can_sleep = false` while driven, `sleeping = false` on enter |
| Car bounces for seconds | Raycast-vehicle damping scales with 2·sqrt(stiffness); 0.3 is far too low | Damping in whole units (2.5 / 3.5 at stiffness 45) |
| Later tests in a suite never run | gdUnit4 stops a suite at the first failing test | Fix the first failure, then rerun; don't read "N passed" as the whole suite |
