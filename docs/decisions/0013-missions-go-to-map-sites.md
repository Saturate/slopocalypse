# 0013. Missions go to the map's sites

Status: accepted
Date: 2026-11-21
Issue or PR: #404

## Context
Missions used to happen at a point along the highway, with their own buildings beside the
road. The generated map now has sites (farms, cabins, radio masts, lookouts, water towers),
each with a pad, a yard and a dirt track to the road network. A mission should pick a place
in the world that fits it rather than bring its own.

## Decision
- Each template in `missions.json` names the site kinds it may use (`sites`), with `any` for
  every kind and `roadside` for a spot beside the highway. An offer picks, from the server's
  seed, an unused site of those kinds whose distance from the camp falls in the template's
  range. With none, the template goes roadside if it allows it (or the map has no sites,
  as on the flat test world), else it is not offered this time.
- Distance is measured as the crow flies from the camp to the site's centre. The ride out
  is a fade, so the way by road is never felt, and a straight line needs no search over
  the road network.
- The zone centres on the site; mission buildings, guards, mines and signs stand round it,
  off its pad and yard, off roads and tracks and out of water. The site's ground is never
  reshaped: since #501 a building's pad is at the site's own level, so it stands right at
  the pad's edge (where the ground lies within `level_step` of that level), and a fence
  runs round the site and its buildings with a gate where the track leaves, so the whole
  reads as one guarded place. Every machine works the fence out from the offer, the
  buildings and the map; nothing about it is sent.
- The group is set down on the site's own track, `dropoff.outside` metres outside the zone,
  found by walking down that track from the site. A track too short for that carries on
  along the road it meets. The car parks beside the way there, facing the site. The site,
  or the track up to it, is in view, and the zone (and any clock) starts a short walk on.
- The objective goes into a mission building, never a site building: site buildings are
  voxel kit pieces owned by the sites module, with no interior spots, damage or loot API.
- Offers carry what they need of the site (centre, footprint, the drop-off worked out), so
  clients lay out the same zone without the site list.

## Alternatives
- Distance along the roads: closer to what a drive would be, but nobody drives it, and it
  needs a route search over roads and tracks that join each other mid-way.
- Drop-off where the track meets the road: true to "the ride ends on a road", but tracks run
  up to 900 m, so the walk was long, short tracks put the drop-off inside the zone, and a
  track joining another site's track set the group down by the wrong site.
- Objective in a site building: reads better for the cabin, but ties missions to the sites
  module's layouts and needs crate spots and damage in kit pieces.

## Consequences
- Templates' distance ranges are in map-scale metres (up to about 2 km); a template whose
  kind is missing or out of range on a map is simply not offered.
- Sites are not persisted or damaged across missions yet (#422); whatever a mission breaks
  is its own buildings.
- Revisit if players get a real drive out (then road distance and a drop-off at the road
  matter), or when danger comes from remoteness (#205).
