# ADR-0001: Adopt the MezCloud layout additively

> **Owner:** Mezba Uddin · **Last meaningful update:** 2026-11-20

**TL;DR:** The maintainer docs follow the mezcloud-homelab layout, but they are added around the published toolkit. No published file or folder is renamed or moved.

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

The repo was already public, with 66 commits, numbered part folders, PascalCase document names in `docs/` and a Changelog table in `README.md`. People link to those paths. Mez's standard layout uses kebab-case names, a `CHANGELOG.md` and `docs/<domain>/` folders.

## Decision

- Add `CLAUDE.md` and the maintainer folders `docs/plan/`, `docs/runbooks/`, `docs/architecture/decisions/` and `docs/conventions/`.
- Keep the published documents (`docs/*.md`) and part folders where they are, with their current names.
- Keep the Changelog table in `README.md` as the canonical version history; no separate `CHANGELOG.md`.

## Consequences

- External links keep working.
- Two naming styles live side by side: PascalCase for published documents, kebab-case for maintainer docs.
- The maintainer folders are public too, so they follow the public-repo rules in [docs-style](../../conventions/docs-style.md#public-repo).

## Alternatives considered

- **Full restructure to kebab-case and `docs/<domain>/`:** breaks every link in posts and bookmarks, for no gain to readers.
- **A separate private repo for the maintainer docs:** keeps plans private, but splits one project across two repos. Revisit if plans ever need client detail.
