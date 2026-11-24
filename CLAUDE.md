# Claude context: M365 tenant-to-tenant migration toolkit

> Front door for any Claude session in this repo. **Read this first.** This file is an index; the detail lives in the linked docs.

## What this is

A **public** toolkit (MIT) of PowerShell scripts and planning documents for moving a business from one Microsoft 365 tenant to another, in the order it's done. One spine of numbered parts (`01` to `10`, plus `02b`, `tools`) and three copy options (`copy-options/A`, `B`, `C`). Built from a real small-business migration.

**Current status:** toolkit version 1.5.0 (24 Nov 2026). Option B (ShareGate) and part 08 (devices) used live; options A and C not yet lab-verified. Version history: the Changelog table in [`README.md`](README.md#changelog).

## Where to start, by task

| You're trying to... | Read |
| --- | --- |
| Pick up from last session | [`docs/runbooks/journal/current.md`](docs/runbooks/journal/current.md) |
| See what's next | [`docs/plan/today.md`](docs/plan/today.md), then [`docs/plan/backlog.md`](docs/plan/backlog.md) |
| See what's undecided | [`docs/plan/open-questions.md`](docs/plan/open-questions.md) |
| Understand the toolkit and its order | [`README.md`](README.md), then [`docs/Cutover-Runbook.md`](docs/Cutover-Runbook.md) (the canonical order) |
| Change a script | That part's `README.md` (TL;DR, why, gotchas, its own version table) |
| Write or restyle a doc | [`docs/conventions/docs-style.md`](docs/conventions/docs-style.md) |
| Find a past decision | [`docs/architecture/decisions/`](docs/architecture/decisions/README.md) |
| Anything else | [`docs/README.md`](docs/README.md) |

## Branching

**`main` only.** Commit straight to `main` and push at once. Detail: [`docs/conventions/branching.md`](docs/conventions/branching.md).

## Hard rules (one line each, detail at the link)

- **The repo is public.** No client names, tenant IDs, domains, addresses, passwords or script output, ever. Examples use generic names (Contoso, Fabrikam) ([docs-style](docs/conventions/docs-style.md#public-repo))
- **No AI attribution** anywhere: no Co-Authored-By lines, session links, "generated with" footers or mentions of Claude in commits, docs or code ([docs-style](docs/conventions/docs-style.md#public-repo))
- **Script output never goes in git.** `.gitignore` blocks `*.csv`, `Inventory-*/`, `TargetBuild-*`; keep it that way
- **Published doc and folder names stay put.** People link to them; rename only with a redirect note ([ADR-0001](docs/architecture/decisions/ADR-0001-adopt-mezcloud-layout-additively.md))
- **Every change bumps versions:** the script's `.NOTES` version, its part README's version table, and the top README Changelog when the toolkit changes ([docs-style](docs/conventions/docs-style.md#versions))
- **Anything that changes a tenant takes `-WhatIf`** and checks the tenant ID first (`-AdminUpn`), as the existing scripts do
- **Never run a script against a real tenant from this machine** unless Mez asks; there are no tenant credentials here

## Quick checks

```bash
git status --short                                       # nothing stray, no CSVs
git log -5 --format=%B | grep -iE 'co-authored-by|claude.ai/code'   # should print nothing
```
