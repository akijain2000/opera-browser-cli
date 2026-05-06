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
