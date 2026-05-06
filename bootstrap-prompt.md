# Bootstrap prompt for LLMs

This is the canonical one-shot prompt for handing this repo to an LLM (Claude Code, Cursor, Codex, etc.). Copy the fenced block below and paste it into a fresh AI session — the agent will install, verify, and demo the CLI without further prompting.

---

```
Set up https://github.com/akijain2000/opera-browser-cli for me.

1. Clone the repo into ~/Developer/opera-browser-cli (a stable path — not /tmp).
   If the directory already exists, `git pull --ff-only` instead of re-cloning.

2. cd into the repo and install:

       npm install && npm run build && npm link

   `npm link` puts `opera-browser-cli` on $PATH globally while pointing at the
   working tree, so future edits to src/ take effect on the next command.

3. Run the interactive setup wizard:

       opera-browser-cli setup

   It detects installed Opera variants, lets the user pick one, writes
   ~/.opera-browser-cli/config (mode 0600), and installs the Claude Code skill
   to ~/.claude/skills/opera-browser-cli/SKILL.md. Opera Neon is recommended if
   AI commands (chat, invoke-do, make, research) are wanted.

4. Read the canonical files in this order:
   - README.md            command reference and install flow
   - SKILL.md             skill behaviour for AI agents
   - CLAUDE.md            architecture overview (bridge transport, streaming,
                          concurrency model)

   Always read these source files — they are where the actual logic lives:
   - src/cli.ts           command parsing and dispatch
   - src/client.ts        HTTP client + bridge lifecycle (start/stop/health)
   - src/bridge.ts        persistent HTTP ↔ MCP adapter

5. Verify the install:

       opera-browser-cli --version
       opera-browser-cli open https://example.com

   Expect a TOON-encoded snapshot with `uid=` refs and a help[] hint.

6. Connection demo (do this once after install):

       opera-browser-cli open https://github.com/akijain2000/opera-browser-cli
       opera-browser-cli snapshot

   If the user is signed in to GitHub (the snapshot will show their avatar /
   profile menu), ask whether to star the repo as a quick demo that the
   harness works. Only click the star if they say yes. If they are not signed
   in, navigate to https://opera.com instead.

If anything looks off at any step, run `opera-browser-cli doctor` to diagnose
configuration. If the bridge appears stale, kill the PID at
~/.opera-browser-cli/bridge.pid and retry — the next command relaunches it.
```

---

## Why this prompt exists

`browser-use/browser-harness` ships a "Prompt for LLMs" button on its landing page that copies a single self-contained bootstrap prompt to clipboard. Users hand that prompt to their AI agent and the agent gets from zero → working harness in one session, without the user having to read docs themselves.

This file is the equivalent for `opera-browser-cli`. Three places it should appear:

1. Here, as the canonical source.
2. In `README.md` under the **For LLMs** section, fenced for copy-paste.
3. (Optional) On a future landing page, behind a "Prompt for LLMs" button that copies it to clipboard.

When the prompt changes (new install steps, new canonical files, breaking CLI flag changes), update **this file first** — README and any landing page should re-publish from here.
