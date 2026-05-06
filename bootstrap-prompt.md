# Bootstrap prompt for LLMs

Hand this prompt to any AI agent (Claude Code, Cursor, Codex) as their first message. The agent installs, verifies, and demos the CLI without further prompting.

```
Set up https://github.com/akijain2000/opera-browser-cli for me.

Read install.md and follow the steps to install opera-browser-cli and connect it to my browser.
```

That's it. [`install.md`](install.md) covers prerequisites, install, setup, verify, configuration, troubleshooting, and a first-time connection demo — agents follow it end-to-end.

If your agent benefits from extra anchors, append:

```
Then read SKILL.md for day-to-day usage. Always run `opera-browser-cli --help`
for the canonical command list, and follow the `help[]` hint that prints after
every command.
```

When the install flow or the canonical files change, **update [`install.md`](install.md) first** — this prompt and the README's "For LLMs" section should re-publish from there.
