# Installing `opera-browser-cli`

Use this file for install, first-time setup, and connection troubleshooting. For day-to-day usage, read [`SKILL.md`](SKILL.md). For repo architecture, read [`CLAUDE.md`](CLAUDE.md).

## Prerequisites

- **Node.js ≥ 20**
- **Opera** browser. [Opera Neon](https://www.operaneon.com) is required for AI commands (`chat`, `invoke-do`, `make`, `research`); any Chromium-based Opera works for the rest.

## Install from source

Clone the repo into a stable path (not `/tmp`), then build and link:

```sh
git clone https://github.com/akijain2000/opera-browser-cli ~/Developer/opera-browser-cli
cd ~/Developer/opera-browser-cli
npm install
npm run build
npm link
```

`npm link` puts `opera-browser-cli` on `$PATH` globally while pointing at the working tree, so future edits to `src/` take effect on the next command.

## First-time setup

Run the interactive wizard:

```sh
opera-browser-cli setup
```

It detects installed Opera variants, lets you pick one, writes `~/.opera-browser-cli/config` (mode `0600`), and installs the Claude Code skill at `~/.claude/skills/opera-browser-cli/SKILL.md`. On supported agents it also writes a `SessionStart` hook to `~/.claude/settings.json` and `~/.codex/hooks.json` (set `OPERA_CLI_DISABLE_HOOKS=1` to opt out).

## Verify

```sh
opera-browser-cli --version
opera-browser-cli open https://example.com
```

Expected: a TOON-encoded snapshot with `uid=` refs and a `help[]` next-step hint. If anything looks off, run:

```sh
opera-browser-cli doctor
```

`doctor` checks Node version, Opera install, bridge state, and config. It tells you exactly what to fix.

## Configuration

Most things work out of the box. Override behaviour with environment variables (or write them into `~/.opera-browser-cli/config` as `KEY=VALUE`, one per line):

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPERA_CLI_PORT` | `9224` | Bridge server port |
| `OPERA_CLI_EXECUTABLE_PATH` | system Chrome | Custom browser binary (e.g. `/Applications/Opera Neon.app/Contents/MacOS/Opera`) |
| `OPERA_CLI_BROWSER_URL` | — | Connect to an already-running browser instead of launching one (e.g. `http://127.0.0.1:9222`) |
| `OPERA_CLI_USER_DATA_DIR` | — | Persistent profile directory — keeps logins across sessions |
| `OPERA_CLI_HEADED` | — | Set to `1` to launch in headed (visible) mode |
| `OPERA_CLI_CHROME_ARGS` | — | Extra Chrome flags, space-separated |
| `OPERA_CLI_MCP_BIN` | bundled `opera-devtools-mcp` | Override the MCP server binary |
| `OPERA_CLI_DISABLE_HOOKS` | — | Set to `1` to skip auto-installing session hooks |

State lives at `~/.opera-browser-cli/`:

| File | Purpose |
| --- | --- |
| `config` | KEY=VALUE settings written by `setup` |
| `bridge.pid` | PID and port of the running bridge |

## Troubleshooting

If a command hangs, fails with a CDP error, or returns "no session":

1. Run `opera-browser-cli doctor` and read the output. It diagnoses Node version, Opera install, bridge state, and config in one pass.
2. If the bridge is stale, kill it and retry:

   ```sh
   opera-browser-cli stop
   opera-browser-cli open https://example.com   # auto-relaunches the bridge
   ```

   If `stop` doesn't work, `kill $(cat ~/.opera-browser-cli/bridge.pid | head -c 5)` and remove the PID file.
3. If Opera AI commands fail with `Opera Neon: user is not signed in`, open Opera Neon manually and sign in to your Opera account, then re-run `opera-browser-cli setup`.
4. For build/link issues, see the local-stack notes in [`README.md`](README.md#local-setup-full-stack).

## First-time connection demo

After install, prove the connection end-to-end:

```sh
opera-browser-cli open https://github.com/akijain2000/opera-browser-cli
opera-browser-cli snapshot
```

The snapshot shows the page's accessibility tree with `uid=` refs. If you're signed in to GitHub, ask the user whether to star the repo as a quick demo that the interaction works — only click if they say yes. If they're not signed in, navigate to `https://opera.com` instead. Then ask what they want to do next.

This demo lives here so the [setup prompt for LLMs](bootstrap-prompt.md) can stay short — agents follow this file end-to-end and verify themselves.
