`opera-browser-cli` is a thin agent-ergonomic CLI that wraps `opera-devtools-mcp` to control a Chromium-based browser session via DevTools Protocol.

# Code priorities

- Clarity
- Token economy (TOON encoding, in-band `help[]` hints, accessibility-tree refs)
- Low-friction install (`npm link` + `setup` wizard)
- Versatility — both standard browser automation and Opera Neon AI commands

# File responsibilities

Core code lives in `src/`:

- `cli.ts` — command parsing and dispatch (`opera-browser-cli <command>`)
- `client.ts` — HTTP client to the bridge plus bridge lifecycle (start, stop, health, PID file)
- `bridge.ts` — persistent HTTP ↔ MCP adapter; spawns `opera-devtools-mcp` over stdio
- `snapshot.ts` — accessibility-tree parsing and `uid=` ref extraction
- `suggestions.ts` — the `help[]` next-step hints emitted with every response
- `hooks.ts` — auto-installer for Claude Code / Codex `SessionStart` hooks
- `run.ts` — multi-step script execution (`opera-browser-cli run <`)

Bin entrypoints are in `bin/`:

- `opera-browser-cli.ts` — main CLI binary
- `opera-browser-cli-bridge.ts` — bridge server binary (calls `runBridge`)

# Doc responsibilities

- `README.md` — usage reference for humans browsing GitHub
- `install.md` — install, setup, configuration, troubleshooting, first-time demo for agents bootstrapping
- `SKILL.md` — day-to-day usage rules for agents already installed
- `CLAUDE.md` — architecture (bridge transport, streaming, concurrency)
- `bootstrap-prompt.md` — the canonical one-shot prompt to hand any LLM
- `specs/*.md` — planned and in-progress fixes; check before starting implementation work

# Contributing

Consider what is really needed. Prefer the smallest diff that fixes the bug. Tests live in `test/` (vitest); new commands or behaviour changes require coverage there.
