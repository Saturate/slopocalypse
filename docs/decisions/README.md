# Decisions

Short records of choices that shape how a system works, so the next person (or agent) knows
why it is the way it is, what else was considered, and when to revisit it. One file per
decision, numbered, never renumbered.

Write one when a change picks a shape others will build on: a data model, an authority split
between server and clients, a module boundary, a pattern copied into new places. Not for
naming or small refactors.

Status is one of: **accepted** (in force), **open** (a question we know we have not settled),
**superseded by NNNN**.

```markdown
# NNNN. Title in a few words

Status: accepted | open | superseded by NNNN
Date: YYYY-MM-DD
Issue or PR: #N

## Context
What forced a choice, in a few sentences.

## Decision
What we do, specifically.

## Alternatives
What else was on the table, and why not (or why not yet).

## Consequences
What this makes easy, what it makes hard, and what would make us revisit it.
```
