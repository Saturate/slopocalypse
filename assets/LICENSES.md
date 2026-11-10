# Licences

Every third-party asset, generated asset and vendored code in this repo, with its source and licence. Add a row when adding the file.

| Path | What | Source | Licence | Added |
| --- | --- | --- | --- | --- |
| (not committed) `tools/godot/` | Godot Engine 4.7.2 binary, fetched by `tools/get-godot.ts` | https://github.com/godotengine/godot/releases/tag/4.7.2-stable | MIT | 2026-11-06 |
| `addons/gdUnit4/` | gdUnit4 6.2.3 test framework (dev only, excluded from exports) | https://github.com/godot-gdunit-labs/gdUnit4/releases/tag/v6.2.3 | MIT | 2026-11-06 |
| (not committed) `tools/changesetter/` | changesetter 0.5.2 release binary (dev tool: versions and changelog), fetched by `tools/get-changesetter.ts` (SHA256 pinned) | https://github.com/Saturate/changesetter/releases/tag/changesetter%40v0.5.2 | MIT (LICENSE file) | 2026-11-09 |
| (not committed) `addons/zylann.voxel/` | Voxel Tools 1.7 GDExtension, fetched by `tools/get-addons.ts` (SHA256 pinned) | https://github.com/Zylann/godot_voxel/releases/tag/v1.7x | MIT | 2026-11-06 |
| (not committed, Cargo) `modules/persistence/rust/core` | rusqlite 0.40.2 with bundled SQLite 3 (compiled into the server's persistence library) | https://crates.io/crates/rusqlite, https://sqlite.org | MIT (rusqlite), public domain (SQLite) | 2026-11-08 |
| `modules/world/textures/Grass004/` | Grass texture set (Color, NormalGL, Roughness 1K) | https://ambientcg.com/view?id=Grass004 | CC0 | 2026-11-06 |
| `modules/world/textures/Ground037/` | Dirt texture set (1K) | https://ambientcg.com/view?id=Ground037 | CC0 | 2026-11-06 |
| `modules/world/textures/Rock030/` | Rock texture set (1K) | https://ambientcg.com/view?id=Rock030 | CC0 | 2026-11-06 |
| `modules/world/textures/Concrete034/` | Concrete texture set (1K) | https://ambientcg.com/view?id=Concrete034 | CC0 | 2026-11-06 |
| `modules/world/textures/Planks037A/` | Wood planks texture set (1K) | https://ambientcg.com/view?id=Planks037A | CC0 | 2026-11-06 |
| `modules/world/textures/Bark014/` | Bark texture set (Color, NormalGL 1K) | https://ambientcg.com/view?id=Bark014 | CC0 | 2026-11-06 |

## Tools (not shipped)

- **ffmpeg 9.0.2**, the "essentials" Windows build from gyan.dev (https://github.com/GyanD/codexffmpeg), GPL-3.0. Fetched by `tools/get-ffmpeg.ts` into the git-ignored `tools/ffmpeg/` to encode trailers; never bundled with the game.
