# Slopocalypse

An open-world shooter you can play solo or with friends, built almost entirely by AI agents. It's an experiment in what happens when you let them just go: we see where it ends up and where the limits are. Anyone is welcome to help, with their own hands or their own models: see [CONTRIBUTING.md](CONTRIBUTING.md).

Right now it is a low-poly voxel world where the gear you carry out is the gear you can lose: a road through forests and mountains, a homemade car you build and mod, drones and guards, loot, outposts that keep your gear, and a dedicated server that decides everything. Where it goes next is up to the people working on it, so expect the game to change a lot.

Status: early and rough. Playable solo or with friends, nowhere near finished.

## Warning: this is slop

Almost every line here was written by AI agents, with a human steering, playtesting and saying "go on". That is the point. Slopocalypse is an experiment in what happens when you let agents just build a game: how far it gets, where it falls apart, and what it takes to keep the slop contained.

So expect odd code, uneven quality, features that are half there, and comments that are more confident than they should be. If you find something bad, you are welcome to fix it, by hand or with your own agent ([CONTRIBUTING.md](CONTRIBUTING.md) says how). Bad code is never a reason to feel bad about touching it.

The other half of the experiment is control: how much structure does it take before agent-written code stays workable? What we use so far:

- **One rulebook for agents.** `AGENTS.md` holds the architecture rules, commands and style, and `.claude/skills/` holds the Godot know-how and the traps we've already hit, so each new session starts from the same ground rules instead of guessing. It works with any agent: Codex, Cursor, Copilot, Gemini CLI and Aider read `AGENTS.md`, and Claude Code reads it through `CLAUDE.md`.
- **A gate that doesn't trust anyone.** `npm run check:full` must pass before anything merges. It runs every test, rebuilds every generated scene and fails if one changes, and scans the logs for engine errors, because Godot happily exits 0 after a script error.
- **Tests first.** Behaviour gets a failing test before the code, so "it works" means something.
- **Small, deletable modules.** Each feature lives in its own folder and talks to the rest only through events, and the gate boots the game with every optional module off. Slop stays local, and a bad module can be deleted.
- **Eyes that didn't write it.** Visual changes are captured to a contact sheet and judged by a fresh agent that never saw the code.
- **No magic numbers.** Gameplay values live in `data/`, so tuning doesn't mean digging through generated code.
- **One issue, one branch, one pull request.** Every change is small and traceable.

If you find better ways to keep agents honest, those are as welcome as features.

## Playing

Download the latest build for Windows, Linux or macOS from [Releases](https://github.com/Saturate/slopocalypse/releases), or build it yourself (below): `node tools/export.ts` makes a portable zip in `build/` you can hand to friends. The main menu has Play solo, Host a game and Join a friend.

## Building

You need Node.js 24, Rust (through rustup, the pinned version installs itself) and Git.

```sh
npm ci
node tools/get-godot.ts     # the pinned Godot 4.7.2 build, into tools/godot/
node tools/get-addons.ts
node tools/get-changesetter.ts   # versions and changelog
npm run check               # builds the Rust parts, imports, runs the fast tests
tools/godot/Godot_v4.7.2-stable_win64.exe --path .   # or your OS's binary in tools/godot/
```

### Running a server in Docker

The `Dockerfile` builds the whole dedicated server inside the container, so all you need is Docker and a checkout with the Git LFS files:

```sh
docker build -t slopocalypse-server .
docker run -d --name slopocalypse --restart unless-stopped -p 7777:7777/udp -v slopocalypse-data:/data slopocalypse-server
```

The world save, logs and journals live in the `/data` volume, so a rebuilt image keeps everyone's gear. Players join on UDP port 7777. For another port, add `--server=PORT --save=/data/world.db` after the image name and publish that port instead. To change game values, mount a file over `/opt/slopocalypse/tweaks/<res path>` (see `TWEAKING.md`).

`AGENTS.md` has every command, the architecture rules and the code style. It is written for coding agents but reads fine for people. `TWEAKING.md` lists the game values you can change without touching code.

## Contributing

Pull requests are welcome, whether you wrote the code yourself or your LLM did. Read [CONTRIBUTING.md](CONTRIBUTING.md) first: every change passes `npm run check:full`, and you agree to the [contributor licence agreement](CLA.md).

## Licence

The code is under the [GNU Affero General Public License v3.0 or later](LICENSE). You can use, change and share it, including on your own servers, as long as you share your changes under the same licence. If you run a modified server for other people, they are entitled to its source.

Third-party assets and libraries keep their own licences, listed in [assets/LICENSES.md](assets/LICENSES.md).

The name Slopocalypse and its logo are not covered by the code licence. Forks are welcome but need their own name; see [TRADEMARKS.md](TRADEMARKS.md).
