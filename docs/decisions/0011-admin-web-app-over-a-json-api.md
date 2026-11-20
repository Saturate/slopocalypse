# 0011. The server's admin is a React app over a versioned JSON API

Status: accepted
Date: 2026-11-20
Issue or PR: #448

## Context
The dedicated server already answers HTTP on its game port with a public status page
(`modules/web`). The maintainer wants map tools on it (the world-generation viewer, a live
map of the played world) behind a password, and later more admin tools. Building each page as
HTML strings in GDScript does not scale past a status page, and the maintainer asked for "a
small api between game and a react frontend".

## Decision
- The game serves a small **versioned JSON API** under `/api/v1/...`. Public routes (status)
  need nothing; admin routes need `WEB_PASSWORD` (HTTP basic auth, guesses limited per
  visitor, admin POSTs only as same-site JSON). The game never renders admin HTML itself.
- The **contract** is `modules/web/api/openapi.yaml`. The frontend's TypeScript types are
  generated from it (`npm run api-types -w web`, openapi-typescript), and API answers are
  checked by type guards before use; no casts.
- The **frontend** is `web/`, React + Vite + TypeScript (strict), an npm workspace of the
  repo. It builds into `modules/web/static` (git-ignored), which the export includes and the
  server serves under `/admin/app/` behind the password: one URL, one login. The Docker image
  builds it in a stage of its own; `tools/export.ts` builds it before exporting.
- The gate typechecks and builds it.

## Alternatives
- **More GDScript-built pages:** no new dependencies, but every view is string templating
  with no types and no reuse; the map viewer already needed a canvas, pan, zoom and forms.
- **A separate admin service** (Node next to the game): richer, but a second process to
  deploy and secure, and it would still need an API into the game.
- **Preact, Svelte or no framework:** smaller or simpler, but the maintainer chose React for
  familiarity and ecosystem.

## Consequences
Easy: new admin views are React components over typed API calls; the same app can run against
a local render server for world-generation tuning. Hard: the repo now has a frontend toolchain
(npm workspace, Vite) that releases and the Docker build must run, and the API must stay
backwards compatible within `v1`. Revisit if the admin grows past what the game process
should serve (heavy renders, many concurrent users).
