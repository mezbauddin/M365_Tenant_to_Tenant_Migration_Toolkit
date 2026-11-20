# Maintainer session on mez-claude-01

> **Owner:** Mezba Uddin · **Last meaningful update:** 2026-11-20

**TL;DR:** The toolkit has its own Claude Code session on mez-claude-01, in tmux window `m365` of session `main`, with Remote Control on, so it shows at claude.ai/code as **M365 T2T toolkit**.

## First session on mez-claude-01

```bash
ssh claude01                                   # auto-attaches to tmux 'main'
tmux new-window -n m365
cd ~/Documents && [ -d M365_Tenant_to_Tenant_Migration_Toolkit ] || git clone git@github.com:mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit.git
cd ~/Documents/M365_Tenant_to_Tenant_Migration_Toolkit && git pull
claude --remote-control "M365 T2T toolkit"
```

Detach with `Ctrl-b d`.

## If it drops

- Disconnected from the browser: run `/remote-control` inside the session.
- Process stopped (for example after a reboot): in window `m365`, run `cd ~/Documents/M365_Tenant_to_Tenant_Migration_Toolkit && claude --continue --remote-control`.
