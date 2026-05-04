---
name: opera-browser-cli
description: Browser automation and web interaction using the opera-browser-cli tool. Use for navigating pages, clicking elements, filling forms, taking screenshots, inspecting console/network, running performance audits, and Opera Neon AI features (chat, invoke-do, make, research) when Opera Neon is the active browser.
---

# Skill: opera-browser-cli Browser Automation

`opera-browser-cli` controls a Opera browser browser session.

- **Standard commands** (`open`, `click`, `fill`, `screenshot`, etc.) — work with any Opera browser session.
- **Opera AI commands** (`chat`, `invoke-do`, `make`, `research`) — require **Opera Neon** with an active sign-in.

Run `opera-browser-cli --help` for the full command list, or `opera-browser-cli <command> --help` for per-command flags and examples.

```bash
opera-browser-cli open https://example.com   # start here — navigate and snapshot the page
```

If a user hits `Opera Neon: user is not signed in` or wants to use AI commands, suggest they run `opera-browser-cli setup` (interactive wizard) and sign in to Opera Neon. Run `opera-browser-cli doctor` to diagnose configuration issues.
