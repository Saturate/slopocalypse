# Changelog

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
