# Installing `opera-browser-cli`

Use this file for install, first-time setup, and connection troubleshooting. For day-to-day usage, read [`SKILL.md`](SKILL.md). For repo architecture, read [`CLAUDE.md`](CLAUDE.md).

## Prerequisites

- **Node.js ≥ 20**
- **Opera** browser. [Opera Neon](https://www.operaneon.com) is required for AI commands (`chat`, `invoke-do`, `make`, `research`); any Chromium-based Opera works for the rest.

## Install from source

Clone the repo into a **stable path** — not `/tmp`, `/var/folders`, or any tempdir. macOS aggressively reaps `/tmp` on reboot and the SessionStart hook this repo installs (see step 3) will end up pointing at a vanished binary. If a clone already exists in a tempdir, delete it after the new clone is in place.

```sh
git clone https://github.com/akijain2000/opera-browser-cli ~/Developer/opera-browser-cli
cd ~/Developer/opera-browser-cli
npm install
npm run build
npm link
```

`npm link` puts `opera-browser-cli` on `$PATH` globally while pointing at the working tree, so future edits to `src/` take effect on the next command.

**Verify the binary landed on PATH:**

```sh
command -v opera-browser-cli
# Expected: a path under ~/.nvm/, /usr/local/bin/, or your global node_modules.
# NOT expected: /tmp/..., a path inside the source tree, or empty output.
```

If `command -v` returns nothing, `npm link` didn't succeed — check the npm output for permission errors and re-run.

## First-time setup

Run the interactive wizard:

```sh
opera-browser-cli setup
```

It detects installed Opera variants, lets you pick one, writes `~/.opera-browser-cli/config` (mode `0600`), and installs the **Claude Code skill** at `~/.claude/skills/opera-browser-cli/SKILL.md`. On supported agents it also writes a `SessionStart` hook to `~/.claude/settings.json` and `~/.codex/hooks.json` (set `OPERA_CLI_DISABLE_HOOKS=1` to opt out).

> **Caveat — Codex skill is NOT auto-installed.** The wizard only copies `SKILL.md` to the Claude Code skills directory. If you also use Codex, copy it yourself:
>
> ```sh
> mkdir -p ~/.codex/skills/opera-browser-cli
> cp SKILL.md ~/.codex/skills/opera-browser-cli/SKILL.md
> ```
>
> This will be fixed in a future release (see [`RECOMMENDATIONS.md` Part 2.3](RECOMMENDATIONS.md) — multi-host auto-detection). Until then, the manual copy is the workaround.

**Verify the SessionStart hook points at the linked binary, not the source:**

```sh
grep -A1 'opera-browser-cli' ~/.claude/settings.json
# Expected: "command": "<path returned by `command -v opera-browser-cli`>"
# NOT expected: a /tmp/... path, or a path inside ~/Developer/opera-browser-cli/dist/.
```

The hook should match `command -v opera-browser-cli`. If it points at the dist directory directly or at a tempdir, edit `~/.claude/settings.json` and replace the `command` value with the npm-linked path. The link survives `npm rebuild` and uninstalls cleanly via `npm unlink`; a direct dist path does not.

## Verify

Three checks. All three should pass before you call the install done.

**1. Binary works:**

```sh
opera-browser-cli --version
opera-browser-cli open https://example.com
```

Expected: a TOON-encoded snapshot with `uid=` refs and a `help[]` next-step hint.

**2. Skill landed in every agent's skills directory you use:**

```sh
ls ~/.claude/skills/opera-browser-cli/SKILL.md
ls ~/.codex/skills/opera-browser-cli/SKILL.md  # only if you use Codex
```

Both paths should print without a "No such file" error. The first is created by `setup`; the second requires the manual copy step above.

**3. Restart your agent.** Skills don't hot-reload — Claude Code, Codex, and Cursor all need to be restarted before a freshly-installed skill becomes invokable. After restart, `opera-browser-cli` should appear in the agent's available-skills list.

If anything looks off at any check, run:

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

### Runtime issues

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

### Install issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `command -v opera-browser-cli` returns nothing | `npm link` failed silently | Re-run `npm link` from the repo root; check for permission errors in the output |
| Skill doesn't appear in agent's skills list after restart | `SKILL.md` wasn't copied to the right directory, or the agent wasn't restarted | Check `ls ~/.claude/skills/opera-browser-cli/SKILL.md` (or `~/.codex/skills/...`) — copy manually if missing, restart the agent |
| SessionStart hook fails on every Claude session | Hook points at a path that no longer exists (e.g. `/tmp/...`) | `grep -A1 opera-browser-cli ~/.claude/settings.json` — replace the `command` value with the output of `command -v opera-browser-cli` |
| `npm install` ran in a tempdir like `/tmp/opera-browser-cli` | The clone is in volatile storage that the OS will reap | Re-clone into a stable path (`~/Developer/`, `~/src/`, etc.); re-run `npm install && npm run build && npm link`; update the SessionStart hook |
| Skill appears in Claude but not Codex | The wizard only auto-installs the Claude skill | Manually copy: `mkdir -p ~/.codex/skills/opera-browser-cli && cp SKILL.md ~/.codex/skills/opera-browser-cli/SKILL.md` |
| Bridge starts but `opera-browser-cli open` hangs | Bridge process is alive on a stale port | `opera-browser-cli stop && opera-browser-cli doctor`; if the doctor shows port mismatch, set `OPERA_CLI_PORT` and re-run |

## First-time connection demo

After install, prove the connection end-to-end:

```sh
opera-browser-cli open https://github.com/akijain2000/opera-browser-cli
opera-browser-cli snapshot
```

The snapshot shows the page's accessibility tree with `uid=` refs. If you're signed in to GitHub, ask the user whether to star the repo as a quick demo that the interaction works — only click if they say yes. If they're not signed in, navigate to `https://opera.com` instead. Then ask what they want to do next.

This demo lives here so the [setup prompt for LLMs](bootstrap-prompt.md) can stay short — agents follow this file end-to-end and verify themselves.
