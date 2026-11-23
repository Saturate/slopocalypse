# 0019. Other bodies are posed less often far off or out of view

Status: accepted
Date: 2026-11-19
Issue or PR: #365

## Context
In the city a client draws 30 to 60 other bodies (players, soldiers, civilians), and each was
posed every frame: the body animator, its AnimationTree, the aim and hand IK modifiers. On an
M-series Mac that was about 4 ms of a 25 ms frame, most of it for figures too far off or
behind the camera for a fresh pose to show. The goal is 120 Hz (8.3 ms a frame).

## Decision
A body someone else steers is posed at a rate set by how far it is from the camera and
whether it is in view (`BodyLod`, `modules/player/data/body_lod.json`): every frame within
`near_distance` and in view, `mid_rate` and `far_rate` times a second further off,
`off_screen_rate` out of view. A scope's narrower field of view counts as coming closer. Its
AnimationTree and Skeleton3D run in manual mode and the body animator advances both, with the
time since the last pose, on the frames it is due. Movement is untouched: the body's position
is still smoothed every frame; only the pose holds between updates. Spawners opt bodies in
(`PlayerBodyAnimator.lod`); your own body never is.

## Alternatives
- `VisibleOnScreenNotifier3D` per body: uses the renderer's own culling, but signals a frame
  late and needs rendering, so it can't be tested headless. A frustum test from the camera's
  planes, worked out once a frame, costs about a microsecond a body.
- Switching modifiers off (`active = false`) far away: the aim and hands then snap back to the
  bare clip instead of holding the last pose.
- Lower rates for smoothing positions too: a moving body's position stepping would show; left
  every frame.

## Consequences
A body out of view holds its pose for up to 1/`off_screen_rate` s, so turning quickly can show
one frame of an older pose; its shadow animates at the lower rate too. The body animator's
profile zone now includes the AnimationTree's own work for opted-in bodies (it used to run
outside any zone), so compare whole frame time, not that zone alone, across this change.
Something that copies a body on a client gets a pose up to one interval old, and must switch
the copy's skeleton back to processing on its own: the ragdoll (`Corpse`) does, since its
physics simulator is a skeleton modifier. Between poses the skeleton holds the
modifiers' result only while nothing else sets its bone poses; a system that writes bone poses
on a living body must pose it through the animator instead.
