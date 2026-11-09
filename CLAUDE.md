@AGENTS.md

## Claude Code

The rules above are shared by every agent. Claude Code specifics:

- The playbooks in `.claude/skills/` load as the `godot-conventions` and `visual-review` skills; use them as skills.
- The maintainer works with the Saturate/agents skills: `/spec`, `/plan`, `/build` (incremental-implementation plus tdd), `commit`, `make-pr`, `evaluating-dependencies`. Specs and plans live in `~/.claude/specs/outpost/`, never in the repo; the game design doc is `~/.claude/specs/outpost/DESIGN.md`.
