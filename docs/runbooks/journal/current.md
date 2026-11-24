# Journal: November 2026

> **Owner:** Mezba Uddin · **Last meaningful update:** 2026-11-24

**TL;DR:** What happened on the toolkit, newest first. Rolls over to `2026-11.md` at the start of December.

## 2026-11-24

- Added `10-Decommission/Remove-SourceLicences.ps1` 1.0.0 (toolkit 1.5.0): pick-list of licences, removes them from source users, skips break-glass, enabled accounts and mailboxes on hold, optional group licences, and a per-subscription billing step (cancel inside 7 days, else turn off recurring billing). No Graph API cancels a directly bought subscription, so billing stays by hand. Smoke-tested with mocked Graph (dry run makes no changes; group removal skipped with `-Users`); not yet run against a real tenant.
- Root README header showed 1.3.0; now 1.5.0.

## 2026-11-20

- Cloned to mez-claude-01 at `~/Documents/M365_Tenant_to_Tenant_Migration_Toolkit` and given a Claude Code session (`M365 T2T toolkit`, Remote Control on) in tmux window `m365`.
- Added the maintainer layout: `CLAUDE.md`, `docs/plan/`, `docs/runbooks/`, `docs/architecture/decisions/`, `docs/conventions/`. No published doc, script or folder moved ([ADR-0001](../../architecture/decisions/ADR-0001-adopt-mezcloud-layout-additively.md)).
