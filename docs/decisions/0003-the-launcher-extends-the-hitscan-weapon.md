# 0003. The rocket launcher is a HitscanWeapon subclass, for now

Status: accepted, to be superseded by #303
Date: 2026-11-12
Issue or PR: #300, #303

## Context
Guns are built from parts, and the weapons module equips every drawn gun as a `HitscanWeapon`.
The launcher needed fire rules, recoil, the HUD and the part system, but a different discharge.

## Decision
The launcher is a receiver part with `projectile: true`; the weapons module gives such guns the
`RocketLauncher` script, a `HitscanWeapon` subclass that overrides `server_fire` to launch a
`Rocket` and lash a backblast.

## Alternatives
- Split the gun into fire rules plus a discharge chosen from data (#303): the right shape, but a
  refactor of every gun touchpoint; done separately so the launcher could be played with first.
- A separate launcher item outside the gun system (like the charge thrower): no part system, no
  shared HUD or recoil, duplicated rules.

## Consequences
A launcher "is a" hitscan weapon in code, which is false; anything that checks for
`HitscanWeapon` treats it as one. The next discharge kind should not add another subclass:
do #303 first.
