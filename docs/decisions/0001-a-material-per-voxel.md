# 0001. A material per voxel

Status: accepted
Date: 2026-11-12
Issue or PR: #248, #281

## Context
Hits, blasts and breaking need to know what was struck. A building used to have one material
for all of it, so a wooden window frame in a concrete wall took hits like concrete, and glass
could not behave like glass.

## Decision
Every filled voxel stores a material index (u8) next to its colour. The materials and their
rules (bullet and blast factors, holes, pass-through, glass breaking, bricks, density,
strength) live in one data file, `modules/voxkit/data/materials.json`; the index is a position
in that list, so new materials go at the end. What a round leaves comes from the struck voxel;
how much a wall piece suffers comes from the piece's main (non-joint) material.

## Alternatives
- A material per building or per wall piece: simpler, but mixes (frames, panes, bricks in
  mortar) can't work.
- Material by colour: fragile, and colours vary for looks.

## Consequences
Every voxel model can carry materials at a byte per cell. Indices are positional, so reordering
the file would change every model: append only. Bullet holes are carved with floats on each
machine, so copies can drift slightly until #251 makes edits exact integer operations.
