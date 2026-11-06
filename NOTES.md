# Notes

Running notes: playtest feedback, findings, known issues and ideas for later. Decisions with lasting impact also go in the spec folder's ROADMAP.

## Phase 0 findings

### Car handling

### Netcode feel

### Harder than expected

- `tar` under Git Bash is GNU tar and cannot extract to `C:\...` paths; `tools/get-godot.ts` calls System32 `tar.exe` on Windows.

### Recommendation

## Known issues

- Cover boxes are axis-aligned on slopes, so one corner digs in and the far end can lift (visual review, #7). Fine for greybox; align to the terrain normal when the real map arrives.
- The player capsule has no walk bob or sway, so movement is hard to read in captures. Arrives with weapon motion in Phase 1.

## Later

- Scenario tests step physics in real time (16 s for five player tests). Consider a faster physics tick or Engine.time_scale in tests once the suite grows.
