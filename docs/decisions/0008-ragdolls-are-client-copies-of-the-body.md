# 0008. Ragdolls are client-side copies of the body

Status: accepted
Date: 2026-11-19
Issue or PR: #130

## Context
The dead should fall as ragdolls. A soldier's node is freed `corpse_seconds` (12 s) after it
dies, a player's node lives on and respawns, and the searchable body (the inventory's
`LootBody`) is a separate server-spawned node that stays for minutes. The old dead body was a
figure of boxes with its own materials, a new shader variant on every client at the first
death, which a playtester's hitches on death pointed at (#373).

## Decision
On each client, `Corpse.from_body` copies the dying body's `Body` subtree (same meshes and
materials), drops what animates and arms it, poses it as it stood and adds physical bones
(`modules/player/data/ragdoll.json`) on the `DEBRIS` layer. It is pushed away from the killer,
simulates for `settle_seconds`, then keeps its pose without physics. A corpse and the
`LootBody` near where it fell find each other, whichever arrives first; the corpse hides the
box figure and goes when the `LootBody` goes. The server makes no corpses and syncs none.

## Alternatives
- Simulating the soldier's own skeleton: the node is freed long before the loot goes, and
  players' bodies respawn, so it would need keeping dead nodes alive on server and clients.
- Physical bones built into the body scene: every living body (up to 200 soldiers, on the
  server too) would carry a dozen idle physics bodies.
- A server-simulated, synced ragdoll: everyone sees the same pose, at the cost of sending
  bone transforms for every corpse; not worth it while corpses are cover for nobody.

## Consequences
Each client's ragdoll lands its own way (Jolt isn't deterministic across machines), so two
players can see a body lying slightly differently; the `LootBody`, where you search, is the
same for everyone. Corpses don't block movement or bullets. A death with no `LootBody` (nothing
carried) keeps its corpse `seconds_without_body`.
