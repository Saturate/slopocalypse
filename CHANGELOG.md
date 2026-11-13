# Changelog

## 0.5.0 - 2026-11-12

#### Buildings break: drone dives, mines and blasts knock holes in walls and roofs you can walk and shoot through

#### Servers have a status page: open http://<server>:7777 in a browser to see who is on, the mission that is running and the board (also as /status.json)

#### Rounds go through plank walls, sheet metal and glass and hit whoever is behind, for less damage (at most two walls); brick and concrete stop them, and a round into a hole you made goes straight on

#### On the test range you're set down across the road from the buildings, and no drones or soldiers turn up

#### Shoot single bricks out of a brick wall: a few rounds into the same brick knock it out, leaving a hole you can see and shoot through, and a wall that loses most of its bricks gives way

#### Glass breaks like glass: a window pane goes on the first round in big shards, security glass stops rifle rounds and cracks white until its twelfth hit, and a blast takes any pane out at once

#### Fewer hitches while new ground, trees and rocks load in as you travel

#### Windows are see-through, and a hit that knocks nothing loose only puffs a little dust instead of throwing chunks

#### Broken walls come loose: pieces tumble out as chunks of themselves and lie on the ground for a while instead of vanishing, and blasts knock brick walls apart brick by brick

#### Broken glass lies on the ground as shards of the pane, and rubble no longer doubles up or freezes in mid-air

#### The car's wheels spin as it rolls, the front ones steer, and each rides its spring over bumps and dips

#### Hits depend on what they strike: rounds leave holes in wood, chip brick and concrete, and throw debris in the colour of what they hit; brick and concrete walls need a charge, and a wooden frame no longer makes a concrete wall easy to break

#### The mission transport is a proper voxel off-roader with a roof rack instead of a stack of boxes

#### Brick houses are built of real bricks: each brick its own block in mortar joints, laid in a running bond, and the mortar chips more easily than the brick

#### Hits and breaks sound like what they hit: a knock on wood, a ping off metal, glass tinkling and shattering, brick and concrete cracking and crumbling, and a rumble when part of a building comes down

#### Buildings collapse: knock out the walls under a roof and it comes down, hurting anyone underneath

#### Bricks stick together: a brick you knock out sometimes takes a neighbour or two with it, loose mortar crumbles away so holes open clean, and shooting the joints loosens the bricks beside them

#### Shooting a wall makes holes where you hit it; a wall piece only gives way once most of it is shot away, instead of a whole slab flying out after a few rounds

#### The test range has its own flat world: a level plain with nothing else on it, loading at once

#### The test range is a row of labelled wall samples on flat ground: planks, brick, concrete, sheet metal, four kinds of glass, and mixed walls with windows and doors

#### Debris from breaking walls, craters and trees flies out with random speed, angle and tumble instead of a neat even burst

#### New players start with 150 tokens to spend at the trader

#### Rocket launcher: a slow, heavy tube that fires one rocket a load, which flies with a smoke trail and blows walls apart; mind the backblast. On sale at the trader, and on the test range

#### Soldiers go round walls to reach cover behind them instead of standing pressed against the wall in plain view

#### Bullet holes in building walls show up the moment you shoot, without the short delay or a hitch

#### Broken walls fall apart into ragged pieces (whole bricks stay whole) that tumble down and lie still where they land, the same for everyone, with no sliding into place at the end

#### Softer wind that rises and falls in gusts with an occasional rustle of leaves, instead of a constant hiss; mission and test range houses are bigger

#### Soldiers no longer crouch at the very end of a wall where you can still see them

#### Buildings feel their weight: a piece carrying more than it can gives way, so a house won't stand on one corner and whatever it held comes down with it

#### Wood and concrete: bullets punch holes in wooden walls and can break them, while concrete blockhouses only chip and need a blast or a breaching charge

#### Test range: "Test range" in the main menu (or node tools/range.ts) takes you to a row of buildings, one per material, to shoot and blast; the HUD names the material you're aiming at

#### Voxel models and the ground darken in their cracks, seams and inside corners, so shapes read better at any distance

#### Rubble stays: the chunks a wall breaks into settle where they land and stay as solid rubble, the same for everyone, that you can hide behind or climb

#### Mission buildings stand on level ground: the slope is dug in or built up under each one, easing back into the hillside, so none is half buried any more

#### Breaching charges: G sticks one on whatever you aim at, T sets off all of yours. Blow holes in walls and roofs, or shoot a charge to set it off. Sold by the trader, found in crates, and you start with two

### Internal

#### Voxels carry a material (wood, glass, sheet metal, brick, concrete); building rules move to one materials file

#### Trailer pipeline: scripted shots rendered with Godot's Movie Maker and joined with ffmpeg

#### Decision records in docs/decisions and a rule to question existing patterns before copying them

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
