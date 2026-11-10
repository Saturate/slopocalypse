# Changelog

## 0.4.0 - 2026-11-10

#### Watch your step: some missions have buried mines and tripwires across doors. Crouch to spot the glint, press F next to one to disarm it, or shoot it. New mission: the cabin in the woods

#### Soldiers feel fear: fire that passes close pins them down and spoils their aim, and depending on their nerve, their friends nearby and their wounds they fight, hold their ground, run, or throw down their gun and give up. They no longer shoot through walls or leaves

#### A trader at home base: sell anything you carry and buy gun parts, rigs, packs and medkits with your tokens (cheap for now while we playtest). Dying now costs everything you carried: you come back with nothing but your tokens

#### Soldiers take cover: under fire they run to the nearest spot that hides them, one at a time while the others keep shooting, then duck and pop up to fire. A soldier who spots you tells their squad

#### Guns are items: your rifle and pistol sit in their own slots, soldiers drop the rifle they carried (with its parts), and you can loot, drop, swap and buy guns. Lose them when you die

#### New mission kind, Clean Sweep: soldiers hold the buildings (sentries at the doors, more inside, patrols between); take them all down, the last few get marked, then ride home for the pay. Missions now have codenames like Operation Rusty Lantern, and the strike zone job is called Smash & Grab

#### Mission markers are subtle now: a small faint diamond with the distance, fading out as you get close so you find the last bit yourself

#### New mission kind, Ghost Run: the drive is in the best-guarded building and there is no clock, so sneak in or fight your way in, then ride home with it

#### Releases include a macOS build (Apple silicon and Intel); it is not notarised, so open it the first time with right-click > Open

#### Releases include a macOS build that runs on Apple silicon and Intel Macs

#### Items in your inventory show pictures of the real thing, rendered from their 3D models, and medkits, rigs, packs and the drive have proper models when they lie on the ground

### Internal

#### Privacy policy and terms of use

#### Release and export build macOS on macos-15 runners

## 0.3.0 - 2026-11-10

#### The start tunnel is home base: pick a job at the mission board, ride out in the parked car to the drop-off down the road, and ride home from the car waiting there

#### Mission zones have buildings you can walk into: the drive is inside one, the others hold loot crates, and strike drones go for their roofs

#### Strike zones get bombed: once the clock starts, drones come in waves and dive into the zone, more as time runs out and nonstop once it has. Shoot one, or fire near them, and they come for you

#### Gear has slots now: wear a rig and a backpack, each with its own grid, plus pockets; loot bodies' rigs and packs (a full pack comes with what is in it). Saved inventories are reset

#### The dead keep their gear on their body: search a body or a crate with F to open a loot screen with your backpack and theirs side by side, then drag items across, Ctrl+click to send one over, or take all

#### Drones no longer spawn inside hills or chase you from under the ground, and a crash's smoke and explosion play out even when you are not looking

#### Missions have a goal: walk into the strike zone to start the clock, grab the drive from its crate, and ride home with it to get paid in tokens (shown top left, kept between sessions)

#### Missions pay in tokens

## 0.2.1 - 2026-11-09

Fixed the game grinding down and closing some time after you killed soldiers: it kept trying to forget their guns every frame. Thanks to LOLIVER for the report and the logs that found it.

### Internal

#### Release notes group features, fixes and changes under the hood.

## 0.2.0 - 2026-11-09

#### The game no longer logs script errors when some event handlers finish very quickly.

#### Press F3 for live performance numbers; every game and server also writes a performance log.

#### Servers no longer hitch when enemies spawn, and shooting the ground no longer gets slower over a long session.

#### The game no longer fills its log with a missing back_to_spawn key error every frame.

Felled trees break with a splintered stump, crumple when they land and slowly dry out to bare branches.

### Internal

Nothing players will notice: every pull request is checked on Linux, Windows and macOS, and releases build in GitHub Actions.

#### Nothing players will notice: pull requests merge after the local gate; CI checks Linux and macOS.

#### Nothing players will notice: benchmarks report cost per frame and catch smaller hitches.

#### Developers can benchmark the game with tools/bench.ts.

#### Developers and agents can inspect a running game live with --debug-api and the MCP server.

## 0.1.0 - 2026-11-09

#### Servers can run from a Docker image, with the world save kept in a volume.

### Internal

Releases come with ready-made Windows and Linux downloads and a server image.

Nothing players will notice: the tooling uses changesetter 0.5.2.

Nothing players will notice: the tooling uses changesetter 0.5.1.

#### The game has a version number and a changelog now. The version shows in the main menu after the first release.
