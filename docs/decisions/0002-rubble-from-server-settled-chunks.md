# 0002. Rubble is the broken voxels, settled by the server

Status: accepted
Date: 2026-11-12
Issue or PR: #279, #297, #301, #302

## Context
Broken wall pieces vanished, then came loose as client-only chunks that sank away. Rubble that
matters (cover, something to climb, the same for everyone) needs one answer to where it lies,
but full physics replication of hundreds of chunks is costly.

## Decision
A broken piece splits into chunks by a fixed rule, and each chunk's throw comes from a seed
(building, piece, chunk), so the server and every client start the same chunks moving the same
way. Clients fly theirs for the look; the server flies its own, and once they have had time to
land it freezes them and sends each resting transform. Everyone freezes theirs there, easing
the last bit, as solid rubble (glass shards lie there but stop nothing). Late joiners rebuild
the chunks from the building as built. A client drops any chunk of a piece the server did not
mention.

## Alternatives
- Client-only debris that sinks: cheap, but leaves nothing to fight around and differs per
  player.
- A made-up heap per piece placed by the server: deterministic and cheap, but not the voxels
  that broke (tried and dropped in review).
- Replicating every chunk's transform each tick: exact, but bandwidth grows with destruction.

## Consequences
One small message per settle. Clients may see a chunk glide a little at the end, where their
physics disagreed with the server's. The server runs short-lived rigid bodies after breaks.
Revisit if chunk counts climb into the thousands per zone.
