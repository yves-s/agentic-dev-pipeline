# Sidekick Reasoning Architecture — Design Document

**Status:** Draft
**Date:** 2026-04-23
**Authors:** CEO + CTO + Design Lead (sparring session)
**Supersedes:** `skills/sidekick-intake/SKILL.md` (classifier-first model), `.claude/rules/sidekick-terminal-routing.md` (role-address hard-rule)
**Related:** `docs/incidents/2026-04-21-workflow-bypass-design-lead.md`, T-871 (Decision Authority), T-876/T-879 (autonomous creation, no-confirm)

---

## 1. Problem Statement

A user addressed the Design Lead asking for a mobile-consistency audit. The current Sidekick classified the input as category 2 (epic), created an epic plus a ticket, and asked *"Soll ich `/develop T-{N}` starten?"*. The Design Lead was never at the table. No audit happened. The user got a backlog entry where they wanted an expert analysis.

The classification was logically correct under today's rules (role address + build signal → intake → epic). The output was wrong because the rules model the wrong thing.

### Root cause

The current Sidekick is a **classifier-first system**: the first question it asks itself is *"which of four buckets does this input belong to?"* (ticket, epic, conversation, project). This schema has no representation for:

- **Audit** — "schau dir X an", "review", "ist das konsistent"
- **Consultation** — "Design Lead, wie denkst du über Y"
- **Diagnosis** — "warum passiert das immer wieder"

Everything that isn't `conversation` (the low-confidence fallback) is forced into producing a board artifact. Inputs that wanted expert *work* instead of an artifact got mis-routed.

### Why over-correction happened

The classifier was tightened after the 2026-04-21 workflow bypass incident, where a Design-Lead role address triggered direct implementation on `main`. The fix was correct in spirit (don't let role-address bypass the ticket flow) but too broad in mechanism — it collapsed two distinct intents into one:

1. *"Design Lead, bau mal X"* — build intent → ticket flow is correct
2. *"Design Lead, schau dir X an"* — audit intent → needs the expert *now*, not a ticket first

Both hit the same pattern match (`role + feature-signal → intake`) and both produced tickets.

---

## 2. Research — State of the Art (2026-04-23)

Parallel research across five reference projects and four broad queries converged on the same pattern. The classifier-first approach is considered obsolete for conversational multi-agent systems; the state of the art is **reasoning-first orchestration with specialists exposed as tools**.

### Reference points

| Project | Pattern | Takeaway |
|---|---|---|
| [Anthropic Multi-Agent Research](https://www.anthropic.com/engineering/multi-agent-research-system) | Lead researcher reasons, spawns task-shaped subagents with Extended Thinking | *"Instilling good heuristics rather than rigid rules"* — no classification step, dynamic specialist instantiation |
| [AWS Agents-as-Tools](https://dev.to/aws/build-multi-agent-systems-using-the-agents-as-tools-pattern-jce) | Specialists wrapped as callable functions, orchestrator picks via LLM reasoning on docstrings | *"Decision-making through reasoning, not classification scores"* — direct inspiration for our tool layer |
| [OpenAI Swarm / Agents SDK](https://cookbook.openai.com/examples/orchestrating_agents) | Handoff pattern: each agent has `transfer_to_X()`, no central classifier | Confirms: the current specialist decides when to hand off, not a pre-stage router |
| [LangGraph Supervisor](https://reference.langchain.com/python/langgraph/supervisor/) | Central orchestrator but dynamic routing via `Command()` — supervisor is an LLM call, not a classifier | The supervisor's only job is routing, but it reasons — doesn't pattern-match |
| [Botpress Routing Guide 2026](https://botpress.com/blog/ai-agent-routing) | Explicit: *"static intent classifiers have become obsolete"* | Industry consensus on the direction |
| [Oh-My-OpenCode](https://github.com/opensoft/oh-my-opencode) | Sisyphus (Opus) orchestrator with specialists (Oracle, Frontend Engineer, Librarian), tool-driven routing | Closest aesthetic match to our setup |
| [GSD](https://github.com/gsd-build/get-shit-done) | Workflow-phase model, but has `/gsd-discuss-phase` — the one "audit/exploration" move we lack | Validates that a `discuss` phase is a real missing primitive |
| [Thorsten Ball — Amp](https://ampcode.com/notes/how-to-build-an-agent) | *"LLM + loop + tools, no classifier"* | The purist extreme — too free for us, but validates the tool-use philosophy |

### Synthesis

The Sidekick should be a reasoning LLM agent with:

1. A **tool roster** (artifact tools + expert tools), not a category enum.
2. A **system prompt with heuristics**, not a procedural decision tree.
3. **Hard guardrails only for destructive/persistent actions** (branch, ship, merge). Routing is reasoning, not pattern-matching.
4. **Visible expert runs** as a first-class move, not hidden internal consultation.

This mirrors Anthropic's own research-system architecture and aligns with the AWS Agents-as-Tools pattern.

---

## 3. Target Architecture

### 3.1 The seven tools

The Sidekick has exactly **seven tools**. Four produce persistent board artifacts. Three spawn specialized expert agents.

#### Artifact tools (persistent, board-visible)

| Tool | Signature | When the Sidekick calls it |
|---|---|---|
| `create_ticket` | `(title, body, priority, project_id, tags?)` | User wants *one* concrete change to something existing with a clear outcome. Bug fixes, copy tweaks, single feature adds. |
| `create_epic` | `(title, body, children[], project_id \| null)` | User wants *multiple* connected changes. Feature name appears. Would naturally split into 3+ child tickets. Cross-project epics set top-level `project_id: null`. |
| `create_project` | `(name, description, workspace_id, confirmed)` | Genuinely new product, new audience, new workspace scope. **Only tool that requires explicit user confirmation** (`confirmed: true`). |
| `start_conversation_thread` | `(topic, initial_context, project_id)` | Direction uncertain, needs multi-turn dialog to shape. Maps to existing Engine thread infrastructure (`draft → waiting_for_input → ready_to_plan → delivered`). |

#### Expert tools (spawn read-only specialists)

| Tool | Signature | When the Sidekick calls it |
|---|---|---|
| `run_expert_audit` | `(scope, expert_skill, project_id)` | User wants analysis, review, or consistency check. "Schau dir X an", "audit", "review", "ist das konsistent". Returns structured findings. Read-only — specialist cannot write, cannot create tickets. |
| `consult_expert` | `(question, expert_skill, project_id)` | User has a knowledge or diagnosis question for a specific role. "Wie denkst du über X", "warum passiert Y", "was ist die best practice für Z". Returns expert answer as text. |
| `start_sparring` | `(topic, experts[], project_id?)` | User wants to think through a strategic question. Loads the sparring skill with specified expert skills as peers. |

**Expert skills are parameters, not tools.** The eight expert skills (`design-lead`, `product-cto`, `backend`, `frontend-design`, `creative-design`, `data-engineer`, `ux-planning`, `ticket-writer`) are passed as the `expert_skill` (or `experts[]`) argument. The Sidekick reasons about which specialist fits the task. This keeps the tool surface narrow and the specialist surface extensible.

### 3.2 Expert audit contract

Every `run_expert_audit` call returns a structured report. This is the contract, regardless of which expert skill was invoked:

```typescript
type AuditReport = {
  scope: string;              // what the audit covered, in user-readable form
  expert: string;             // which expert skill produced this
  findings: Array<{
    title: string;            // short, scannable
    description: string;      // one or two sentences
    severity: 'low' | 'medium' | 'high' | 'critical';
    evidence?: {
      files?: string[];       // paths touched during audit
      lines?: string;         // e.g. "42-51"
      quote?: string;         // relevant code/text excerpt
    };
    suggested_fix?: string;   // hint only, non-binding
  }>;
  summary: string;            // one-paragraph executive summary
}
```

The Sidekick renders this report in first-person expert voice (see section 3.5) and asks a business follow-up question (which findings to ship as tickets).

**Constraints on audit agents (enforced via new rule `expert-audit-scope.md`):**

- Read-only. No file edits, no writes, no board API calls, no ticket creation.
- Time-boxed (target: 30s–2min, hard cap: 5min).
- If the audit agent believes something must be fixed immediately, it reports that as a `critical` finding with `suggested_fix`. The Sidekick (not the audit agent) decides what to do with it.

### 3.3 Guardrails — what stays procedural

Hard rules remain for **state-changing actions**. Routing rules dissolve into the Sidekick's reasoning layer.

| Rule | Status | Rationale |
|---|---|---|
| `branch-check-before-edit.md` | **Keep hard** | Writing to `main` is always a risk, regardless of reasoning quality |
| `ship-trigger-context.md` | **Keep hard** | Merge to `main` is irreversibly visible |
| `no-premature-merge.md` | **Keep hard** | See ship-trigger |
| `ticket-number-format.md` | **Keep hard** | Format-only, zero cost |
| `detect-stuck-tickets.md` | **Keep hard** | Session-start check, read-only |
| `audit-completeness.md` | **Keep hard** | Quality gate for audit agents |
| `no-premature-merge.md` | **Keep hard** | See above |
| `decision-authority-enforcement.md` | **Keep hard, but clarified** | Applies inside tickets AND inside the Sidekick's tool-selection reasoning |
| `post-develop-feedback.md` | **Keep hard** | Feedback = implementation task, not a question |
| **New:** `expert-audit-scope.md` | **Add** | Defines read-only constraint on audit agents |
| `sidekick-terminal-routing.md` | **Replace** | Routing becomes Sidekick system-prompt heuristics, not a hard rule |
| Sidekick-Intake four-category classification | **Delete** | Replaced by reasoning + seven tools |
| Role-address hard-rule (`role + feature-signal → intake`) | **Replace** | Becomes Sidekick system-prompt heuristic |
| `brainstorming-design-awareness.md` | **Keep** | Still relevant to brainstorm skill |
| "Internal expert consultation (never visible to user)" pattern | **Delete** | Replaced by visible `run_expert_audit` / `consult_expert` |

### 3.4 System-prompt heuristics (replacing routing hard-rules)

The Sidekick's system prompt encodes reasoning heuristics instead of regex rules. Example heuristic structure:

> **Role addresses are expertise signals, not routing directives.**
> When the user addresses a role by name ("Design Lead, …", "CTO, …", "Backend, …"), it signals which expert they want at the table. It does not automatically determine the intent.
>
> - *"Design Lead, bau mal X"* → build intent → `create_ticket` with the Design Lead consulted on ACs during finalization
> - *"Design Lead, schau dir X an"* → audit intent → `run_expert_audit(scope=X, expert=design-lead)`
> - *"Design Lead, wie denkst du über Y"* → consultation intent → `consult_expert(question=Y, expert=design-lead)`
>
> The verb carries the intent (bau / schau / denk). The role carries the expertise choice. Read both.

> **Audits and consultations are first-class moves.** If the user wants analysis, review, or a specialist's take, call `run_expert_audit` or `consult_expert` directly. Do not create tickets speculatively before the expert has looked.

> **Artifact creation is autonomous (T-876/T-879).** When the tool to call is a `create_*` tool, call it without asking the user to confirm — except `create_project`, which requires explicit confirmation because the scope is structurally larger.

> **Business questions allowed, implementation questions forbidden (T-871).** The Sidekick may ask about target audience, timing, scope boundary, replaces-or-augments, success criteria. The Sidekick never asks about tech stack, database, hosting, visual design, layout, component choice, flow patterns, architecture, or auth — those are delegated internally to experts.

### 3.5 Expert-run UX

The expert run is **visible and narrated in first-person voice**. This is the core UX difference from the old internal-consultation model.

**Terminal output format:**

```
User: Design Lead, mach ein Audit der Mobile Experience auf dem Board.

Sidekick: ⚡ Design Lead joined — läuft Audit auf Mobile-Viewports

[progress indicator, ~30s–2min]

⚡ Design Lead: Mobile-Audit fertig.

5 Findings:
1. Card-Buttons auf /tickets sind 32px hoch, Rest der App nutzt 40px Primary/Secondary.
   → Inkonsistenz. Severity: medium.
2. Empty-State auf /epics hat px-4, Rest nutzt px-6 auf Mobile.
   → Padding-Skala gebrochen. Severity: low.
3. Filter-Sheet öffnet nicht swipe-down-closeable auf iOS Safari.
   → Interaction-Pattern nicht durchgezogen. Severity: high.
4. Status-Dropdown im Ticket-Detail clipt auf kleineren Screens (<375px).
   → Overflow-Bug. Severity: high.
5. Keyboard-Shortcuts-Overlay ist auf Mobile eingeblendet, obwohl Touch-Only.
   → Dead-Feature auf Mobile. Severity: medium.

Welche davon sollen ins Board? Alle 5, nur high-severity, oder willst du einzeln durchgehen?
```

**Three design decisions baked in:**

1. **Expert speaks in first person.** `⚡ Design Lead: ...` — not `[Design Lead sagt]` or hidden output. Gives the user the feel of a real person at the table.
2. **Report is structured but conversational.** Numbered findings with severity, no JSON dump, no formal audit report. Linear's tonality.
3. **Follow-up is a business question.** "Welche sollen ins Board" is scope (CEO decision). Not "soll ich die als Tickets oder als Epic anlegen" (implementation, executor scope). On "alle 5" → Sidekick autonomously decides: 5 related UI fixes → epic with 5 children.

**Browser widget parity:** The same flow runs in the web widget. The only difference is rendering (chat bubbles instead of terminal lines). The tool, the report, the follow-up question, the artifact logic — all identical.

### 3.6 Thread model — scoped to conversation tools only

Today every Sidekick interaction goes through the Engine thread infrastructure. In the new model, threads are **only** for the two conversation tools:

- `start_conversation_thread` — uses the existing Engine thread with full status machine (`draft → waiting_for_input → ready_to_plan → planned → approved → delivered`). Keeps browser-widget pause/resume behavior and review-flow follow-ups.
- `start_sparring` — uses a thread for multi-turn sparring sessions. Same infrastructure.

The other five tools are **stateless**. `create_ticket`, `create_epic`, `create_project`, `run_expert_audit`, `consult_expert` are one-shot calls with direct responses. No thread overhead for interactions that don't need multi-turn state.

If, after an audit, the user says *"lass uns über Finding 3 nochmal reden"* — that *starts* a new conversation thread. Clean separation.

### 3.7 Browser widget parity

The browser Sidekick widget and the terminal Sidekick share the same:

- System prompt
- Tool definitions
- Heuristics
- Report format

The only differences are transport and rendering. The API surface is `POST /api/sidekick/chat` (which already exists — this ticket refactors its internals).

### 3.8 Open decisions — deferred to V2

These came up in sparring and were deferred with explicit reasoning:

| Decision | V1 answer | Revisit when |
|---|---|---|
| Audit reports as their own board artifact type | No — findings become tickets, no new schema | Multiple users report wanting to re-find past audits |
| Conversation-thread status machine | Keep as-is | After V1 is in production for 2 weeks, re-evaluate if it's overkill |
| `create_project` confirmation step | Keep the one confirmation prompt | If user feedback says the prompt feels unnecessary |

---

## 4. Non-Goals

- This is not a UI redesign of the board. Board artifact display is unchanged.
- This is not a change to the `/develop` or `/ship` pipeline. Those remain as they are.
- This is not a change to the eight expert skills themselves. They are loaded and executed as today; only the *entry point* (Sidekick) changes.
- This is not a change to authentication, API keys, or the Engine's endpoint structure.
- This is not migration work — the project is pre-alpha, we break cleanly.

---

## 5. Implementation Plan — Epic + Children

Since pre-alpha, we do a clean rebuild of the Sidekick layer. No parallel run, no feature flags.

### Epic: Sidekick Reasoning Architecture Rebuild

**Body:** Replaces the current classifier-first Sidekick with a reasoning-first orchestrator exposing seven tools. See `docs/superpowers/plans/2026-04-23-sidekick-reasoning-architecture.md`.

### Children (proposed split — 7 tickets)

1. **Tool layer definition (backend)**
   Define the seven tool schemas in the Engine (`pipeline/lib/sidekick-tools.ts` or equivalent). Each tool has a Zod schema for parameters and a handler that either calls existing board APIs (for artifact tools) or spawns an expert subagent (for expert tools). No new board endpoints needed for artifact tools (reuse `/api/sidekick/create` etc.); new internal route needed for audit execution.
   Size: M.

2. **Audit agent runtime (backend + data-engineer)**
   Implement the read-only audit agent runner. Takes `(scope, expert_skill, project_id)`, loads the expert skill, runs a Claude subagent call with read-only tool permissions, returns structured `AuditReport`. Includes the time-box, the scope constraint, and the Sentry instrumentation. New rule file `expert-audit-scope.md` written.
   Size: M.

3. **Sidekick system prompt rewrite (backend)**
   New system prompt for the orchestrator LLM. Encodes the seven-tool roster, the role-address heuristics, the business-vs-implementation question policy. Replaces `pipeline/lib/sidekick-converse.ts`'s system prompt. Includes the corpus of example inputs → tool-calls for prompt stability.
   Size: M.

4. **Kill the classifier (backend)**
   Remove `skills/sidekick-intake/SKILL.md`, delete the classifier endpoint (`POST /api/sidekick/classify`), remove the four-category branching code. Update `pipeline/lib/sidekick-policy.ts` to drop classifier-specific logic.
   Size: S.

5. **Terminal rewire (backend)**
   Update `.claude/scripts/sidekick-api.sh` and the terminal Sidekick flow in `.claude/rules/sidekick-terminal-routing.md`. Replace the classification-and-branch logic with a direct chat stream against the new reasoning-first Sidekick. Role-address hard-rule file is deleted; heuristic lives in system prompt.
   Size: S.

6. **Browser widget rewire (frontend)**
   Update the web-widget's chat endpoint usage to match the new API. No visual changes — the widget already streams. Remove any client-side category handling. Verify parity with terminal.
   Size: S.

7. **Test corpus rewrite (backend + qa)**
   `pipeline/lib/sidekick-policy.test.ts` gets rewritten for the new model. Test scenarios cover: role-address + build verb → `create_*`; role-address + analysis verb → `run_expert_audit`; role-address + question verb → `consult_expert`; implementation questions never leak; business questions allowed. Drop the category-specific tests.
   Size: M.

**Dependencies:**
- (1) must land before (3), (4), (5), (6), (7).
- (2) must land before (7) — audit test scenarios need the runtime.
- (3) must land before (4), (5), (6) — kill old model only once the new one works.
- (7) runs after all implementation, validates the policy end-to-end.

**Suggested order:** 1 → 2 → 3 → 4 → 5 → 6 → 7.

**Total estimated size:** 4× M + 3× S ≈ one focused week of development.

---

## 6. Success Criteria

- A user saying *"Design Lead, mach ein Audit der Mobile Experience"* triggers `run_expert_audit(scope="Mobile Experience", expert=design-lead, project_id=...)`, sees `⚡ Design Lead joined`, receives a first-person findings report, and is asked *"Welche davon sollen ins Board?"* — not a speculatively-created epic.
- A user saying *"fix the typo on the header"* still produces a ticket in one shot, no expert detour.
- A user saying *"build a notifications system with settings, bell, email, inbox"* still produces an epic with children in one shot.
- A user saying *"ich hab da eine Idee"* still opens a conversation thread.
- A user saying *"neues Projekt: Aime Coach"* still gets the one confirmation prompt, then a project + init-epic + three children.
- Zero implementation questions leak to the user in any of the above flows.
- Browser widget and terminal produce identical tool calls for identical inputs.
- The role-address hard-rule file and the four-category classifier no longer exist.
