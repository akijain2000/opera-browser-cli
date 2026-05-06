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

## Canonical source files

When asked how a command works or how to extend the CLI, read the actual source — don't guess from the README:

- `src/cli.ts` — command parsing and dispatch (`opera-browser-cli <command>`).
- `src/client.ts` — HTTP client for the bridge plus bridge lifecycle (start, stop, health, PID file at `~/.opera-browser-cli/bridge.pid`).
- `src/bridge.ts` — persistent HTTP ↔ MCP adapter; spawns `opera-devtools-mcp` as a child over stdio.
- `src/snapshot.ts` — accessibility-tree parsing and `uid=` ref extraction.
- `src/suggestions.ts` — the `help[]` next-step hints emitted with every response.

For setup, install, or first-time bootstrap, read `bootstrap-prompt.md` and `README.md`. For architecture (transport model, streaming, concurrency), read `CLAUDE.md`.
