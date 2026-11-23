# 0018. Layer 19 is your own first-person arms and gun

Status: accepted
Date: 2026-11-23
Issue or PR: #447

## Context
Your own glowstick is clipped to your chest, a hand's width from the gun you hold in first
person. A light there falls off with the square of distance, so the gun and arms took many
times the light the ground did and filled the lower screen with flat, saturated colour. Lowering
the light's energy until the gun looked right left the ground unlit; moving the light away from
the chest still kept the gun nearer to it than anything else in view.

## Decision
Render layer 19 (`RenderLayers.FIRST_PERSON`) holds your own arms and whatever they hold, in
first person, and nothing else: `PlayerBody.first_person()` adds a `FirstPersonLayer` node that
moves the arms mesh and every mesh under the weapon attachment onto it, gear given later
included, and off every other layer. A light near your eye leaves the layer out of its cull
mask. Your own glowstick does this and adds a faint, even light that lights only that layer, so
the gun still shows the stick is lit. Everyone else's view of you is unchanged: your body on
their screen is not first person and keeps its usual layers. Decals skip the layer, like layer
20, and gore's clean-keeping leaves it alone. Your ragdoll moves back to layer 20.

## Alternatives
- A lower energy or gentler falloff for your own light only: the gun is always the nearest
  thing to it, so the gun stays the brightest thing on screen at any energy that lights the
  ground.
- Leaving layer 20 (bodies) out of your own light: your gun is only on layer 20 while gore is
  on, and people standing next to you would go unlit on your screen.
- A separate viewport for the view model: a large change to cameras, depth and post effects for
  one light.

## Consequences
Any light that sits at your own body (a future torch or muzzle light on your own gun, seen by
you) can leave the layer out the same way. A camera or light that sets a cull mask has to keep
layer 19 in, or your own gun vanishes or goes unlit; new decals that spare people should skip it
too. Only your own stick leaves the layer out: a partner's stick right next to you still
lights your gun with its usual steep light. A mesh moved out of your hands into the world (none
is today; dropped guns are built fresh) would keep layer 19 and has to be moved off it.
