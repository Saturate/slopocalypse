# 0005. Rubble is seeded fragments with worked-out falls

Status: accepted
Date: 2026-11-12
Issue or PR: #279, supersedes 0002

## Context
Rubble has to lie in the same place for everyone (it is cover) and look like the wall that
broke. 0002 ran physics on the server and on each client and eased each client's chunks into
the server's resting places, which showed as a glide at the end; it also cut pieces on a
grid, so chunks were squares. Physics engines don't give the same answer on two machines even
from the same start, so a shared seed can't make physics agree.

## Decision
Seed everything and use no physics for it. A broken piece cracks round seed points from the
building's seed and the piece's number (`VoxelModel.fracture` in the Rust core: nearest seed
with noise for ragged edges, bricks kept whole). Each fragment's throw, tumble (whole turns)
and resting place (lying on its thinnest side, at a seeded heading, on level ground) are
worked out from its own seed, and every machine animates that path. Pieces split in ascending
order, each carved out before the next, so pieces sharing edge voxels split the same way.
Late joiners lay the same fragments straight at rest from the entry's `broken` and `fallen`.
Nothing about rubble is sent.

## Alternatives
- Physics with corrections (0002): looks live, but disagrees and needs a correction step.
- Deterministic fixed-point physics: the real fix for agreeing simulations, far too big.
- Synthetic heaps: deterministic, but not the voxels that broke (dropped earlier).

## Consequences
Fragments don't bounce off each other or the building and land on the level pad round the
building, so on rough ground beyond it they can float or sink a little. Bullet holes carved
with floats can make a live split differ slightly from a late joiner's until #251 makes edits
exact. Costs one fracture per broken piece, no network traffic.
