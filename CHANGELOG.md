# Changelog

## 0.12.0 - 2026-11-24

### slopocalypse

#### The F3 overlay and the benchmark results show where each frame's time goes: scripts, physics, rendering and the rest, with the shadow passes counted apart

#### A belt-fed machine gun: 100 rounds, hits hard, sprays standing and shoots tight crouched on its bipod, but it is slow to draw, reload and aim, and you walk slower with it out. Find it in crates or at the trader.

#### Servers use far less CPU while nobody is near: soldiers and civilians far from every player stand still until someone comes within 360 m

#### Rounds passing close to you now pin you down: the screen edges darken, the view jolts and a crack snaps past with each near miss, and your own aim gets wider until the fire lets up. The shake can be turned off in Settings (Screen shake under fire).

#### The glowstick, charge and set-off hints at the bottom left show their keys (L, K, G, T) instead of a question mark

#### Walking or driving into new ground no longer stutters while trees, grass and roads appear

#### Soldiers and drones around your car keep showing up however far you drive from where you got in

#### Crowds of soldiers and civilians cost less frame time: those far off or out of view are animated a few times a second instead of every frame

#### Settings has a "Colour-blind colours" switch: armbands become blue, white, vermillion, amber and pink, which stay apart with red-green colour blindness, and every band in the world changes at once

#### Missions at farms, cabins and masts are one fenced compound: the huts stand close round the site and a fence with a gate on the track rings the lot

#### Everyone wears a coloured armband on both upper arms: blue for co-op players, green for civilians, red or their faction's colour for soldiers, readable at night too

Soldiers think a few times a second instead of every tick, reacting like people do, so the server keeps up when the city fills with fighting.

#### Joining a server no longer freezes the game while the map builds; a loading card shows instead

#### Your own glowstick no longer floods your gun and the ground at your feet with colour, and a dropped glowstick now shows as a stick lying on the ground

#### Your co-op partners have a small blue marker over them with their name and distance, seen through walls, so you can find them in a fight or at night

#### Driving into new ground no longer stalls the game for a moment while the ground is built

#### Steep hillsides step in uneven ledges with green sides instead of a black pegboard, and potholes are shallow dips in the asphalt

#### Glowsticks: find or buy one, press L to crack it and it glows on your chest in your armband colour for five minutes (L again stows it, K drops it); some soldiers on night patrol carry one too

#### Distances on the compass no longer print over each other when three markers bunch up

#### Some militia and regulars squads bring a machine gunner, who keeps firing at the cover you ducked behind for a few seconds while the rest of the squad moves up

#### You can't shoot or aim while climbing a ladder, your gun drops out of view while you climb, and you no longer catch a ladder you fall past fast or appear beside in mid-air

### Internal

#### A client with no window builds the ground round the car it drives, not where it got in.

#### Save smoke prints what each server did with the save when it fails

#### Windows opened by the capture, playtest, bench and trailer tools no longer take the keyboard on macOS

#### Trailer shots: staged scenes with a moving camera, a blocked-view check and stills

#### A sleep test no longer races the sleep sweep.

#### Playtests, debug API calls and player settings now live in the module that owns them

#### Brain sleep test no longer races the first sweep

#### Decision records get their own numbers

#### The city benchmark's walker can no longer be shot, so it measures the walk.

#### World state test waits on the clock while the map builds

#### Scripted playtests can walk, shoot, hurt players, find the ground and change a client's settings; a new playtest covers dying and switching guns with a lit glowstick

#### The map API test waits on time instead of a frame count.

#### Scripted playtests (tools/play.ts) drive a real server and clients, check state and hand screenshots to a blind reviewer

#### Headless playtest clients build the ground and scenery round their own player, and scenarios about what is drawn are skipped in headless runs

## 0.11.0 - 2026-11-22

### slopocalypse

#### Server hosts can keep the web page for an HTTPS proxy on the same machine: `--web-bind=127.0.0.1` (or `WEB_BIND`), with `WEB_PORT` beside `--web-port` for Docker, and `tools/deploy.ts --web`

#### Water towers stand by the farms and in the towns of the map, and farms and other sites are no longer overgrown with trees and rocks.

#### On the generated map (--world=map), roads have their asphalt and lines and every site its dirt track, worn more the further out they are

#### High-voltage pylons cross the countryside between the city and the towns, and wooden poles carry power along roads to farms.

#### Other players are seen climbing ladders instead of falling past them.

#### Mission buildings no longer flatten a road they stand beside. Trees felled before this update stand again.

#### A server's save remembers which world it is for; a save for another world is set aside (world.db.old-...) and a fresh one starts

#### The credits name the people who sent in pull requests.

#### On the generated map the city stands on its own levelled ground where the highway arrives

#### The road is in good repair near the camp and the city and gets more worn and potholed the further out you drive

#### Joining a server, your game builds the same world the server plays (the generated map included); no extra option needed

#### Server admin: the map viewer fills the window, zooms in to real detail, and has zoom buttons, a scale bar and a legend; /admin goes straight to it

#### You start and respawn in a fenced camp with a hut, the mission board and the trader inside; soldiers and drones leave you alone in there. The map changed under the camp, so a save for the old map is set aside and a fresh one starts.

#### Getting shot no longer fills your view with a pale blob.

#### The server's status page shows the kill board: soldiers, drones, players and civilians killed, deaths, headshots and the longest kill, and the top five players

#### Linux servers and games load the world in seconds again instead of minutes, without climbing to several GB of memory

#### Dirt tracks no longer show grass rings and dark holes; tracks run on as packed dirt up to the buildings at farms, cabins and lookouts; site tracks wind less, and sites too far from a road are left out.

#### Joining on a slow computer no longer drops you while the world loads.

#### Farms, cabins, radio masts and lookout towers stand on the map's sites; climb a lookout tower's ladder to its deck.

#### The generated map can be played with --world=map (recipe and seed with --map= and --seed=): you start at its camp with the car beside you

#### Shots, hits and footsteps vary a little in pitch and loudness each time, so repeated sounds feel less mechanical; recorded sounds can now be dropped in beside the generated ones.

#### Gentle hills are smooth instead of terraced, dirt tracks blend into the grass, and farm yards are worn into the ground.

#### Joining a server while someone is in the car shows them in it, not standing where they got in.

#### The gun and its sight keep their size on screen at any field of view: a wider view in Settings (or the sprint widening) brings the gun nearer instead of shrinking the sight picture

#### The Benchmark from the main menu ignores your keyboard and mouse, so every run is the same, and its results have a Copy summary button for sharing the numbers

#### Missions send you to the map's farms, cabins and towers instead of a spot by the highway.

#### Trees, rocks and grass load in squares around you instead of long rows across the world; felled trees from older saves stand again

#### The generated map is now the world you play: you start at its camp, with its city, roads, tracks and countryside

#### A compass strip along the top of the screen shows north, the mission objective, the cars, the camp and your co-op partners by name, with distances; turn it off in Settings

### Internal

#### Review fixes for the contributor batch: car bot from menu args, scope clamp note, deploy web flag checks, late join smoke waits for the seated driver, compass base at the camp centre

#### Capture setups start at the camp on the generated map.

#### World generation (not played yet): farms, water towers, antennas, lookouts and lone cabins placed by zone and remoteness in the map preview

#### World generation (not played yet): every site stands on a level pad with a dirt track to the nearest road

#### Decision record: the generated map becomes the played world

#### Wires can hang between two points as sagging power lines, barbed wire and steel cable (nothing in the world uses them yet)

#### The test gate runs the GDScript suites in parallel and waits for clients before a test server stops.

## 0.10.0 - 2026-11-20

### slopocalypse

#### A shot water tower leaks in thin streams that fall by its legs instead of spraying like a fire hose.

#### Joining a server no longer puts you inside a parked car, and leaving while driving saves you beside the car.

#### Items on the ground are drawn bigger, lie flat with their names above them, and the one you would pick up glows

#### The server's web page has an admin app behind its password, starting with the server's status.

#### Server admins can look at world-generation maps in the admin page: pick a recipe and seed, toggle layers, try changed numbers

#### The bolt-action rifle fits in the backpack now.

#### Mission sites no longer land in the city, and the city keeps clear of the road where it bends.

#### A street now leads from the road into the city on levelled ground, and city streets no longer swallow your feet.

#### Joining a server on a different game version now says which version the server runs, instead of joining with missing effects

#### Search a body where its ragdoll lies; the floating Body label is gone.

#### When joining a server fails, the menu lists what to check: address and port, the UDP port on the server's firewall, your own network, and a VPN as a way round

#### Cars shove people out of the way instead of stopping dead, and hurt them when they hit fast.

#### New players start with 50 tokens instead of 150; the first missions pay for the rest.

#### Server admins can set WEB_PASSWORD to open admin pages on the server's web page; the status page stays public.

#### Craters are shallow bowls with walls you can walk out of, even on a hillside; they are as wide as before.

### Internal

#### World generation: city, towns and the players' camp placed on the land (not played yet).

#### Decision record 0010: world generation makes the land first, then places settlements and roads that shape it.

#### World generation: ponds where water collects in the low ground (not played yet).

#### World generation: road heights within their grade, tunnels and bridges marked (not played yet).

#### World generation (not played yet): roads cut into hills and settlements on level pads in the map preview

#### A local map viewer for tuning world generation.

#### The Windows export builds the admin web app through Node instead of npm.cmd

#### World generation: the land of a map from a recipe (not played yet).

#### tools/server.ts passes arguments after -- to the game

#### World generation: the land read as zones, with a city spot and a spawn (not played yet).

#### World generation: biomes on the new land, woods on the hills and open lowland (not played yet).

#### World generation: roads routed between the camp, the city and towns (not played yet).

#### World generation: a second, hillier map recipe (not played yet).

#### World generation: a map preview tool, and broad lowland with rounded hills (not played yet).

## 0.9.0 - 2026-11-19

#### Press F8 (or Report a bug in the Esc menu) to save one file with a screenshot, your logs and machine details to send us

#### Starting a session no longer freezes for a moment while soldiers fill the map

#### Frames are about 30% quicker near other players and soldiers (measured in the city): your machine no longer runs their movement as well as the server

#### Players who join at the same moment start side by side instead of being flung off the spawn together

#### The heavy rifle's support hand holds the handguard instead of hovering just off it

#### Tapping crouch while sprinting no longer stacks slide boosts into absurd speed

#### Smoother frame rate near the city and buildings: each voxel building is drawn as a few big pieces instead of hundreds of small ones

#### The dead fall as ragdolls, pushed away from whoever shot them

#### Blasts can tear arms, legs or heads off the dead, and a hard killing shot to a leg or arm sometimes does too; the piece flies off bleeding (off with Blood in Settings)

#### Shots draw blood: hits spray out of the far side and mark the wall behind, and pools spread under the dead (turn it off with Blood in Settings)

#### Turning while sprinting follows your new direction straight away instead of sliding

#### A bolt-action rifle: hard-hitting 7.62 rounds, a 5 round magazine and an 8x scope, and you work the bolt after every shot. Find it in crates, buy it from the trader, or take it off the marksmen some squads now bring

#### Benchmark in the main menu: a fixed one-minute run that shows your frame rate and worst stutters, and saves a report you can send us

### Internal

#### The gate retries Godot's import once when the engine crashes during it

## 0.8.0 - 2026-11-18

#### The city has people: unarmed civilians stroll near their front doors and run for cover or crouch when shooting starts. Killing them counts in your stats

#### Every in-game screen (inventory, trader, modding, mission board, admin) now uses the same steel look and readable text sizes, and the trader's stock scrolls instead of running off the screen

#### Your kills are counted: soldiers by faction, players, drones, headshots, your longest kill and your deaths, kept with your save and shown under Stats in the Esc menu

#### Each faction remembers how you've treated it: kill their soldiers and they hate you more, kill their enemies and they warm to you, and once they're no longer hostile their squads let you pass. See your standing from the Esc menu

### Internal

#### Benchmarks: a city walk scenario, GPU and draw-call numbers; --start=city puts you down in the city

#### Nothing players will notice: a missing script id file is committed, and a test keeps them all committed so CI stays green

## 0.7.0 - 2026-11-17

#### A cleaner HUD: health and ammo are a number and a thin line that fade back when you're fine, the screen edges pulse red when you're low, a red arc shows which side a hit came from, ammo turns amber when the magazine runs low, and the HUD gets out of the way when you die

#### The title screen shows the city at golden hour behind the menu, the camera drifting slowly down an avenue

#### Settings, from the title screen or the Esc menu: mouse sensitivity, field of view, volume, interface size, fullscreen and your own keys, saved between games

#### The game opens on a title screen: the logo and the main choices down the left, your name in the corner, and hosting and joining friends on their own screen

#### Soldiers now belong to three factions, each with its own uniform and kit, and rival factions fight each other on sight

#### Esc closes the screen on top first (modding over the inventory closes modding), clicks on the admin panel no longer grab the mouse, and the Esc menu is called Menu since the world keeps running

#### The title screen has a What's new card with the latest changes, a full changelog, and credits for the people, agents and open-source parts behind the game

#### The interface has a new look: worn steel panels, a stencil heading font and amber highlights, and it now scales with the window so menus fit at 720p and text is bigger at 1080p

#### Soldiers guard the city: at upper-floor windows, on flat roofs, at street corners and on patrol round the blocks

#### The city mixes in hand-made blocks: a market in the square, courtyard gardens and a ruined block

#### Prompts like Search crate, Trade and Ride out stack neatly under the crosshair instead of overlapping, and every key hint shows the key you actually have bound

#### Fixed the mouse barely turning the view in game, mostly at low frame rates. Thanks to LOLIVER for the report

#### Craters, felled trees, shot-out lamps and holed water towers now stay after a server restart, and players who join later see the craters too

### Internal

#### Nothing players will notice: fresh checkouts import cleanly again, so CI and release builds work

## 0.6.0 - 2026-11-17

#### The asset library's GPU voxels switch draws models straight from their voxels on the graphics card

#### The asset library has a generated Danish apartment block: choose floors, stairwells, elevators, balconies, brick and roof, with furnished flats of different sizes inside

#### The city's street fronts are whole buildings with arched gateways into the courtyards, in brick and white, grey and ochre render, along pale streets with kerbs, zebra crossings, street lamps and trees

#### Rounds and blasts splash and ripple ponds, craters beside a pond fill with water, and cars stall in deep water

#### Street lamps light the road at night, and you can shoot their bulbs out

#### Blasts and drone crashes leave smoke that drifts with the wind, and soldiers can't see you through it

#### Ponds beside the road: wade through the shallows, swim in the deep part (no shooting while you swim)

#### Apartment blocks beside the road that you can walk into: through the front door, up the stairs, into the flats; and you walk up stairs and kerbs without jumping

#### Servers send about a third of the data they did, so games with more soldiers stay smooth on slower connections

#### Window frames, door trim and roof edges come down with the wall behind them instead of hanging in the air

#### Ponds look better: green-teal water with drifting waves, a light shore and glints

#### A small European city off the road: perimeter blocks of brick apartments round courtyards, streets with pavements, and an open square in the middle

#### Other players, soldiers and drones move smoothly instead of stepping from one network update to the next

#### Bullet holes, knocked-out bricks and broken walls look exactly the same for every player, including friends who join after the shooting

#### A water tower by the road: shoot its tank and water pours from every hole and puddles under it

#### Soldiers and drones far from you are no longer sent to you, so busy servers use a fraction of the bandwidth

#### Soldiers see and shoot through windows; cracked security glass hides you, and a broken pane leaves a real opening

#### Up to 200 soldiers roam the map at once, spread out in squads instead of gathering near the start

#### A thermal scope shows soldiers, players and drones bright white through smoke; buy it from the trader or find it on soldiers

### Internal

#### Decision record for maps as recipes of stitched sites

#### A destruction table test and a per-subject capture: every breakable sample takes a ladder of hits, from one round to a 6 m blast

#### Hand-made city blocks: a block format, an editor tool to build them, and three first blocks

#### The destruction table test now fails if any hit takes the server more than 100 ms

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
