# Recommendation: a self-improving knowledge layer for `opera-browser-cli`

**Author:** Akshat Jain
**Date:** 2026-05-06
**Audience:** `opera-browser-cli` engineering @ Opera
**Status:** Proposal — not implemented

## TL;DR

`opera-browser-cli` is a polished CLI: TOON encoding, in-band `help[]` hints, accessibility-tree refs, persistent bridge, vitest coverage, release-please automation. Its weakness vs. [`browser-use/browser-harness`](https://github.com/browser-use/browser-harness) is **knowledge accumulation**: there is nowhere for an agent to deposit what it learns about a site so future runs benefit. browser-harness ships ~90 agent-written per-site playbooks plus 17 reusable mechanic playbooks; we ship none.

This doc proposes adding three structural pieces — `agent-workspace/`, `interaction-skills/`, and CLI surfacing of those skills on `open` — to close that gap without touching the existing CLI ergonomics.

The companion install-docs restructure (see PR linked at the end) is a prerequisite for this to land cleanly. That PR is small and shippable now; the work in this doc is bigger and benefits from team discussion first.

## Background — what browser-harness actually does

browser-harness is described as "a thin self-healing harness." The "self-healing" part is doing real work. Anatomy of the repo:

| Layer | Path | Editable by | Purpose |
|---|---|---|---|
| Core | `src/browser_harness/` | maintainers | Daemon + CDP wrapper + CLI. ~1k LOC across 4 files. |
| Agent helpers | `agent-workspace/agent_helpers.py` | the agent at runtime | Empty by design. Slot for task-specific Python helpers the agent writes mid-session. Auto-loaded by core. |
| Interaction skills | `interaction-skills/*.md` | maintainers | 17 reusable mechanic playbooks: dialogs, dropdowns, iframes, screenshots, scrolling, shadow DOM, tabs, uploads, viewport, network requests, drag-and-drop, cookies, downloads, print-as-pdf, profile sync, cross-origin iframes, connection. |
| Domain skills | `agent-workspace/domain-skills/<host>/*.md` | the agent at runtime | ~90 per-site playbooks. Filed by the agent itself when it figures something non-obvious out. Surfaced by `goto_url` when `BH_DOMAIN_SKILLS=1`. |

A domain skill is not "here's how to scrape" — it is field-tested gotcha capture. Sample from [`agent-workspace/domain-skills/github/repo-actions.md`](https://github.com/browser-use/browser-harness/blob/main/agent-workspace/domain-skills/github/repo-actions.md):

> The visible Star button looks like `button[aria-label^="Star "]`, but that selector has two gotchas on the modern repo header:
>
> - There are two matching buttons. The first one `querySelector` returns is a hidden fallback inside the sticky sub-header form with `getBoundingClientRect() == {x:0, y:0, w:0, h:0}`. Coordinate-clicking it does nothing because it has no geometry.
> - Synthetic `.click()` on the visible React button does not persist the star. The click fires, `aria-label` stays `Star ...`, network tab shows no POST. GitHub's component swallows the synthetic event somewhere in its React fiber handler.
>
> `form.submit()` sidesteps both problems — it bypasses React entirely and goes straight to the HTML form's POST.

The agent generated this. A future run on `github.com` reads the file, skips the click-vs-submit detour, ships in seconds instead of minutes.

The README is explicit about the philosophy:

> Skills are written by the harness, not by you. Just run your task with the agent — when it figures something non-obvious out, it files the skill itself. Please don't hand-author skill files; agent-generated ones reflect what actually works in the browser.

## What we have today

| File | Lines | Role |
|---|---|---|
| `README.md` | ~270 (after restructure) | Usage reference |
| `install.md` | ~100 | Install + setup + troubleshoot + first-time demo |
| `SKILL.md` | ~30 | Day-to-day usage rules |
| `CLAUDE.md` | 53 | Architecture |
| `AGENTS.md` | 25 | Agent contract |
| `bootstrap-prompt.md` | 15 | The 2-sentence setup prompt |
| `specs/*.md` | 2 files | In-progress fix specs |

No `agent-workspace/`. No `interaction-skills/`. No `domain-skills/`. The CLI itself is excellent — it's the surrounding knowledge graph that's empty.

## What we have that browser-harness doesn't

Worth listing so the comparison is fair. These should not regress:

- **In-band `help[]` hints** in `src/suggestions.ts`. Every command response ends with the agent's next-step suggestion. browser-harness has nothing equivalent — agents have to remember helpers or re-read source.
- **TOON encoding** for ~40% token savings vs raw JSON.
- **Accessibility-tree refs** (`@1`, `@2`) — the CLI hands the agent stable handles instead of asking it to read pixels.
- **Persistent bridge** — one MCP client shared across CLI invocations. browser-harness has the daemon model but it's per-name.
- **vitest test coverage** — 14 test files. browser-harness has tests but they're lighter.
- **Session hooks auto-installer** — writes `SessionStart` hooks to `~/.claude/settings.json` and `~/.codex/hooks.json`. browser-harness asks users to do this manually via `install.md`.
- **release-please automation** — fully automated semver releases.

## Proposal

Three additions, each independently shippable. Order matters — A is the foundation, B and C build on it.

### A. `agent-workspace/` extension surface

Mirror browser-harness's `agent-workspace/` directory at the repo root:

```
agent-workspace/
  README.md                 contract: what goes here, who edits it
  snippets.md               empty by default; slot for agent-written command sequences
  domain-skills/            per-site playbooks (one folder per host)
    README.md
  interaction-skills/       reusable mechanic playbooks (one file per pattern)
```

`agent-workspace/snippets.md` is the equivalent of browser-harness's `agent_helpers.py`. It starts empty. Agents append known-good multi-command flows there as they discover them — e.g.:

> ### Submit a GitHub form bypassing React
> ```sh
> opera-browser-cli eval "(() => { const f = document.querySelector('form[action\$=\"/star\"]'); if (!f) return 'absent'; f.submit(); return 'submitted'; })()"
> opera-browser-cli wait 2000
> opera-browser-cli snapshot
> ```

The repo ships the directory empty (or with one starter example) and trusts agents to fill it.

### B. Seed `interaction-skills/` with high-value playbooks

Port 5–6 high-value playbooks from browser-harness, adapted for opera-browser-cli's shell shape. Suggested initial set:

- `dialogs.md` — `dialog accept` / `dialog dismiss` patterns; what to do when JS thread freezes; when to use `eval` to stub `window.alert` proactively
- `iframes.md` — running `eval` inside iframe targets; cross-origin gotchas
- `uploads.md` — `upload @<uid> <path>` semantics; when to use `--full-page` snapshot vs viewport
- `screenshots.md` — `screenshot --uid @<uid>` for element-only capture; `--full-page` for full doc; format choice (`png` vs `jpeg` vs `webp`) for token economy
- `network.md` — `network` + `network-get` for verification; filtering by type; when to use vs `eval` against `performance` API
- `forms.md` — `fill @<uid>` vs `fillform @<uid>=<val> @<uid2>=<val2>`; React-controlled inputs gotchas; submit via Enter vs button click

These are written by maintainers (one-time effort) because they encode CDP/MCP knowledge that doesn't change per-site. Agents can append to them but rarely need to.

Estimate: ~1 day of writing. Most content can be lifted from browser-harness's equivalents — the CDP semantics are identical, only the shell wrapping changes.

### C. Surface domain skills automatically on `open`

The killer feature. Add an `OPERA_CLI_DOMAIN_SKILLS=1` env flag (default off). When set, `open <url>` scans `agent-workspace/domain-skills/<host>/` for matching markdown files and emits a new top-level field in the response:

```
$ OPERA_CLI_DOMAIN_SKILLS=1 opera-browser-cli open https://github.com/akijain2000/opera-browser-cli
page: {title: "...", url: "https://github.com/...", refs: 12}
snapshot:
  ...
skills[2]:
  Read agent-workspace/domain-skills/github/repo-actions.md
  Read agent-workspace/domain-skills/github/scraping.md
help[1]:
  Run `opera-browser-cli click @1` to click the "More information..." link
```

Implementation: ~30 lines in `src/snapshot.ts` (or `src/suggestions.ts`). Match logic: take `URL(url).hostname`, strip `www.`, take the first dotted segment, look for that folder under `agent-workspace/domain-skills/`, list up to N markdown files. browser-harness's [`helpers.py`](https://github.com/browser-use/browser-harness/blob/main/src/browser_harness/helpers.py) lines 159–164 are the reference implementation:

```python
def goto_url(url):
    r = cdp("Page.navigate", url=url)
    if os.environ.get("BH_DOMAIN_SKILLS") != "1":
        return r
    d = (AGENT_WORKSPACE / "domain-skills" / (urlparse(url).hostname or "").removeprefix("www.").split(".")[0])
    return {**r, "domain_skills": sorted(p.name for p in d.rglob("*.md"))[:10]} if d.is_dir() else r
```

The off-by-default flag means existing users see no change. Agents who opt in get site-specific knowledge for free.

### D. Update `SKILL.md` to teach the contribution loop

After A–C land, append to `SKILL.md`:

> If you learn anything non-obvious while working on a site — a private API, a stable selector, a framework quirk, a URL pattern, a hidden wait, or a site-specific trap — write it as `agent-workspace/domain-skills/<host>/<topic>.md`. Capture the durable shape of the site (the map, not the diary). Don't write step-by-step task narration or pixel coordinates (they break on layout). Future runs against the same host will surface the file automatically when `OPERA_CLI_DOMAIN_SKILLS=1`.

This is the contract that makes the system self-improving. Without it, agents won't write skills proactively.

## Why bother?

Three concrete reasons.

**1. The CLI's value compounds with use.** Today, every agent run starts cold against every site. After this lands, the second time any agent in any user's environment hits `github.com`, it gets the React-fiber-swallows-synthetic-clicks gotcha for free. The third time it hits `linkedin.com`, it gets the rate-limit signature. The agent stops paying the same tax twice.

**2. It's the cheapest way to differentiate from browser-harness.** opera-browser-cli's CLI ergonomics are already strong — TOON, `help[]`, refs. What it's missing is the knowledge moat browser-harness has been building. We can copy the structure (open-source, MIT) and adapt it; we don't have to invent it.

**3. Contributors have somewhere to put work that compounds.** Right now a contributor who figures out a Shopify Polaris quirk has nowhere to file it. With domain-skills, they open a PR adding `agent-workspace/domain-skills/shopify-admin/polaris-inputs.md` and every future user benefits. browser-harness's contribution model (small per-site PRs, agent-generated) is high-throughput and maintainer-light — it's the right shape.

## Risks and open questions

- **Skill quality drift.** Agent-generated skills can capture wrong-but-currently-working patterns. Mitigation: PR review; periodic prune by maintainer; skills auto-decay after N months unless touched. browser-harness hasn't published a quality strategy publicly — worth asking them.
- **Privacy.** Agents must not write user data, secrets, or task narration into committed skills. browser-harness addresses this in their SKILL.md ("Don't write pixel coordinates, task narration, or secrets — the directory is public"). We need the same guardrail prominently in ours.
- **CLI surface complexity.** Adding `skills[]` to every `open` response increases token use slightly. Off-by-default flag mitigates; users who don't opt in see no change.
- **Where do skills live in the npm package?** browser-harness ships its `domain-skills/` inside the repo and uses `BH_AGENT_WORKSPACE` to point at a different one. We'd want similar — `OPERA_CLI_AGENT_WORKSPACE` env var pointing at a user-writable directory, defaulting to the repo's `agent-workspace/` for editable installs and to `~/.opera-browser-cli/agent-workspace/` for `npm i -g` users.
- **Coexistence with `specs/`.** Today `specs/` holds in-progress fix specs (planned work). `agent-workspace/` is for runtime-written skills (accumulated work). Different purposes — keep both, link from `AGENTS.md`.

## Implementation estimate

| Phase | Scope | Effort | Owner |
|---|---|---|---|
| A. `agent-workspace/` directory + READMEs + contract | Folder structure, 3 short README files, no code change | 0.5 day | Anyone |
| B. Seed 5–6 interaction-skills | Adapt from browser-harness, validate against current CLI behaviour | 1–2 days | Maintainer familiar with the CLI |
| C. Domain-skills surfacing in `open` | ~30 lines in `src/snapshot.ts` or `src/suggestions.ts`; env flag plumbing; tests | 0.5–1 day | Maintainer |
| D. SKILL.md contribution loop docs | Append section, link from README and AGENTS.md | 0.25 day | Anyone |

Total: 2–4 days of focused work.

## Companion PR

The install-docs restructure that this proposal builds on is shipped in [`akijain2000/opera-browser-cli` PR #2](https://github.com/akijain2000/opera-browser-cli/pull/2) (extracted `install.md`, slimmed README, added `AGENTS.md`, 2-sentence setup prompt). It's small, low-risk, and unblocks the elegance discussion above. Suggest reviewing and porting that first; the work in this doc can follow as a separate proposal.

## Open question for the team

Is this directionally interesting? If yes, the cheapest next step is to land A and D as a single PR — it adds the structure and the contribution rule but no code change. B and C can come iteratively, one site or one mechanic at a time, as the team encounters cases that warrant capture.

If the team wants to skip the agent-workspace pattern entirely and stay CLI-only, that's a coherent choice too — but worth saying so explicitly so contributors don't keep re-asking "where do I put this knowledge."

---

# Part 2: Onboarding patterns from `garrytan/gstack`

This is a parallel proposal to Part 1 — same audience, different concern. Part 1 is about **knowledge accumulation**. Part 2 is about **install UX**: how `setup` feels and what users have to decide up front.

[`garrytan/gstack`](https://github.com/garrytan/gstack) is Garry Tan's Claude Code skill pack (23 skills, ~10K stars, MIT). Its setup pattern is unusually polished — it asks zero questions on first install, then surfaces one decision per session as features become relevant. We can borrow most of it.

## What gstack does well — three pillars

### Pillar 1: Just-in-time consent gated by flag files

Every preference is opt-in via a one-time prompt that triggers the **first time the user hits a code path that benefits from the preference**. The choice is persisted in `~/.gstack/config.yaml`, and a marker file at `~/.gstack/.<feature>-prompted` ensures the prompt never fires again.

The mechanism lives in [`SKILL.md.tmpl`'s preamble](https://github.com/garrytan/gstack/blob/main/SKILL.md) and runs at the start of every skill invocation. Sample of the actual flow:

```bash
_TEL_PROMPTED=$([ -f ~/.gstack/.telemetry-prompted ] && echo "yes" || echo "no")
_PROACTIVE_PROMPTED=$([ -f ~/.gstack/.proactive-prompted ] && echo "yes" || echo "no")
# ... if not yet prompted, fire AskUserQuestion, capture answer via gstack-config set,
# then `touch` the marker file
```

Concrete prompts gstack runs over a user's first ~5 sessions:

| Prompt | Marker file | Persisted as |
|---|---|---|
| Writing style (default vs terse) | `.writing-style-prompted` | `explain_level` config |
| Telemetry (community / anonymous / off) | `.telemetry-prompted` | `telemetry` config |
| Proactive mode (auto-invoke matching skills) | `.proactive-prompted` | `proactive` config |
| Skill routing rules in CLAUDE.md | (config-driven) | `routing_declined` config |
| Vendored gstack warning + migrate offer | `.vendoring-warned-<slug>` | (just the marker) |
| GBrain sync (full / artifacts / off) | (config-driven) | `gbrain_sync_mode_prompted` config |

Each fires once. The user is never bombarded — at most one decision per session.

**Spawned-session opt-out:** `OPENCLAW_SESSION=true` env var skips ALL prompts, the skill auto-chooses recommended options. Crucial for spawned sessions that can't ask the user.

### Pillar 2: Multi-host auto-detection

[`setup` lines 158–178](https://github.com/garrytan/gstack/blob/main/setup#L158-L178):

```bash
if [ "$HOST" = "auto" ]; then
  command -v claude   >/dev/null 2>&1 && INSTALL_CLAUDE=1
  command -v codex    >/dev/null 2>&1 && INSTALL_CODEX=1
  command -v kiro-cli >/dev/null 2>&1 && INSTALL_KIRO=1
  command -v droid    >/dev/null 2>&1 && INSTALL_FACTORY=1
  command -v opencode >/dev/null 2>&1 && INSTALL_OPENCODE=1
  ...
fi
```

`./setup --host auto` installs for every coding agent the user has on `PATH`. Each host gets its own runtime root (`~/.codex/skills/gstack`, `~/.factory/skills/gstack`, etc.) with appropriate symlinks. Same skill source serves all hosts.

### Pillar 3: Versioned migrations

[`setup` lines 945–970](https://github.com/garrytan/gstack/blob/main/setup#L945-L970):

```bash
MIGRATIONS_DIR="$SOURCE_GSTACK_DIR/gstack-upgrade/migrations"
CURRENT_VERSION=$(cat "$SOURCE_GSTACK_DIR/VERSION")
LAST_SETUP_VERSION=$(cat "$HOME/.gstack/.last-setup-version" || echo "0.0.0.0")
# ... finds migrations/v*.sh between LAST_SETUP_VERSION and CURRENT_VERSION
# ... runs them in semver order, idempotent
echo "$CURRENT_VERSION" > "$HOME/.gstack/.last-setup-version"
```

User upgrades → next setup runs all migrations between their old version and the new version, in order, idempotently. Used for stale config, orphaned files, directory-structure changes — anything `setup` alone can't cover.

### Six smaller patterns worth noting

| # | Pattern | Where |
|---|---|---|
| a | **Once-per-day update banner** — `gstack-update-check` prints `UPGRADE_AVAILABLE 1.2.3 -> 1.2.4` when remote `VERSION` differs, throttled by `last-update-check` mtime | [`bin/gstack-update-check`](https://github.com/garrytan/gstack/blob/main/bin/gstack-update-check) |
| b | **Self-healing inline migrations** — banner-printer also fixes known bad state (e.g. oversized Codex descriptions) gated by single-shot marker | same file |
| c | **Team mode** — `./setup --team` enables auto-update via SessionStart hook + `gstack-team-init required` bootstraps shared repos | [`setup` 980–1000](https://github.com/garrytan/gstack/blob/main/setup#L980-L1000) |
| d | **Smart rebuild detection** — only rebuilds if source files / package.json / lock are newer than the binary | [`setup` 224–233](https://github.com/garrytan/gstack/blob/main/setup#L224-L233) |
| e | **Annotated config header** — first `gstack-config set` writes a YAML file with comments explaining every key | [`bin/gstack-config`](https://github.com/garrytan/gstack/blob/main/bin/gstack-config) |
| f | **Welcome-once flag** — `~/.gstack/.welcome-seen` — terse "Welcome! Run /gstack-upgrade anytime" only on first install | [`setup` 972–976](https://github.com/garrytan/gstack/blob/main/setup#L972-L976) |

## What `opera-browser-cli` does today

Single-shot wizard. Everything decided up front in one `opera-browser-cli setup` invocation:

- Detects Opera installs, lets the user pick one
- Writes `~/.opera-browser-cli/config` (mode `0600`)
- Installs the Claude Code skill at `~/.claude/skills/opera-browser-cli/SKILL.md`
- Writes `SessionStart` hooks to `~/.claude/settings.json` and `~/.codex/hooks.json`
- `OPERA_CLI_DISABLE_HOOKS=1` env opt-out

What it doesn't do:

- No just-in-time prompts. Everything decided up front.
- No multi-host auto-detection. Hooks are written to Codex but the **skill itself** only goes to `~/.claude/skills/`.
- No telemetry consent (no telemetry, but no opt-in either — should the team add some, the consent flow needs to exist).
- No update banner.
- No team mode / SessionStart hook for self-update.
- No migrations system.
- No `config` CLI subcommand (`get` / `set` / `list` / `defaults`).
- No spawned-session detection.

## What to borrow — five patterns prioritized by ROI

### 1. `opera-browser-cli config` subcommand (smallest, biggest delta)

Adopt gstack-config's shape:

```sh
opera-browser-cli config get telemetry
opera-browser-cli config set hooks.enabled false
opera-browser-cli config list
opera-browser-cli config defaults
```

Backs onto the existing `~/.opera-browser-cli/config` (KEY=VALUE format already exists). Adds a defaults table, an annotated header on first write. ~80 LOC in `src/cli.ts` + a new `src/config.ts`. Unblocks every pattern below — they all need a config get/set primitive.

### 2. Just-in-time prompts gated by flag files

The biggest UX win. Today the setup wizard asks ~5 questions up front. Instead, install asks zero — the user runs `opera-browser-cli open https://example.com` and it works. Then over the next few invocations, the CLI surfaces one decision at a time:

| First time the user… | …prompt | Persist as | Marker |
|---|---|---|---|
| Runs `opera-browser-cli` ≥3 times | "Should I install a SessionStart hook so the bridge auto-starts?" | `hooks.enabled` | `~/.opera-browser-cli/.hooks-prompted` |
| Tries an Opera AI command (`chat`, `make`, etc.) | "These need Opera Neon signed in. Configure now?" | (runs Neon path of `setup`) | `~/.opera-browser-cli/.neon-prompted` |
| Runs against the same site ≥3 times | "Want to capture lessons learned in `agent-workspace/domain-skills/<host>/`?" *(needs Part 1)* | `domain_skills.enabled` | `~/.opera-browser-cli/.domain-skills-prompted` |

Implementation: ~50 LOC in `src/cli.ts` — checks marker files at the top of `main()`, fires prompts before dispatching the user's actual command. Skip if `OPERA_CLI_SPAWNED_SESSION=1` (the parallel of `OPENCLAW_SESSION`).

Net effect: install drops from "answer 5 questions" to "it just works", and users discover features when they're relevant, not all at once.

### 3. Multi-host auto-detection in `setup`

Mirror gstack's `--host auto`:

```sh
opera-browser-cli setup --host auto    # default
opera-browser-cli setup --host codex   # explicit
opera-browser-cli setup --host claude
opera-browser-cli setup --host cursor
```

`auto` checks `command -v claude codex cursor` and installs the skill into whichever skill directory each one uses (`~/.claude/skills/`, `~/.codex/skills/`, `~/.cursor/skills/`). Already most of the way there — `setup` writes hooks to both Claude and Codex hook files; just needs to extend the **skill-copy** step to match. ~30 LOC in `setup` (or wherever the wizard logic lives in `src/cli.ts`).

### 4. `--team` mode with auto-update SessionStart hook

[Two things bundled together](https://github.com/garrytan/gstack/blob/main/setup#L980-L1000):

- `opera-browser-cli setup --team` writes a `SessionStart` hook that runs `opera-browser-cli --update-if-newer` at the start of every Claude Code / Codex session.
- The hook is throttled (once per hour, network-failure-safe, silent) so it doesn't slow session start.
- `opera-browser-cli team-init` bootstraps a repo: writes `.claude/settings.json` with the hook + commits it, so teammates get auto-update for free.

Why this matters specifically for `opera-browser-cli`: the bridge process model means **version drift is dangerous** — a stale bridge against a newer `opera-devtools-mcp` can deadlock or stream-route incorrectly (see [`specs/fix-parallel-streaming-routing.md`](specs/fix-parallel-streaming-routing.md)). Auto-update on session start eliminates that class of bug for teams.

### 5. Migrations system

Add `migrations/v*.sh` directory + `~/.opera-browser-cli/.last-setup-version` marker. Setup runs all unrun migrations in semver order. ~20 LOC in the setup wizard. Lets us ship config-format changes, hook-shape changes, etc., without breaking existing installs.

Each migration is a standalone shell script — idempotent by design:

```sh
# migrations/v0.2.0.sh
# v0.1.x stored config as JSON; v0.2.0 is YAML.
if [ -f ~/.opera-browser-cli/config ] && head -1 ~/.opera-browser-cli/config | grep -q '{'; then
  ~/.opera-browser-cli/migrate-config-to-yaml
fi
```

## What NOT to borrow — and why

| gstack pattern | Why skip for opera-browser-cli |
|---|---|
| Skill prefix prompt (`/gstack-qa` vs `/qa`) | gstack has 23 skills; `opera-browser-cli` has one. Namespacing matters at scale, not at one. |
| 23-specialist skill ecosystem | Different scope. `opera-browser-cli` is one tool, not a tool family. |
| Browse binary compile + Apple Silicon codesign workaround | Not relevant — `opera-browser-cli` is npm-installed JS, no compiled binary. |
| "Boil the lake" intro / completeness manifesto | gstack's branding moment. Not transferable. |
| GBrain sync | Separate product. |
| Builder/developer profile gating | Audience-segmentation tool. `opera-browser-cli` has one audience. |

## Implementation estimate (Part 2)

| Phase | Scope | Effort |
|---|---|---|
| 2.1 `config` subcommand | New `src/config.ts`, wire into `cli.ts`, `defaults` table, annotated header on first write, tests | 0.5–1 day |
| 2.2 Just-in-time prompts framework | Marker-file checker in `cli.ts main()`, 3 starter prompts, spawned-session opt-out, tests | 1 day |
| 2.3 Multi-host auto-detect in setup | `--host` flag, `auto` detection, per-host skill copy | 0.5 day |
| 2.4 `--team` + auto-update hook | `--team` flag, `team-init` subcommand, SessionStart hook content, throttle logic | 0.5–1 day |
| 2.5 Migrations system | `migrations/` directory, `.last-setup-version` marker, semver-ordered runner | 0.25 day |

Total: 3–4 days of focused work. Each phase is independently shippable; 2.1 unblocks the others.

## Combined plan: Part 1 + Part 2

If both proposals land, here's the natural sequencing — each phase is a separate small PR:

1. **Part 1.A + Part 1.D** — `agent-workspace/` skeleton + SKILL.md contribution rule (no code change)
2. **Part 2.1** — `config` subcommand (unblocks 2.2)
3. **Part 1.B** — seed 5–6 interaction-skills
4. **Part 2.2** — just-in-time prompts framework (uses 2.1)
5. **Part 2.3** — multi-host auto-detect
6. **Part 1.C** — domain-skills surfacing in `open`
7. **Part 2.4** — `--team` mode
8. **Part 2.5** — migrations system

Total: ~5–8 days across both proposals. Order matters for 2.1 → 2.2; everything else is parallelizable.

## Open question for the team (Part 2)

Is just-in-time onboarding directionally interesting? It's a meaningful UX shift — users go from "answer 5 questions to install" to "it just works, ask me later." gstack has validated the pattern at ~10K-star scale.

Cheapest first step: ship 2.1 (`config` subcommand) on its own. It's useful immediately (users can introspect/tweak config) and unblocks the rest of Part 2 if the team wants to keep going.
