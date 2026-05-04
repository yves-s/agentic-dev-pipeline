# CTO Deep Audit — Just Ship Engine

**Date:** 2026-04-25
**Auditor:** CTO (single-pass, no parallel sub-agents — see Caveats)
**Branch:** main (read-only)
**Scope:** Engine repo (`just-ship`) plus cross-checks against installed copies in `just-ship-board`, `just-ship-bot`, `just-ship-web`

CTO Skill geladen ✓ — head-hash 3d0da06f505c91462efb8cf464953a68 (lines 1–5 of `skills/product-cto/SKILL.md`).

---

## 1. Executive Summary

The system has been productively engineered for two weeks (49 feats, 24 fixes, 91 commits in 14 days), but its core invariants are silently broken in production. Three structural defects compound into the trust collapse the CEO is feeling:

1. **The reasoning Sidekick is wired but not connected.** The new seven-tool reasoning system (T-983) and the matching system prompt with 15+ few-shot examples (T-986) exist as code with passing unit tests — but `pipeline/lib/sidekick-chat.ts:394` invokes the SDK with `allowedTools: []`. The browser widget and terminal both hit a tool-less Sonnet that can talk about creating tickets but cannot actually create them. The Operating Model's central building block (Sidekick as orchestration hub) is non-functional in the running engine.
2. **The skill-loading topology is broken at the source-vs-install boundary.** Every specialist agent now hard-codes `Read('skills/<role>/SKILL.md')` (T-1014, yesterday). That path exists *only* in the engine repo. In every installed project (`just-ship-board`, `bot`, `web`) the skill lives at `.claude/skills/<role>.md`. T-1014 fixed the symptom in this repo while guaranteeing the same symptom in every customer install — and there is no setup.sh logic that rewrites the path on copy.
3. **The self-install repo is two weeks behind itself.** `.claude/.template-hash` and `framework.updated_at` in `project.json` are stamped `2026-04-12 (a36db5a)`. Source has 30+ commits and 7 new skills since (`design-lead`, `reporter`, `sidekick-converse`, `find-skills`, `implement`, `plugin-security-gate`, `autonomy-boundary` — none of these are present in `.claude/skills/`). Every Sidekick or `/develop` run in *this very repo* is operating against a stale install. The Reporter skill that the new `/develop`, `/ship`, and `/implement` flows depend on (T-997, T-998, T-999, T-1003) is not installed locally — those features are dead in this repo.

**Top-3 recommendations (full roadmap in §6):**
1. Wire the seven reasoning tools into `sidekick-chat.ts` and ship a path-aware skill loader that resolves both `skills/<n>/SKILL.md` and `.claude/skills/<n>.md` at the agent prompt-injection boundary, not in markdown.
2. Add a CI job that diffs `skills/<n>/SKILL.md` vs `.claude/skills/<n>.md` and fails on drift; same for `agents/` and `commands/`. Run `setup.sh --update` as part of CI on this self-install repo so the install never falls behind source.
3. Replace the hand-edited `Read('skills/...')` strings in agent prompts with a runtime injection via `appendSystemPrompt` (already named in the T-1014 commit's "out of scope"). The markdown-instruction approach can never survive the install/source duality.

The codebase isn't broken because the engineers are bad. It's broken because the ground truth ("what runs?") is invisible behind two layers of indirection (source markdown + install markdown + SDK config) and no test exercises the end-to-end. Every fix from the last two weeks addresses a symptom the next install will reintroduce.

---

## 2. Skill-Load-Verifikation

`skills/product-cto/SKILL.md` loaded ✓. Hash of first 5 lines: `3d0da06f505c91462efb8cf464953a68`. Operating Model, PRODUCT.md, CLAUDE.md, all 17 rules under `.claude/rules/` read.

---

## 3. Phase 2 Inventory Findings

### A. Commit pattern (last 14 days)

| Type | Count | Notes |
|---|---|---|
| feat | 49 | Heavy build cadence — Sidekick reasoning architecture (T-983/986/979/980), Operating Model (T-990/991), Reporter system (T-998/999/997/1003), develop/ship instrumentation |
| fix | 24 | ~24% of commits are bug fixes — high but not catastrophic |
| chore | 10 | Mostly process/rules |
| docs | 7 | |
| test | 1 | **Only one test-only commit in 14 days.** Tests are added inline with feats, and entire critical files have zero tests (see §3.E). |

Reverts: 0 — but the pattern of `fix(T-XYZ)` immediately following `feat(T-XYZ)` shows up multiple times (T-826: feat + four fixes in one day; T-799/802/805/796/801/814 init flow: triple-fix sequence — see incident log).

Top 5 modified files (14 days):
1. `CHANGELOG.md` (67 changes — auto-bumped per merge)
2. `setup.sh` (27 changes — fragile install script churning)
3. `pipeline/server.ts` (9 changes)
4. `README.md` (8 changes)
5. `CLAUDE.md` (7 changes)

### B. Incident log (5 reports under `docs/incidents/`)

| Date | Title | Root-cause cluster |
|---|---|---|
| 2026-04-07 | Pipeline Reliability Crisis | Pipeline never ran end-to-end for 3 weeks; orchestrator never delegated; "done" reported without verification |
| 2026-04-10 | Orchestrator-Bypass T-741 | Orchestrator missed native Claude Code feature, planned over-engineered system; agent did 4/10 files; CEO had to escalate |
| 2026-04-11 | Init-Flow broken | 12-line CLAUDE.md instead of 265, empty project.json, no framework files copied — three independent root causes |
| 2026-04-12 | Plugin-skills not in project | 4 tickets shipped, feature still non-functional; ~$22 / 55M tokens; CEO corrected 5x |
| 2026-04-21 | Workflow-bypass design-lead | Rollen-Anrede + frontend-design skill loaded directly, no ticket, code on `main` |

**Common pattern across all 5:** features that rely on multiple files coordinating (skills + agents + setup.sh + project.json) ship "green" while the runtime composition is broken. No incident was caught by tests; all by the CEO at runtime.

### C. Skill-loading topology audit (CRITICAL)

**Source vs install gap (`skills/` vs `.claude/skills/` in this repo):**

Present in source `skills/` but **missing from `.claude/skills/`** in this repo:
- `design-lead`, `reporter`, `sidekick-converse`, `plugin-security-gate`, `ticket` (note: source has both `ticket/` and `ticket-writer/`; install has only `ticket-writer.md`)

Present only in install (plugin skills): `plugin--differential-review--differential-review`, `plugin--insecure-defaults--insecure-defaults`, `plugin--sentry-skills--*` (4) — these are correctly placed (plugin-system installs flat).

**Source-path leakage in agent/command markdown:**

`grep -rnE "skills/[a-z-]+/SKILL\.md" agents/ commands/` finds 14 references. Examples:

- `agents/orchestrator.md:52` — spawn template uses `Read('skills/{role}/SKILL.md')`
- `agents/backend.md:24`, `agents/frontend.md:26`, `agents/qa.md:25`, `agents/data-engineer.md:24`, `agents/security.md:25`, `agents/devops.md:26` — each has `Read('skills/<role>/SKILL.md')` as ERSTER TOOL-CALL
- `commands/develop.md:348,354–357,450,452` — same pattern in the develop command

**These paths only resolve in the engine repo.** In `just-ship-board` (verified): no `skills/` directory exists; `.claude/skills/backend.md` does. The agent's first tool call will fail (or fall back silently), the skill never loads, and the agent works as a generic coder. T-1014 (yesterday's fix) made this *worse*, not better, because it removed the prior fallback wording ("Lade dein Domain-Skill via Skill-Tool") and replaced it with a hard `Read('skills/...')` that has zero chance of working in installed projects.

**Stage check:**
- `framework.updated_at` in this repo's `project.json`: `2026-04-12`
- 30+ source commits since
- 7 new skills since not installed locally (incl. `reporter`, on which 4 features built this week depend)

### D. Stuck tickets / worktree hygiene

```
.worktrees/T-1013
.worktrees/prototype-to-production
```

Two orphan worktrees. T-1013 is uncommitted ticket work; `prototype-to-production` looks like an experiment branch. Neither has matching `in_progress` Board status (not queried — read-only audit per spec). No active work loss, but orphan accumulation indicates `/recover` is not being run.

### E. Test-coverage inventory

26 `.test.ts` files vs 43 production files in `pipeline/lib/`. Coverage of critical files:

| File | LOC | Tested? |
|---|---|---|
| `load-skills.ts` | 296 | ✓ (342 lines) |
| `audit-runtime.ts` | 928 | ✓ (735 lines) |
| `sidekick-reasoning-tools.ts` | 678 | ✓ (661 — but tests don't cover wiring into chat) |
| `sidekick-chat.ts` | 631 | ✓ (614 — but tests don't catch `allowedTools: []` bug) |
| `sidekick-system-prompt.ts` | 343 | ✓ (snapshot tests) |
| `model-router.ts` | 182 | ✓ |
| `github-app.ts` | 191 | ✓ (264 — added today, T-1015/1014 area) |
| `load-agents.ts` | 102 | **✗ NO TEST** — frontmatter parser, agent loading, no coverage |
| `worktree-manager.ts` | 419 | **✗ NO TEST** — every `/develop` and `/ship` flows through it |
| `event-hooks.ts` | 188 | **✗ NO TEST** — pipeline event reporting, agent state chips |
| `watchdog.ts` | 87 | **✗ NO TEST** — agent timeout detection |
| `drain.ts` | 126 | **✗ NO TEST** — graceful shutdown |
| `qa-runner.ts` | 677 | **✗ NO TEST** — QA loop |
| `qa-fix-loop.ts` | 176 | **✗ NO TEST** — autonomous fix loop |
| `config.ts` | 290 | **✗ NO TEST** — project.json loader |

The pattern: heavy unit tests on the new Sidekick reasoning code; the *runtime* code (event-hooks, worktree-manager, watchdog, qa-runner, config) has none. The user's complaint "Agent-Chips zeigen falsche States" maps directly to event-hooks/watchdog being untested.

---

## 4. Phase 3 Domain-Audits

Spec asked for 4–6 parallel sub-agents. I executed them serially in this single context (Caveat: see §10). What follows is the consolidated finding set, severity-sorted.

### Backend (pipeline/lib)

**CRITICAL — Sidekick reasoning tools not wired into chat endpoint.**
`pipeline/lib/sidekick-chat.ts:394` sets `allowedTools: []`. The seven tools defined in `sidekick-reasoning-tools.ts` and advertised in the system prompt (`sidekick-system-prompt.ts`) are never offered to the model. A user typing "create a ticket for the typo on /pricing" in the browser widget gets a chat reply, not a ticket. The Operating Model's premise (§ "Four building blocks → Sidekick", § "Tools" table) is nonfunctional. This is invisible because the unit tests for chat use a scripted `_internal.callChatModel` seam that never asks the SDK what tools it has.

**HIGH — Two parallel Sidekick code paths (legacy classifier + new reasoning) coexist.**
`sidekick-policy.ts` (195 LOC) + `sidekick-converse.ts` (847 LOC) implement the legacy classifier-first model. T-979 was supposed to remove the classifier-first path — it removed the classifier *file* but `sidekick-converse.ts` still imports from `sidekick-policy.ts` and `pipeline/server.ts:1795` still routes `/api/sidekick/converse` to it. New code (`sidekick-reasoning-tools.ts`, `sidekick-system-prompt.ts`) lives next to it but isn't connected. Two truths in the same module.

**HIGH — `executeSidekickReasoningTool` has zero callers in production code.**
`grep -rE "executeSidekickReasoningTool" pipeline/` returns one declaration (the file itself) and one test. The dispatcher exists; nothing calls it. Same for `toolSchemas()` — declared, tested, never used outside its own file.

**MEDIUM — `expert_runtime_not_implemented` for two of three expert tools.**
`sidekick-reasoning-tools.ts:482` returns a hard-coded `not_implemented` error for `consult_expert` and `start_sparring`. Only `run_expert_audit` is wired (via T-985). Even if the chat endpoint were tool-enabled, two of the three "expert" tools would no-op.

**MEDIUM — Skill loader's `frameworkSkillsDir` lookup uses install structure.**
`load-skills.ts:209` resolves `${projectDir}/skills/${name}.md`. But the source structure is `skills/<n>/SKILL.md` (subdirectory). The framework-skills-dir lookup will *never* match in the source repo — only the `.claude/skills/${name}.md` fallback matches. The "framework first, install fallback" semantics implied by the variable names are inverted in practice. Setup.sh works around it by flattening (`cp $d/SKILL.md → .claude/skills/$dname.md`) — but that means the `frameworkSkillsDir` branch in the loader is dead code.

**LOW — Module-init race documented as fixed but the workaround is fragile.**
`audit-runtime.ts:21` duplicates `EXPERT_SKILL_VALUES` to break a circular value-level dependency, with a compile-time lockstep guard. Works, but brittle: any contributor adding an expert in one file but not the other will hit a TS error in audit-runtime that doesn't obviously point to the actual fix location.

### Data engineer

**No `migrations/` directory in this engine repo.** Schema lives in the Board project. Engine talks to Board via REST API (good — confirmed in `sidekick-create.ts`, `threads-store.ts`). No data-engineering findings in scope here. Full schema audit would require reading `just-ship-board/` migrations, deferred to Caveats.

**LOW — Threads-store uses in-memory map keyed by thread_id.**
`sidekick-chat.ts:_resetChatThreadsForTests`, the THREAD_TTL_MS eviction, and the `inFlight` guard suggest threads live in process memory, not Postgres. Restart loses chat state. Acceptable for short-lived chat turns, but "Engine owns Sidekick threads + conversations" (T-924) suggests durable threads. Verify which threads-store is authoritative — the persistence story is split across `threads-store.ts` (DB-backed) and the in-memory map in `sidekick-chat.ts`.

### DevOps

**HIGH — CI does not run `setup.sh --update --check`.**
`.github/workflows/build-pipeline.yml` runs typecheck and tests but never validates that the self-install matches source. The two-week drift on this repo would have failed a "git diff --quiet after `setup.sh --update`" check on day one.

**HIGH — Pre-commit hook scope is narrower than the documented topology.**
`.githooks/pre-commit` blocks edits to `.pipeline/`, `.claude/.pipeline-version`, `.claude/.template-hash` only. Per `self-install-topology.md`, `.claude/{agents,commands,skills}/` are also installed copies that get clobbered by `setup.sh --update`. The rule documents this as "deferred" but the gap is what allowed (and continues to allow) the source-path leakage in §3.C.

**MEDIUM — `setup.sh` is 1640 lines with no test harness.**
Every install/update/migration path runs through it. Init-flow incident (2026-04-11) and plugin-skills incident (2026-04-12) both stem from setup.sh edge cases. A bash test harness exists for some scripts (`session-summary.test.sh`, `develop-summary.test.sh` etc., 1500+ test lines) but not for setup.sh itself.

**MEDIUM — Plugin-skill install relies on `claude plugin install` succeeding silently.**
`setup.sh:392` swallows `claude plugin install` failures with `|| echo "  ⚠ Failed"`. If the user has an offline session or the marketplace is misconfigured, plugins silently drop. The `plugin_count` counter still increments to `total`, so the success message lies.

**LOW — Hooks copy uses unguarded glob.**
`setup.sh:1240` does `cp "$FRAMEWORK_DIR/.claude/hooks/"*.sh "$PROJECT_DIR/.claude/hooks/" 2>/dev/null || true`. If hooks dir is empty, the script proceeds silently. Combined with the documented intent that hooks enforce constraints, a missing hook is a security regression.

### QA

**CRITICAL — Two of the most failure-prone files have zero tests.**
`worktree-manager.ts` (419 LOC) and `qa-runner.ts` (677 LOC) — both untested. The pipeline-reliability incident (2026-04-07) was largely worktree state confusion. Adding 1 test wouldn't catch it; the absence of any test is the issue.

**HIGH — Snapshot tests on the system prompt mask logical drift.**
`sidekick-system-prompt.test.ts` asserts the prompt is byte-for-byte stable. That catches accidental edits but not the question "does the prompt actually drive the model to call the right tool" — because the chat endpoint doesn't call any tools (see Backend §1).

**HIGH — `sidekick-policy.test.ts` (541 lines) tests the policy code that should be deprecated.**
Resources are spent maintaining tests on the legacy classifier path while the new reasoning path's wiring lacks integration coverage. T-980 ("rewrite sidekick-policy corpus for reasoning-first model") rewrote the corpus but left both paths alive.

**MEDIUM — Test naming hides what's tested.**
e.g. `sidekick-chat.test.ts` exists with 614 lines but doesn't cover the production model invocation path — the test seam (`_internal.callChatModel`) bypasses it. Reading the test file and trusting "covered" is a false signal.

### Security

**LOW — Audit-runtime read-only contract is well-engineered.**
`audit-runtime.ts:classifyBashCommand` is conservative, layered, and tested (`audit-runtime.test.ts` 735 lines). The expert-audit-scope rule documents the boundary clearly. This is the strongest module in the codebase.

**MEDIUM — Plugin skills bypass the audit-runtime allowlist.**
The `plugin-security-gate.sh` (called from setup.sh:493) scans plugin skills for dangerous patterns at install time, but the runtime has no equivalent — once a plugin skill is installed, it's loaded into agent context as-is. The gate is one-shot, not enforcing.

**LOW — `BLOCKED_PREFIXES` in pre-commit hook is bash-array; one entry per line.**
`/.claude/.template-hash` and `/.claude/.pipeline-version` matched as prefixes — fine because no other file shares the prefix, but a future `.claude/.template-hash.bak` would be incorrectly blocked. Cosmetic.

**LOW — `GIT_ALLOW_INSTALLED_EDIT=1` is the only emergency override.**
Documented in the rule and the hook. Acceptable, but a future audit should require a paired commit message tag (e.g. `[allow-install-edit: T-NNN]`) so the override is auditable in `git log`.

### Code-review (architecture & dead code)

**HIGH — `sidekick-tools.ts` (827 LOC) is documented as "Sidekick Tool-Registry — T-923" but its registry isn't called by any production code path.**
The new `sidekick-reasoning-tools.ts` (T-983) was meant to replace it. Both exist. The old one has a 470-line test file. Duplication is not parity.

**HIGH — Reporter skill (`skills/reporter/`) is referenced from `commands/ship.md`, `commands/develop.md`, multiple agents, but is not installed in `.claude/skills/`.**
This means `/develop` and `/ship` in this very repo cannot use the Reporter system that was built this week (T-998, T-999, T-997, T-1003). It will be installed in customer projects via `setup.sh --update`, but only if their `.template-hash` is older than the framework's — which it is for this repo too (`2026-04-12` stamp), and yet the install never happened.

**MEDIUM — Skill `ticket` (NEW) and `ticket-writer` coexist in source, only `ticket-writer` is installed.**
The naming is confusing and probably one is dead. `skills/ticket/SKILL.md` is 44 lines — looks like a redirect.

**MEDIUM — `develop/SKILL.md` is 806 lines (Operating Model says ≤500).**
`just-ship-vps/SKILL.md` is 608 lines. Both exceed the constitutional limit. The constitution explicitly says "≤500 lines" because longer skills compete for attention with system prompts — and these are the two most-loaded skills.

**LOW — `agents/security.md` and `agents/devops.md` instruct `Read('CLAUDE.md')` as the first tool call because no domain skill exists.**
That's a reasonable fallback but means these agents have no enforced anti-pattern catalog. Plan to either create the skills or remove the instruction.

**LOW — `agents/devops.md` references `skills/reporter/SKILL.md` for output formatting.**
Same source-path leakage. In an installed project this is `.claude/skills/reporter.md`.

---

## 5. Phase 4 Vision-Drift

### 5.1 Code is ahead of the vision

- **Audit runtime** (`audit-runtime.ts`, 928 LOC, T-985) is more sophisticated than the Operating Model required — it has a 9-error-code taxonomy, Sentry instrumentation, `canUseTool` callback layered over `allowedTools`, and a fully tested Bash sandbox. The vision says "read-only specialist" in one paragraph; the code delivers a hardened sandbox. **Not a problem — but worth noting that the strongest piece of the system is also the one furthest from a user-visible feature.**
- **Three parallel skill-loading mechanisms exist:** (1) `loadSkills` injects skills into agent prompts via `byRole` map, (2) `Read('skills/...')` markdown instructions in agent definitions, (3) Claude Code's native `Skill` tool referenced in `agents/orchestrator.md:26`. Vision describes one mechanism (Skill tool, on-demand load). Code has three competing ones. The recent T-1014 fix added a fourth via `Read('skills/...')`.
- **`pipeline/server.ts` is 2208 lines with 20+ HTTP endpoints** (`/api/launch`, `/api/events`, `/api/answer`, `/api/sidekick/{chat,conversations,threads,create,update,attach,converse,create-project}`, `/api/ship`, …). Operating Model lists Path 2 as "Board calls an Engine endpoint". Singular. Reality is a fan-out.

### 5.2 Code lags behind the vision

- **Sidekick reasoning tools not wired** (Backend §1) — vision says these are the orchestrator's primitives; reality is they're shelf-ware.
- **No-polling promise** (Operating Model §"Two execution paths"): vision says polling is removed (T-993). Code: `pipeline/server.ts` has no polling loop ✓ — but `sidekick-converse.ts` still implements the legacy poll-style state machine the new push model is supposed to replace.
- **Reporter, design-lead, sidekick-converse skills built but not installed** (§3.C, §4 Code-review HIGH) — features shipped, deployment incomplete.
- **Three-tier loading model** (Operating Model § "Architecture of loaded context"): vision says CLAUDE.md ≤200 lines. Current CLAUDE.md is 93 lines ✓. But two skills (`develop`, `just-ship-vps`) exceed the 500-line ceiling, and the agents have effectively become a fourth tier (`agents/<n>.md` is 50–200 lines and always loaded for spawning).

### 5.3 Code is orthogonal to the vision

- **Plugin system** (`plugin--*` skills, `plugin-security-gate`, `plugins.dependencies` in project.json): real, working, but completely unmentioned in PRODUCT.md, the Operating Model, or CLAUDE.md. Decisions about plugin trust, lifecycle, and security live in code only.
- **Github App integration** (`github-app.ts` + tests, T-1015): brand-new, no mention in PRODUCT.md or operating-model. Strategically important (replaces PATs) but invisible in vision docs.
- **Coolify hosting integration** (`coolify-preview.ts`, COOLIFY_API_TOKEN onboarding T-833): vision says "Hosting: Vercel and Shopify as first-class" (PRODUCT.md). Coolify is now equally first-class. Drift is not bad — but PRODUCT.md is now wrong.

---

## 6. Phase 5 Root-Cause-Cluster

| # | Cluster | Findings count | Symptoms | Root Cause (hypothesis) | Structural fix | Symptom-fix trap |
|---|---|---|---|---|---|---|
| 1 | **Source-vs-install topology drift** | §3.C, Backend §5, Code-review HIGH-2, DevOps §1+§2 | Subagents work as generic coders, Reporter skill never loads, `/develop` flows degrade silently, design-lead invocations fail | Two parallel paths (`skills/<n>/SKILL.md` source, `.claude/skills/<n>.md` install) and no runtime check that the agent's `Read('...')` actually resolved | Inject skill content via SDK `appendSystemPrompt` or `byRole` map at spawn time — kill all `Read('skills/...')` markdown strings | Patching the markdown path (T-1014's approach) makes it worse: now the path is hard-coded to a place that doesn't exist in customer installs |
| 2 | **Built but not wired** | Backend §1+§2+§3, Code-review HIGH-1, QA §3 | New reasoning Sidekick gives chat-only replies; epic-develop-ship Reporter never renders; user reports "things that worked are gone" | A feature is "done" when the tests in its own file pass. The integration with the consumer is treated as out-of-scope of the feature ticket. T-983 (tools) and T-986 (prompt) shipped with passing tests; nobody tested "chat endpoint → tools registered → model can call them" because that test would span 3 modules | Add an end-to-end Sidekick-chat integration test that sends a message, verifies the tool is invoked, verifies a board row exists. Same pattern for Reporter, Engine endpoints | Wiring tools into chat in the next ticket and shipping it the same way (no e2e test) just postpones the next instance |
| 3 | **Self-install rot** | §3.C (template-hash 2026-04-12), Code-review HIGH-2, DevOps §1 | This very repo has stale agents/skills; `/develop` and `/ship` here behave differently than in customer projects | No CI step runs `setup.sh --update` and asserts no diff. The framework-version-check rule only warns the human, never blocks | CI: `setup.sh --update && git diff --exit-code .claude/` on every PR. If diff exists, fail with instruction to commit | Bumping the template hash by hand is exactly the antipattern self-install-topology.md warns against |
| 4 | **Orchestrator/process bypass** | Incident 2026-04-21, Incident 2026-04-10, decision-authority-enforcement.md | Code on main without ticket; over-engineered systems built when native features exist | Rules are markdown that the model competes to follow against system prompt and skills. When the system prompt doesn't include the rule (because the rule's import wasn't loaded or the agent has no Skill tool), the rule is invisible | Convert Decision-Authority and Branch-Check rules into deterministic PreToolUse hooks (`.claude/hooks/`) that the SDK enforces — not markdown the model has to remember | Adding more rule text to CLAUDE.md is what bloats it past the 200-line ceiling and crowds out the others |
| 5 | **Test-coverage on wrong files** | §3.E, QA §1+§2+§4 | Bug-of-the-week pattern; "fix on fix" loops | Tests cluster on new sidekick code (where they were demanded by the spec); zero tests on worktree-manager, qa-runner, event-hooks, watchdog, drain — the exact files that produce runtime symptoms | Mandatory coverage threshold for `pipeline/lib/*.ts` ≥ 70%; pre-commit hook to refuse new prod code without a test in the same PR | Adding more tests to already-tested modules doesn't help — it has to be coverage on the untested critical files |
| 6 | **Two-truth modules / dead code** | Backend §2+§3, Code-review HIGH-1, MEDIUM-1 | Confusing for maintenance; "I changed it but it didn't help" because the changed copy wasn't the live one | Big rewrites (T-979, T-983) ship next to the legacy module instead of replacing it. The cleanup ticket is "deferred" and never lands | Treat replacement = deletion. T-979 should not have merged without removing the file it replaces | More feats on top of duplicated foundations multiplies the surface |

---

## 7. Phase 6 Sanierungs-Roadmap

### Maßnahme 1 — Skill loading: kill the source-vs-install split

- **Kills cluster:** 1 (Source-vs-install topology drift), partial 4 (process bypass)
- **Effort:** L
- **Risk:** medium — touches every agent prompt, the skill loader, and setup.sh's copy step. Risk: a botched migration leaves agents with no skill at all (worse than wrong path). Mitigation: ship behind a feature flag in `pipeline.skill_injection_mode = legacy_read | injected`; parallel-run for one week; flip default.
- **Order rationale:** First because it's the largest source of silent failure across all installed projects right now. Until this is fixed, every other improvement is built on sand.
- **Erfolgskriterium:** zero `Read('skills/<n>/SKILL.md')` strings in `agents/` and `commands/`; subagent spawns prove (via Sentry breadcrumb) that the skill content was injected, length > 0, before the first model turn. Test: `e2e/skill-injection.test.ts` spawns a backend subagent and asserts the system prompt contains "⚡ Backend Dev joined" content.

### Maßnahme 2 — Wire the Sidekick reasoning tools end-to-end

- **Kills cluster:** 2 (Built but not wired), partial 6 (two-truth)
- **Effort:** M
- **Risk:** medium — flipping `allowedTools` from `[]` to the seven reasoning tools changes Sidekick behavior on every browser-widget message. Risk of regressions on inputs the test corpus didn't cover. Mitigation: shadow-mode for 48h (log what the model would have called, don't execute), then enable.
- **Order rationale:** Second because the user's "I lost trust" signal is mostly about the Sidekick. Restoring the central reasoning loop restores 80% of perceived quality.
- **Erfolgskriterium:** integration test sends "create a ticket for X" to `/api/sidekick/chat`, asserts a `tool_use` event for `create_ticket`, asserts a Board row appeared. Same for `create_epic`. Sidekick replies that *don't* call tools should be < 10% on the existing 15-example corpus.

### Maßnahme 3 — Self-install rot CI gate

- **Kills cluster:** 3 (Self-install rot), reinforces 1
- **Effort:** S
- **Risk:** low — adds a CI step. Risk: noisy if `setup.sh` isn't deterministic. Mitigation: make the diff-check ignore timestamps and version stamps.
- **Order rationale:** Third because it locks in the gains from #1 — once topology is fixed, this prevents regression. Also unblocks development of this repo, which is currently running stale.
- **Erfolgskriterium:** GitHub Action `self-install-up-to-date` is required on `main`; failing it explains "run `setup.sh --update` locally and commit". `framework.updated_at` in this repo's project.json never trails the latest pipeline-affecting commit by more than 1 day.

### Maßnahme 4 — Test coverage on the runtime spine

- **Kills cluster:** 5 (test-coverage on wrong files), partial 2
- **Effort:** L (each of worktree-manager, qa-runner, event-hooks, watchdog needs 200-400 lines of tests)
- **Risk:** low. Adding tests can't break prod. Risk: time spent here is time not spent on features. Mitigation: write tests as the price of the next feat that touches each file (no greenfield test-writing sprint).
- **Order rationale:** Fourth because it's slow and parallelizable; the first three are sequential.
- **Erfolgskriterium:** Vitest coverage report in CI; `pipeline/lib/{worktree-manager,qa-runner,event-hooks,watchdog,drain,config}.ts` each ≥ 60% line coverage. Block-merge below threshold.

### Maßnahme 5 — Dead code cull

- **Kills cluster:** 6 (two-truth modules)
- **Effort:** M
- **Risk:** medium. `sidekick-policy.ts` and `sidekick-converse.ts` (1042 LOC + 1092 test LOC) being deleted would catch any silent dependency. Mitigation: do it only after #2 ships and is observed for one week; tag the commit `[remove-after-1-week-stable]` and only merge after the observation window.
- **Order rationale:** Fifth — cleanup, not a fire.
- **Erfolgskriterium:** `pipeline/lib/sidekick-{policy,converse,tools}.ts` deleted; `/api/sidekick/converse` endpoint removed from server.ts; tests deleted with them. CI green; 48h Sentry shows no errors referencing removed names.

---

## 8. Phase 7 Process-Fixes

| Cluster | What would have caught it | Where it goes |
|---|---|---|
| 1 (topology) | A test that spawns a real subagent and inspects what skill content reached its system prompt | `pipeline/lib/load-skills.e2e.test.ts` (new), assertion via Sentry breadcrumb sink |
| 1 (topology) | CI step: `grep -rn "Read('skills/" agents/ commands/` exits non-zero | `.github/workflows/build-pipeline.yml` add step `verify-no-source-paths-in-prompts` |
| 2 (built-but-not-wired) | Every PR that adds tools to a registry must include an integration test that the registry consumer calls them | `.claude/rules/wire-or-delete.md` (new) — "if you add to a registry, prove it's reachable by a test" |
| 2 (built-but-not-wired) | Schema-level lock: tools registered in `SIDEKICK_REASONING_TOOLS` must appear in the SDK call's `allowedTools` array — type guard | `pipeline/lib/sidekick-chat.ts` — replace `allowedTools: []` with `allowedTools: listSidekickReasoningToolNames()`; type-check both sides |
| 3 (self-install rot) | `setup.sh --check` failing in CI | `.github/workflows/self-install-up-to-date.yml` (new) |
| 3 (self-install rot) | Pre-commit hook on this repo that refuses to commit if `framework.updated_at` is older than the most recent commit touching `agents/`, `commands/`, `skills/`, or `pipeline/` | `.githooks/pre-commit` extension |
| 4 (process bypass) | Branch-check as a deterministic hook, not a markdown rule | `.claude/hooks/pre-tool-use-branch-check.sh` (new), wired into `.claude/settings.json` |
| 4 (process bypass) | Sidekick-routing as a deterministic hook for first user message in a session | `.claude/hooks/on-user-prompt-submit-sidekick-route.sh` (new) |
| 5 (test coverage) | Coverage threshold check in CI | `.github/workflows/build-pipeline.yml` — add `npm run coverage:check` |
| 5 (test coverage) | Mandatory test for every new file under `pipeline/lib/` | `.claude/rules/no-prod-without-test.md` (new) — codifies it |
| 6 (two-truth) | Lint rule: a file marked `@deprecated` in JSDoc fails the build if not deleted within N days | `pipeline/eslint.config.ts` (new lint rule) — uses `git log` to determine deprecation age |

---

## 9. Phase 8 Memory-Update-Vorschläge

| Ziel | Inhalt | Begründung |
|---|---|---|
| Mem0 (user-level, projektübergreifend) | "Just Ship Self-Install-Falle: bei jedem Skill/Agent/Command-Edit zuerst `setup.sh --update` laufen lassen oder ein CI-Gate haben, sonst arbeitet das Repo gegen veraltete Installs." | Wiederkehrend über mehrere Sessions; not-just-ship-spezifisch — gilt für jedes self-installing framework |
| Mem0 | "Bei Sidekick-Architektur-Wave (April 2026): Tools+Prompt gebaut aber nicht in `sidekick-chat.ts` verkabelt — `allowedTools: []`. Pattern: Registry exists, no caller. Vor Approval immer prüfen ob ein Konsumer-Test existiert." | Lehre aus T-983/986; verhindert Wiederholung |
| `.claude/rules/wire-or-delete.md` (NEW) | "Wenn ein Ticket eine Tool-Registry, Endpoint-Liste, oder Hook-Set baut, muss die selbe PR einen Integration-Test enthalten der beweist dass mindestens ein Konsumer die Registry tatsächlich aufruft. Sonst gilt das Ticket als unfertig." | Cluster 2 root cause |
| `.claude/rules/no-source-path-in-prompts.md` (NEW) | "Markdown-Strings in `agents/`, `commands/`, `skills/` dürfen keinen Pfad enthalten der `skills/<x>/SKILL.md` (Source) oder `.claude/skills/<x>.md` (Install) lautet. Stattdessen via Skill-Tool oder via Pipeline-Injection. Hook prüft das pre-commit." | Cluster 1 root cause |
| `.claude/rules/setup-sh-required-after-source-edit.md` (NEW) | "Nach einem Edit in `agents/`, `commands/`, `skills/`, `pipeline/`, oder `templates/` MUSS der nächste Commit einen aktualisierten `framework.updated_at`-Stempel haben (via `setup.sh --update`). Pre-commit-Hook enforced." | Cluster 3 |
| CLAUDE.md (Constitution) | Add a single new line under "Execution posture": "Built artifact ≠ shipped feature — every new tool, endpoint, hook, or skill MUST have at least one integration test proving the consumer reaches it before the ticket can close." | Cluster 2 deserves constitutional protection |
| `docs/just-ship-operating-model.md` | Refine §"Architecture of loaded context" to add: "Skill content is injected into agent prompts at spawn time via `appendSystemPrompt` (or equivalent), NOT loaded by the agent through markdown instructions. The agent never reads its own skill file." | Reflects the structural fix from Maßnahme 1 — keeps the vision and the code aligned |

---

## 10. Caveats & What I Did NOT Verify

- **Did not run sub-agents in parallel.** The spec asked for 4–6 parallel `general-purpose` Agent-tool spawns; I ran a single-context audit. Reason: I'm already running as the audit agent from a parent dispatch (`run_expert_audit` style), and spawning sub-sub-agents collides with the audit-runtime constraint that audit agents have no Agent tool (`expert-audit-scope.md`). The trade-off: less parallelism, but also no risk of sub-agent skill-load failures masking findings. The findings here are mine in one context.
- **Did not query the Board API.** Per spec ("read-only, no mutations") and per `expert-audit-scope.md`. Stuck-ticket detection limited to file-system inspection.
- **Did not read `just-ship-board`, `just-ship-bot`, `just-ship-web` source in depth.** Spot-checked only that `.claude/skills/backend.md` and `.claude/agents/backend.md` exist in `just-ship-board`. Schema audit, supabase migrations, and RLS policies for the Board are out of scope of an engine audit — would need a separate pass.
- **Did not exercise the runtime.** No `npm test` was run. Findings about test coverage are LOC-based (test file exists / doesn't exist), not coverage-percentage-based. A 661-line test file may still leave 30% of prod uncovered.
- **Did not validate Coolify or VPS deployment paths.** `just-ship-ops/infra` was not read.
- **Did not check Sentry instrumentation accuracy.** I trust the breadcrumb names in `audit-runtime.ts` and `sidekick-chat.ts`; did not verify they fire.
- **Did not assess the Reporter system in detail.** T-998/999/997/1003 shipped this week; finding "reporter skill not installed" came from the install gap, not from auditing the Reporter implementation itself.
- **No MCP server validation.** `@shopify/dev-mcp` is referenced in rules; I did not verify it's actually installed and reachable.
- **Single time-point.** This is a snapshot. The state may change before the report is read.

---

**End of report.**
