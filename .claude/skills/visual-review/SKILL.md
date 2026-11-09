---
name: visual-review
description: Captures Slopocalypse gameplay to a PNG contact sheet and has a fresh subagent, which never sees the code, judge it against the stated goal. Use after any change that affects what the game looks like or how something moves on screen (terrain, player, car, weapons, effects, UI), when asked to "look at it", "check visually", "screenshot", or before calling a visual task done. The author of a change does not judge its visuals in the same session.
metadata:
  author: Saturate
  version: "1.0"
---

# Visual review

The agent that built something is a poor judge of how it looks: it sees what it meant to build. This skill separates capture from judgement.

## 1. Capture

Each module keeps capture setups in `modules/<id>/capture/*.gd`: a script extending `Node3D` that builds the scene, places a camera, and drives intents over time (see `modules/player/capture/walk.gd`). Then:

```bash
node tools/capture.ts --setup res://modules/<id>/capture/<name>.gd --out screenshots/<name>.png --frames 120 --sheet 6
```

- `--frames` is how long to run at a fixed 30 fps; `--sheet` how many evenly spaced frames go into the grid (1 for a single screenshot).
- It opens a real window for a few seconds; headless Godot renders nothing.
- `screenshots/` is git-ignored.

## 2. Write the goal

One or two sentences of what a viewer should see, written before looking. Example: "A capsule walks forward and turns right across rolling green terrain, casting a shadow, never sinking into the ground or floating, passing wooden cover boxes that sit on the ground."

## 3. Blind review

Spawn a fresh subagent with the Agent tool. Give it only the image path and the goal, never code, file names of scripts, or your own opinion:

```
Look at <absolute path to png>. It is a contact sheet of frames in time order, left to right,
top to bottom, from a low-poly 3D game prototype (grey-box art is expected).
Goal: <goal>.
Report: (1) the single largest gap between the images and the goal, (2) any blocking defect
(clipping, floating, missing shadows, black or inverted surfaces, wrong scale, nothing moving),
(3) anything that looks unintentional. Be concrete about which frame. Do not suggest code.
```

## 4. Act on it

- Blocking defects: fix, recapture, review again with a new subagent.
- Non-blocking notes: add to `NOTES.md` under "Known issues" or "Later".
- Report the reviewer's findings to the user in the task summary, with the PNG path.
