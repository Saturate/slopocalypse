# 0006. Remote things are shown a moment in the past

Status: accepted
Date: 2026-11-17
Issue or PR: #321

## Context
Clients wrote each server update straight onto other players, soldiers and drones. Updates
come once a server tick but arrive unevenly, and screens faster than 60 Hz draw several frames
per update, so remote movement stepped and jumped. Clients don't simulate remote bodies
(physics is off for them), so there is nothing between updates to show.

## Decision
A client keeps the recent updates of each smoothed thing, stamped with when they arrived, and
shows it `smooth_delay` (0.05 s) in the past, blended between the two updates either side;
angles blend the short way. If updates stop it carries on for up to `smooth_extrapolate`, then
holds. A jump longer than `smooth_snap_distance` is a teleport and shows at once. Only the
properties a synchronizer sends every tick are smoothed. A module opts a node in with the meta
`net_smooth` when it spawns it (`NetSmoothing` in `core/`, added on clients only); your own
player and cars don't opt in, so nothing you steer lags.

## Alternatives
- Server timestamps on every update: blends to exact server times instead of arrival times,
  so a burst of late packets doesn't speed things up. Costs a synced value per thing and a
  clock estimate; worth it if bursts show in playtests.
- Extrapolation only (no delay): no added lag, but every wrong guess shows as a correction.
- Running remote bodies' physics on clients: they'd still need correcting toward the server.

## Consequences
Remote things are drawn about 50 ms further in the past than before, on top of the connection's
own delay, so moving targets need a little more lead until hits are lag compensated. Anything a
client sets directly on a smoothed property (outside its synchronizer) is overwritten each
frame; set it on the server instead, or teach `NetSmoothing` about it. Cars and your own
movement (prediction) are separate work.
