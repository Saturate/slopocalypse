# Changelog

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
