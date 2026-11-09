# Contributing

Thanks for helping. Code written by you, by an LLM, or by both is all welcome; you are responsible for what you submit either way.

## Before you start

- Look at the open issues. Each piece of work has one; comment on it, or open a new one for your idea, so two people don't build the same thing.
- Read `AGENTS.md`. It holds the architecture rules (modules, server decides and clients replay, no magic numbers, scenes from builders) and the commands. Any coding agent works: most read `AGENTS.md` on their own (Claude Code through `CLAUDE.md`). The playbooks in `.claude/skills/` cover Godot conventions and visual review; Claude Code loads them as skills, other agents can read them as plain Markdown.

## Making a change

1. Branch from `main` as `issue-<number>-<short-slug>`.
2. Write a failing test first wherever the behaviour is testable, then make it pass.
3. Add a changeset: `tools/changesetter/changesetter add --package slopocalypse --bump patch -m "What changed, for players"`. Use `--bump none` for tooling, docs and tests, `minor` for new features. It ends up in `CHANGELOG.md` when the maintainer releases, so write it for players.
4. Run `npm run check:full`. It must pass locally before you push; the `check` workflow then runs the same gate on Linux, Windows and macOS for your pull request.
5. For anything visible, attach a screenshot or short clip to the pull request.
6. Open a pull request that references the issue and says how you tested it and what is still rough. The template asks for these.

Keep a pull request to one issue. Ask in the issue before adding a dependency, changing the save or journal format, or changing the architecture rules.

## Say who made it

Issues and pull requests say who wrote them: a person, or which model in which tool and how much a person steered it. The templates have a field for it, agents add a `Made by:` line (the rule is in `AGENTS.md`), and the `by:human` and `by:agent` labels make it filterable (GitHub only lets maintainers set labels, so the `Made by` line is what counts). Nobody is judged for using an agent; it's part of the experiment to see what people and models each do.

## Licence and the CLA

The project is under the AGPL-3.0-or-later. By opening a pull request you agree to the [contributor licence agreement](CLA.md): you keep the copyright to your work and it stays available under the AGPL, but you also give the maintainer the right to release it under other terms. That is what makes releases on stores and platforms that don't accept AGPL code possible (Steam's SDK, consoles).

If you can't agree to that, say so in the issue before you start.
