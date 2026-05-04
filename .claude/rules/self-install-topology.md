---
applies_to: customer-projects-only
---

In a consumer project (any repo where Just Ship was installed via `setup.sh`), the framework source lives **outside this repo** — typically in a separate clone of the engine repo. What you see locally is the install: `.pipeline/`, `.claude/agents/`, `.claude/commands/`, `.claude/skills/`, `.claude/rules/`, etc. There is no Source/Install duplication here, because the source isn't in this tree at all.

Edits to install-path files in this repo will survive locally, but they will **not survive the next `setup.sh --update` run** — that command regenerates the install from the engine source. If you want a change to stick, it has to land in the engine source first.

## The topology in a consumer repo

| Path | Who writes it | Persistent? |
|---|---|---|
| `.pipeline/` | `setup.sh` | No — regenerated on every `--update` |
| `.claude/agents/*.md` | `setup.sh` | No — regenerated on every `--update` |
| `.claude/commands/*.md` | `setup.sh` | No — regenerated on every `--update` |
| `.claude/skills/*.md` | `setup.sh` | No — regenerated on every `--update` |
| `.claude/rules/*.md` | `setup.sh` | No — regenerated on every `--update` |
| `.claude/scripts/*` | `setup.sh` | No — regenerated on every `--update` |
| `.claude/hooks/*.sh` | `setup.sh` | No — regenerated on every `--update` |
| `.claude/settings.json` | `setup.sh` | Replaced on every `--update` |
| `.claude/.pipeline-version` | `setup.sh` | Stamp file — never hand-edit |
| `.claude/.template-hash` | `setup.sh` | Stamp file — never hand-edit |
| `CLAUDE.md` | First install only; user owns it after | Yes — never overwritten on update |
| `project.json` | First install + plugin injection | Yes — never overwritten, only merged |

## What this means for you

- **Need to change agent / command / skill / rule behavior?** It belongs in the engine source. Open an issue or PR against the engine repo. A local edit to `.claude/agents/orchestrator.md` will work for one session and disappear on the next `setup.sh --update`.
- **Need to change pipeline behavior?** Same answer — `.pipeline/` is regenerated from the engine's `pipeline/` source. Don't hand-patch `.pipeline/run.ts`.
- **Need to change CLAUDE.md or project.json?** Those are yours. Edit freely. `setup.sh --update` will not touch CLAUDE.md once it exists, and project.json gets merged (not replaced) — your project-specific fields survive.
- **Need a one-off local hack?** Use `GIT_ALLOW_INSTALLED_EDIT=1 git commit ...` to bypass the pre-commit gate that protects against malformed artifact frontmatter. The hack will still be wiped on the next update — plan accordingly.

## How updates flow

```
engine source (somewhere else)
  ↓ git pull / new release
setup.sh --update (run in this repo)
  ↓ regenerates install paths
your repo (.pipeline/, .claude/agents/, …)
```

The version stamp at `.claude/.pipeline-version` records which engine commit produced the current install. `pipeline/run.sh` does not enforce a drift-check — if the install is stale relative to your engine clone, `setup.sh --update` is the fix.

## Anti-patterns

❌ **Edit `.pipeline/run.ts` to fix a bug.** The fix vanishes on the next `setup.sh --update`. The right path is: reproduce in the engine repo, fix there, push, run `setup.sh --update` here.

❌ **Add a new agent by creating `.claude/agents/my-agent.md`.** Same problem — the agent file is wiped on update. Add it in the engine source under `agents/my-agent.md`, then run `setup.sh --update` here.

❌ **Hand-edit `.claude/.pipeline-version` to silence a version-drift warning.** The file is a stamp that records what `setup.sh` actually installed. Faking it lies about the install state.

✅ **Project-specific work goes in `CLAUDE.md`, `project.json` (merged fields), `src/` (your code), and any custom skill files you want — `.claude/skills/<name>.md` files that don't exist in the engine source are preserved, only framework-named files get regenerated.**

## Engine repo note

If you're reading this rule inside the **engine repo** (the repo that contains `setup.sh` and `pipeline/`), the topology is simpler: the source is the install. Edits to `pipeline/`, `agents/`, `commands/`, `skills/`, `.claude/rules/`, `.claude/scripts/`, `.claude/hooks/` are direct — no `.pipeline/` install copy is maintained there since T-1064. This rule's `applies_to: customer-projects-only` keeps it scoped to consumer projects, where the regeneration trap actually exists.
