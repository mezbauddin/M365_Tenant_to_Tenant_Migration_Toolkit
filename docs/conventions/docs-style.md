# Docs style

> **Owner:** Mezba Uddin · **Last meaningful update:** 2026-11-20

**TL;DR:** Plain British English, sentence case, no em dash. Every published doc and part README opens with a TL;DR and explains why it exists and what goes wrong without it. The repo is public.

## Writing

- British English, sentence case headings, never the em dash character.
- Part READMEs keep their pattern: TL;DR, why you need it, what goes wrong without it, how to run it, gotchas from a live migration, version table.
- Maintainer docs (`docs/plan/`, `docs/runbooks/`, `docs/architecture/`, `docs/conventions/`) start with a title, the owner line and a TL;DR.
- Relative links, Mermaid diagrams. Split files above about 400 lines.

## Public repo

- No client or business names, tenant IDs, domains, addresses, people's names other than the author, passwords or script output.
- Examples use generic names (Contoso, Fabrikam, contoso.com).
- No AI attribution: no Co-Authored-By lines, session links, "generated with" footers or mentions of Claude, in commits, docs or code.

## Versions

- Each script carries its version in its comment-based help `.NOTES`.
- Each part README has a version table; add a row for every change.
- A change to what the toolkit offers adds a row to the Changelog in `README.md` and updates the version in its header table and in `docs/README.md`.

## Canonical docs

| Topic | Canonical doc |
| --- | --- |
| The order of the whole migration | [docs/Cutover-Runbook.md](../Cutover-Runbook.md) |
| What no tool moves | [docs/What-Doesnt-Move.md](../What-Doesnt-Move.md) |
| Lessons from live runs | [docs/Lessons-Learnt.md](../Lessons-Learnt.md) |
| Toolkit version history | [README.md, Changelog](../../README.md#changelog) |
| Open work | [docs/plan/backlog.md](../plan/backlog.md) |
| Decisions | [docs/architecture/decisions/](../architecture/decisions/README.md) |
