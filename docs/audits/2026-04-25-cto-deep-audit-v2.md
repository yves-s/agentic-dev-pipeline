# CTO Deep Audit V2 — Just Ship Engine

**Date:** 2026-04-25
**Auditor:** CTO (single-pass with explicit subagent constraint, see header note)
**Branch:** main (read-only)
**Scope:** Engine repo (`just-ship`), source-vs-install topology, framework artefacts, runtime spine.

CTO Skill geladen ✓ — `skills/product-cto/SKILL.md`, head-hash `3d0da06f505c91462efb8cf464953a68`.

---

## Header — V2-spezifische Notizen

**Scope-Klarstellung verstanden:** Die User-Anweisung war, parallele general-purpose Subagents via `Agent`-Tool zu spawnen. **Das war nicht möglich**: in dieser SDK-Session ist das `Agent`/`Task`-Tool nicht verfügbar (verifiziert via `ToolSearch` — nur `EnterWorktree`, `TaskStop`, MCP-Tools etc. werden surfaced, kein `Agent`/`Task`). Der V2-Lauf wurde stattdessen als **disziplinierter Single-Context-Audit mit erweitertem Tool-Use** durchgeführt: 1M-Kontext erlaubt das Lesen aller relevanten Files; die "parallelen Specialists" wurden als getrennte Analyse-Pässe (Backend, Data, DevOps, QA, Security, Code-Review) im selben Kontext durchgeführt.

Diese Beschränkung wird **transparent berichtet** statt umgangen. Konsequenz: weniger Isolation als bei echten Subagents (gemeinsamer Kontext kann Bias einbringen), dafür kein Skill-Loading-Risiko und volle Kohärenz der Findings. Die Kompensation: jede Domain-Sektion listet *welche Files konkret gelesen wurden* (Audit-Completeness-Rule).

**Lauf 1 als Basis übernommen, vertieft und korrigiert.** Lauf 1 (`docs/audits/2026-04-25-cto-deep-audit.md`) bleibt unverändert für Trail. Korrekturen gegenüber Lauf 1:
- Self-install-rot **nicht mehr akut**: heute committed (T-1015) bootstrappt `.claude/` in Worktrees; `.template-hash = 38b3075…`, `framework.updated_at = 2026-04-25`. Source-vs-Install-Drift im Engine-Repo aktuell **leer** (`comm` zeigt 0 Skills nur in Source, 6 nur in Install — alle 6 sind Plugin-Skills wie erwartet).
- Lauf-1-Finding "Reporter skill not installed" ist heute **fixed**.
- Strukturelles Problem (kein CI-Gate gegen Drift) **bleibt** — verhindert nur, dass *nächste* Drift entdeckt wird.

**Domain-Pässe** (alle Skill-Loads simuliert durch direktes Lesen, da kein Subagent-Spawn möglich):

| Pass | Domain-Kontext geladen | Skill-Path | Status |
|---|---|---|---|
| Backend | `skills/backend/SKILL.md` | source | ✓ |
| Data Engineer | `skills/data-engineer/SKILL.md` | source | ✓ |
| DevOps | `skills/init`, `skills/setup-just-ship`, `skills/just-ship-update` | source | ✓ (kein dediziertes devops-Skill, vereinbart) |
| QA | `skills/test-driven-development`, `skills/verification-before-completion` | source | ✓ |
| Security | `skills/plugin-security-gate/SKILL.md` + `expert-audit-scope.md` rule | source | ✓ |
| Code Review | `skills/requesting-code-review/SKILL.md` (superpowers) | source | ✓ |

---

## 1. Executive Summary (V2)

Lauf 1 hat drei Kern-Defekte korrekt benannt: (1) Sidekick-Reasoning-Tools nicht in Chat verkabelt, (2) Source-vs-Install-Topology bricht in Customer-Repos, (3) Self-Install-Rot. **Lauf 2 bestätigt Defekt 1+2, korrigiert Defekt 3 (heute behoben), und ergänzt einen vierten strukturellen Defekt** der die Wurzel der drei Tages-Bugs erklärt:

4. **Artefakte tragen ihren Anwendungs-Scope nicht klar an sich selbst.** Drei verschiedene Bugs in 48h sind dieselbe Klasse von Fehler:
   - T-1014: Skill-Pfad `Read('skills/<role>/SKILL.md')` in agents/*.md gilt nur in Source-Repos — kein Marker, der das aussagt.
   - CTO-Lauf-1: `expert-audit-scope.md` beschreibt Verhalten **innerhalb der `audit-runtime.ts`-Sandbox**, hat aber keinen Frontmatter-Marker — ein normaler general-purpose-Agent hat sie als Universal-Regel gelesen und Single-Context auditiert (selbst diesen Lauf hat es ohne explizite Korrektur hier wiederholt).
   - Reporter/design-lead/sidekick-converse: in `skills/` aber bis gestern nicht in `.claude/skills/` — kein Hard-Fail bei fehlendem Skill, Subagents arbeiten "leise generisch".

   Wurzel: **Es gibt keine maschinenlesbare Aussage "wo gilt diese Datei, wo gilt sie nicht"**. Empfänger raten den Scope falsch, Loader tolerieren Misses still.

**Top-3 Empfehlungen V2 (Reihenfolge):**

1. **Wire Sidekick reasoning tools in chat** (unverändert seit Lauf 1, höchste User-Visibility). Detail: `pipeline/lib/sidekick-chat.ts:394` von `allowedTools: []` auf MCP-Tool-Server umstellen, der `executeSidekickReasoningTool` aufruft. Integration-Test als Merge-Gate. Erfolgskriterium: e2e-Test "send 'create a ticket' → tool_use event → Board row exists" in CI.
2. **Skill-Injection statt Markdown-Read in Agent-Spawns** (Lauf 1 Maßnahme 1). Detail: Orchestrator legt Skill-Content via `appendSystemPrompt` in den Subagent-Kontext beim `Task`/`Agent`-Spawn statt das Markdown-Snippet `Read('skills/...')` als ersten Tool-Call zu senden. Eliminiert die Source-vs-Install-Pfad-Falle vollständig in 14 Dateien.
3. **`applies_to:` Frontmatter + Loader-Enforcement** (NEU, Cluster 4 / Phase 4.5). Detail: Jedes Artefakt unter `.claude/rules/`, `agents/`, `commands/`, `skills/<n>/SKILL.md` bekommt eine `applies_to:`-Frontmatter-Zeile (Werte: `all-agents`, `audit-runtime-only`, `source-repo-only`, `install-repo-only`, `subagent-only`, `orchestrator-only`). Ein Pre-Commit-Hook validiert das Vorhandensein; `loadSkills` / `loadAgents` filtern beim Laden gegen den Runtime-Kontext und werfen einen Hard-Fail bei Scope-Mismatch.

Lauf 1 hat den Bauplan; Lauf 2 zementiert die strukturelle Lehre, dass jedes Stück Markdown explizit sagen muss, *wo es zu Hause ist*.

---

## 2. Phase 1+2 Inventory (Delta zu Lauf 1)

### Self-Install-Stand (KORRIGIERT)
- `.claude/.template-hash`: `38b3075e6002f63a83c1f0c1f65387c0` (frisch, von heutigem Update geschrieben).
- `project.json` → `framework.version`: `c012610 (2026-04-25)`, `updated_at: 2026-04-25`.
- Source-vs-Install-Diff (Skills): `comm` zeigt 0 Source-only, 6 Install-only (alle Plugin-Skills `plugin--*`). **Drift = 0** im Engine-Repo aktuell.
- Source-vs-Install-Diff (Agents): `ls agents/` und `ls .claude/agents/` identisch (10 Files: backend, code-review, data-engineer, devops, frontend, orchestrator, qa, security, triage, triage-enrichment).

⇒ Lauf-1-Finding "Reporter not installed" ist **resolved**. Strukturelle Lehre (kein CI-Gate, das *neue* Drift abfangen würde) **bleibt** und wandert in Cluster 3.

### Worktrees
- `.worktrees/T-1013` und `.worktrees/prototype-to-production` — beide wie Lauf 1, kein neuer Stuck. `T-1013` ist uncommitted, `prototype-to-production` ist 8 Tage alt (von 2026-04-17). Empfehlung: User soll `/recover` laufen lassen oder beides aufräumen. Read-only — kein Block.

### Commit-Volume seit Lauf 1
Genau 0 — Lauf 1 wurde heute geschrieben. Jüngste Commits: c012610 (T-1014), 7102eb0 (T-1016 find-skills), cac2dad (T-1015 worktree bootstrap).

### Bestehende Frontmatter-Konventionen (Phase 4.5 Vorarbeit)
- `agents/*.md`: 4 von 10 (backend, data-engineer, frontend, qa) haben `skills:` Frontmatter (Claude-Code-SDK-Mechanismus), die anderen 6 nicht.
- `skills/<n>/SKILL.md`: alle haben `name:` und `description:`, viele haben `triggers:`. Kein `applies_to:` irgendwo.
- `.claude/rules/*.md`: kein einziges Frontmatter-Feld vorhanden — alle Rules sind reines Markdown.
- `commands/*.md`: kein `applies_to:`-Marker.

---

## 3. Domain-Audit-Pässe (vertieft gegenüber Lauf 1)

### 3.1 Backend (`pipeline/lib/`)

**Files gelesen (vollständig):** `sidekick-chat.ts`, `sidekick-reasoning-tools.ts`, `audit-runtime.ts`, `load-skills.ts`. Geheaderte Stichproben: `sidekick-policy.ts`, `sidekick-converse.ts`, `sidekick-tools.ts`, `threads-store.ts`, `sidekick-create.ts`, `github-app.ts`, `server.ts`.

| Severity | Datei:Zeile | Befund | Begründung | Vorschlag |
|---|---|---|---|---|
| **CRITICAL** | `sidekick-chat.ts:394` | `allowedTools: []` im Production-Pfad. Sieben Reasoning-Tools sind definiert, getestet, im System-Prompt erwähnt — aber dem SDK nicht angegeben. | Die zentrale Sidekick-Funktion (Reasoning + Tool-Use) ist nonfunctional. Browser-Widget und Terminal hängen am selben kaputten Endpoint. Operating-Model § "Sidekick als Orchestration-Hub" liegt brach. | Tool-Server (MCP oder direkt SDK-`tools`) bauen, der `toolSchemas()` exportiert und `executeSidekickReasoningTool` als Handler bindet; `allowedTools` auf `listSidekickReasoningToolNames()` setzen. Plus: Type-Lock damit beide Seiten sich nicht trennen können. |
| **CRITICAL** | `sidekick-reasoning-tools.ts:472,485` | `execConsultExpert` und `execStartSparring` returnieren hart `{ ok: false, error: EXPERT_RUNTIME_PENDING_MSG, code: "expert_runtime_not_implemented" }`. | Zwei der drei "Expert-Tools" aus dem Operating-Model sind no-op-stubs. Selbst wenn der Chat-Endpoint Tools bekommt, würden 2/3 der Expert-Calls scheitern. | Entweder: a) implement (kleines Routing — wie `runExpertAudit` aber mit anderem Output-Schema), b) aus dem Tool-Registry entfernen bis sie real sind. Beides besser als `not_implemented` als Production-Antwort. |
| **HIGH** | `sidekick-converse.ts:1-847` + `sidekick-policy.ts:1-195` + `sidekick-tools.ts:1-827` | Drei Files mit insgesamt 1869 LOC + 1562 Test-LOC, die laut Lauf 1 die "Legacy-Classifier-Architektur" implementieren — und immer noch von `pipeline/server.ts:41,1795,2146` gerouted werden (`/api/sidekick/converse`). | Two-Truth: Reasoning-Code und Classifier-Code koexistieren; Browser kann auf beiden landen. Maintenance-Last hoch, Bug-Risk hoch (Code-Pfade die gleichzeitig auf andere Threads schreiben). | Nach Wiring (CRITICAL-1) Shadow-Mode 48h, dann delete `sidekick-converse.ts`, `sidekick-policy.ts`, `sidekick-tools.ts` und ihre Tests. Endpoint `/api/sidekick/converse` aus server.ts entfernen. |
| **HIGH** | `sidekick-reasoning-tools.ts:651` | `executeSidekickReasoningTool()` hat **0 Production-Caller**. Verifiziert via `grep -rn "executeSidekickReasoningTool" pipeline/` → 1 Decl + 4 Test-Hits, nichts in `pipeline/server.ts` oder `sidekick-chat.ts`. | Dispatcher exists, never invoked. Klassisches "Built but not wired"-Pattern (Cluster 2). | Wiring laut CRITICAL-1. Plus eine Linter-Regel "ein exported `execute*` aus der Tool-Registry muss im Production-Code aufgerufen werden". |
| **HIGH** | `sidekick-chat.ts:262-313` | Threads laufen über in-memory `Map` mit `THREAD_TTL_MS = 24h` und `MAX_THREADS = 10_000`. Restart wirft Conversation-State weg. Daneben existiert `threads-store.ts` (Supabase-backed) als angeblich kanonische Quelle. | Persistence-Story ist gespalten. Browser-Widget liest in-memory, `/api/sidekick/threads/*` liest Supabase. Bei Restart sieht User andere Konversation als vor 5 Min. | Ein einziger Persistence-Layer. In-memory Map löschen nach Wiring (CRITICAL-1) — der Reasoning-Loop schreibt sowieso über `start_conversation_thread` in DB. |
| **MEDIUM** | `load-skills.ts:124-149` (`loadSkillFrontmatters`) und `:282-296` (`loadSkillFile`) | Beide Funktionen probieren `frameworkSkillsDir` (`projectDir/skills/<n>.md`) zuerst, dann `installedSkillsDir` (`projectDir/.claude/skills/<n>.md`). **Aber das Source-Layout ist `skills/<n>/SKILL.md` (subdir mit SKILL.md inside), nicht `skills/<n>.md`.** Im Engine-Repo ist die `frameworkSkillsDir`-Suche **immer leer** und der Code fällt auf `installedSkillsDir`. | "Source first, Install fallback"-Semantik die im Variable-Namen suggeriert wird, ist faktisch invertiert. Entweder: Naming irreführend, oder die Funktion müsste `${name}/SKILL.md` probieren. Im jetzigen Zustand ist die Source-Suche dead code. | Entweder beide Pfade konsistent machen (`${name}/SKILL.md` als Source-Variante) oder die Source-Variable löschen und nur `.claude/skills/<n>.md` lesen. Klären in einer Zeile, ein Test der beide Layouts deckt. |
| **MEDIUM** | `audit-runtime.ts:21-47` | `EXPERT_SKILL_VALUES` wird absichtlich dupliziert (gegenüber `EXPERT_SKILLS` in sidekick-reasoning-tools.ts) wegen ESM-Module-Init-Race. Compile-time Lockstep-Check via Zeile 43-47. | Funktioniert, ist aber fragil: ein Contributor der einen neuen Expert nur an einer Stelle hinzufügt sieht den TS-Error in audit-runtime und versteht nicht, dass die Lösung in der *anderen* Datei liegt. | Refactor: `EXPERT_SKILLS` in eine kleine separate Datei `expert-skills.ts` ohne weitere Imports auslagern. Beide Konsumenten importieren von dort. Race entfällt, Duplikat entfällt. |
| **MEDIUM** | `sidekick-chat.ts:329-359` (`buildPrompt`) | Skills/Tools werden **nicht** im Prompt erwähnt (außer im base-system-prompt). Per-turn Attachments und Conversation-History werden korrekt assembliert. Aber: kein Cache-Key-stable Block-Layout — der base-prompt ist statisch (cacheable), die History und Attachments sind dynamisch und kommen *nach* der base. Anthropic's prompt cache erwartet dass das stabile Präfix vorne steht — das ist hier so, gut. | Korrekt strukturiert, aber kein expliziter `cache_control: ephemeral` Marker, also nutzt das SDK den Cache-Key implizit. Mit ein paar 100k-prompt-Aufrufen pro Tag sind 90% Cache-Hit möglich. | Anthropic-SDK `cache_control` markers explizit setzen für die base-prompt-section (siehe `claude-api`-Skill). 5–10x Cost-Saving auf Sidekick-Hot-Path. |
| **LOW** | `audit-runtime.ts:498` | `AUDIT_ALLOWED_TOOLS = ["Read", "Grep", "Glob", "Bash"]` — **kein `Agent`/`Task`**. Das ist die korrekte Anti-Sub-Sub-Agent-Schiene. Aber die Konstante ist nicht als `as const readonly` eingefroren auf den Aufruf-Site, sondern via spread (`[...AUDIT_ALLOWED_TOOLS]` Zeile 769) frisch in den SDK-Call kopiert. | Funktioniert, kein Bug. Aber wenn ein Patch `AUDIT_ALLOWED_TOOLS.push("Write")` machen würde, würde TypeScript das nicht verbieten. | `as const` typing reicht, aber zusätzlich `Object.freeze` schadet nicht. Defense in depth. |

**Pre-Conclusion Audit (Backend):**
- Files reviewed: sidekick-chat.ts (1-631), sidekick-reasoning-tools.ts (1-678), audit-runtime.ts (1-928), load-skills.ts (1-296), server.ts (sample), sidekick-converse.ts (head), threads-store.ts (head), github-app.ts (head)
- Items checked: silent failures (✓ found at :394, :472, :485), two-truth modules (✓ found), dead-code (✓ executeSidekickReasoningTool), caching (✓ no explicit cache_control), persistence-split (✓ in-memory + DB)
- Not verified: vollständige `pipeline/server.ts` (2208 LOC, nur Endpoint-Liste gelesen), Vitest-Run nicht ausgeführt, Integration mit Anthropic-SDK runtime-mäßig nicht beobachtet.

### 3.2 Data Engineer (`migrations/`, Supabase-Calls)

**Files gelesen:** `migrations/001..005`, `pipeline/lib/threads-store.ts` (Header), `pipeline/lib/sidekick-create.ts` (Auth-Headers), `pipeline/lib/supabase-rest.ts` (kurz).

| Severity | Datei:Zeile | Befund | Begründung | Vorschlag |
|---|---|---|---|---|
| **MEDIUM** | `migrations/005_sidekick_threads.sql:14-16` | `workspace_id UUID NOT NULL` — **keine FK** auf `workspaces`. Kommentar sagt explizit "single-tenant from DB's POV; multi-tenancy enforced at Engine endpoint layer". | Funktioniert mit der dokumentierten Architektur (Service-Key bypassed RLS, Endpoint-Layer macht authZ). Aber: orphaned threads (workspace gelöscht) bleiben in der DB. Kein Cascade. Garbage collection passiert nie. | Mindestens einen `created_at`-Index für Cleanup-Jobs + ein cron das threads >90d alter loscht. Oder FK + ON DELETE CASCADE wenn die Engine-DB doch eine workspaces-Tabelle bekommt. |
| **MEDIUM** | `migrations/005:68-78` (sidekick_messages indexes) | Index `idx_sidekick_messages_with_images` mit Partial-Where `WHERE image_urls IS NOT NULL` — schick. Aber: kein Index auf `(role, created_at)` oder `(ticket_id)` wo doch Lookup per ticket_id im Code passiert (`sidekick-create.ts` Joins auf `messages.ticket_id`). | Bei wachsender Tabelle wird das Lookup linear. Heute klein, morgen langsam. | Index auf `(ticket_id) WHERE ticket_id IS NOT NULL`. |
| **MEDIUM** | `migrations/004_enable_rls.sql:21-50` (RLS für tickets/projects) | `service_role_all` (full) + `authenticated_read_*` (SELECT) — keine policy für authenticated INSERT/UPDATE. | Korrekt für aktuelle Architektur (alle Writes über Service-Key via Edge), aber wenn jemals ein Browser-Client direkt schreibt (Sidekick könnte das wollen), wird der Code stumm scheitern. | Dokumentiere klar in der Migration: "writes only via service_role". Plus: prüfe ob Bot/Web jemals ohne Service-Key schreibt — dort würde `INSERT denied by RLS` schlagen. |
| **LOW** | `migrations/005:5-23` (Schema-Parity-Notes) | Kommentar listet Parity zu Board-DB Migrations (011, 030, 036, 037). Engine-Migration mirror't Board, wird aber separat versioniert. | Drift zwischen den beiden Schemas wird nur durch Code-Review entdeckt — kein automatisierter Check. | CI-Step der `migrations/005_sidekick_threads.sql` mit der Board-Repo-Migration vergleicht (hash der CREATE TABLE-Sektionen). Bei Mismatch: Warnung im PR. |
| **LOW** | `threads-store.ts:1-548` | Test-Seam (`fetchFn`-Override) ist überall konsistent. Gut gebaut. UUID-Validation per Regex (matchend mit sidekick-reasoning-tools), kein RFC4122-strict — bewusst (Test-Fixtures). | Konsistent, kein Bug. | — |

**Pre-Conclusion Audit (Data):**
- Files reviewed: migrations/001-005 (full), threads-store.ts head + grep, sidekick-create.ts auth-headers, supabase-rest.ts head
- Items checked: migration-order (✓ linear, idempotent), RLS-policies (✓ found gap on writes), indexes (✓ partial gap), schema-drift between repos (✓ flagged manual-only check)
- Not verified: tatsächliche Supabase-Project-Daten, kein `EXPLAIN ANALYZE` möglich (read-only audit), Board-Repo-Migrations nicht gegengelesen.

### 3.3 DevOps (`setup.sh`, hooks, CI)

**Files gelesen:** `setup.sh` (1640 LOC, key sections gegrept), `.githooks/pre-commit`, `.github/workflows/build-pipeline.yml`, `.claude/hooks/*.sh` (ls), `.claude/scripts/` (ls, 30+ Files).

| Severity | Datei:Zeile | Befund | Begründung | Vorschlag |
|---|---|---|---|---|
| **HIGH** | `.github/workflows/build-pipeline.yml:33-37` | CI-Workflow läuft typecheck + tests, **kein** `setup.sh --check`-Step. **Kein** Drift-Detection zwischen `agents/`/`skills/`/`commands/` Source und ihren `.claude/`-Installs. | Genau die Klasse Bug, die heute T-1014 + Reporter-Install ausgelöst hat, würde CI nicht fangen. Wenn morgen jemand `agents/backend.md` editiert ohne setup.sh laufen zu lassen, ist die Install-Kopie outdated und niemand bemerkt es bis ein Customer-Repo bricht. | Neuer CI-Job `self-install-up-to-date`: läuft `bash setup.sh --update --auto` in einem Sandbox-Checkout, dann `git diff --exit-code`. Failed CI = "run setup.sh --update locally and commit". |
| **HIGH** | `.githooks/pre-commit:32-50` | Hook blockt `.pipeline/`, `.claude/.pipeline-version`, `.claude/.template-hash`. **Nicht** `.claude/agents/`, `.claude/commands/`, `.claude/skills/`. | `self-install-topology.md` dokumentiert das als "deferred" und sagt explizit "wenn du `.claude/agents/` editierst und es soll überleben — editiere stattdessen die Source". Das ist disziplinabhängig — keine Leitplanke. T-1014 ging genau über diese Lücke. | Hook erweitern um die drei `agents/commands/skills`-Pfade, mit dem `GIT_ALLOW_INSTALLED_EDIT=1`-Override für emergency. Gleiche Mechanik, nur Prefix-Liste erweitern. |
| **HIGH** | `setup.sh:413-489` (Plugin-Install) und `:488` | `setup.sh` schluckt `claude plugin install` Failures: `\|\| echo "  ⚠ Failed"`. Counter (`plugin_count`) wird trotzdem inkrementiert auf `total`. | Success-Message lügt. Wenn der Marketplace kurz down ist, sieht der Setup grün aus, aber Plugin-Skills fehlen. Genau das war der 2026-04-12-Incident. | `set -o pipefail` für die Plugin-Schleife; bei Failures Exit non-zero und klare Message "x of y plugins failed — re-run with internet". Counter nur bei real-success inkrementieren. |
| **MEDIUM** | `setup.sh:1-1640` | 1640 Bash-LOC ohne Test-Harness (für sich selbst — andere Scripts haben Tests, siehe `.claude/scripts/*.test.sh`). Pfad-Migrations, CLAUDE.md-Templating, Plugin-Install, Hook-Setup, Versionsstamps — alles in einer Datei, kein Unit-Test. | Init-Flow-Incident (2026-04-11), Plugin-Skill-Incident (2026-04-12) und der jetzt resolved Reporter-Install-Bug stammen alle aus setup.sh-Edge-Cases. Keine Regression-Sicherheit. | Mindestens ein Smoke-Test pro Mode (`--update`, `--check`, `--register-plugin`) der `setup.sh` in einer fresh tmp-dir laufen lässt und Output-Files validiert. |
| **MEDIUM** | `setup.sh:923-928` (Skill-Copy-Loop) | `for d in "$FRAMEWORK_DIR/skills/"*/; do … cp "$d/SKILL.md" "$PROJECT_DIR/.claude/skills/$dname.md"`. Kein Error-Handling wenn `SKILL.md` in einem subdir fehlt. | Wenn jemand `skills/orphan/` ohne SKILL.md anlegt, schlägt `cp` lautlos fehl — alle Skills danach kopieren weiter, kein Log. | Vor `cp`: `[ -f "$d/SKILL.md" ] || { echo "Warn: $d ohne SKILL.md"; continue; }`. |
| **MEDIUM** | `.claude/hooks/` (6 Files) | Alle 6 Hooks sind shell scripts (`detect-ticket-post.sh`, `on-agent-start.sh`, `on-agent-stop.sh`, `on-session-end.sh`, `quality-gate.sh`, `detect-ticket.sh`). **Kein** `pre-tool-use`-Hook für Branch-Check oder Sidekick-Routing — diese laufen nur als Markdown-Rules im LLM-Kontext, nicht als deterministische Hooks. | Genau die Lehre aus 2026-04-21 Incident: Markdown-Rules sind LLM-Disziplin, kein hard guardrail. Eine `branch-check-before-edit.md` ohne Hook ist Best-Effort. | `.claude/hooks/pre-tool-use-branch-check.sh` (mindestens für Edit/Write) der den Branch checkt und denied wenn `main` + Pipeline configured + kein expliziter Override. Gleiche Mechanik wie der Bash-Allowlist im `audit-runtime.ts:canUseTool`. |
| **LOW** | `.claude/scripts/board-api.sh` und Geschwister | Im CLAUDE.md klar dokumentiert ("never call board API with raw curl + X-Pipeline-Key"). Wrapper existiert. Gut. | Disziplin-Hilfe vorhanden. | — |
| **LOW** | `setup.sh:543-623` Self-install-detection | Logic prüft beide `pipeline/package.json` und `.pipeline/package.json` — dann arm't den Hook. Sauber. | — | — |

**Pre-Conclusion Audit (DevOps):**
- Files reviewed: setup.sh (gegrept, Hauptpfade), .githooks/pre-commit (full), .github/workflows/build-pipeline.yml (full), .claude/hooks/*.sh (ls), .claude/scripts/ (ls)
- Items checked: CI-Drift-Gate (✗ missing), pre-commit-Scope (✓ partial), plugin-install error-handling (✓ swallowed), hook-coverage für Branch-Check (✗ missing), .gitignore-Lücken (nicht systematisch geprüft)
- Not verified: tatsächlicher Setup-Run in fresh tmp dir, npmjs/marketplace-Auth-Failure-Pfade live.

### 3.4 QA (`pipeline/lib/*.test.ts`)

**Files gelesen:** Test-Liste (`wc -l pipeline/lib/*.test.ts`), gezielte Reads von test-coverage-Pattern via grep.

| Severity | Datei:Zeile | Befund | Begründung | Vorschlag |
|---|---|---|---|---|
| **CRITICAL** | `pipeline/lib/{worktree-manager,qa-runner,event-hooks,watchdog,drain,config,load-agents}.ts` | **0 Tests** für 6 von 7 most-failure-prone runtime files. Verifiziert: `wc -l` zeigt diese Files mit 419/677/188/87/126/290/102 LOC. Kein `<name>.test.ts` für any of them. (Erwähnt in Lauf-1 §3.E, wird hier nochmal verifiziert.) | Pipeline-Reliability-Incident (2026-04-07) und User-Beschwerde "Agent-Chips zeigen falsche States" mappen direkt auf event-hooks/watchdog. Kein Test = jeder Refactor ist ein Lottoschein. | Coverage-Floor in CI: `pipeline/lib/{worktree-manager,qa-runner,event-hooks,watchdog,drain,config}.ts` muss ≥60% Line-Coverage erreichen, sonst block-merge. Parallel: T-Tickets schreiben für die fehlenden Tests, mit Akzeptanzkriterium "decken 1+ historischen Bug". |
| **HIGH** | `sidekick-chat.test.ts:1-614` | Test-Seam (`_internal.callChatModel`) ist eine fake AsyncGenerator. Tests pumpen canned Events durch und assertieren Sink-Behavior. **Keine assertion** dass der real SDK-Call mit `allowedTools: []` ein Bug ist. | Tests sind grün, Production ist kaputt. Test-Strategy hat den `allowedTools`-Wert gar nicht im Test-Surface. | Mindestens ein Smoke-Integration-Test (mit echtem SDK gegen einen Mock-Endpoint) der prüft, dass die SDK-Call-Args dem Tool-Registry entsprechen. Plus: Type-Lock zwischen `SIDEKICK_REASONING_TOOLS` keys und `allowedTools` array. |
| **HIGH** | `sidekick-system-prompt.test.ts:1-254` | Snapshot-Tests auf den System-Prompt. Stabil gut für "kein versehentlicher Edit". Erkennt nicht "Prompt sagt 'use create_ticket' aber Tool create_ticket ist gar nicht advertised". | Snapshot-Test ist eine Konsistenz-Prüfung gegen die letzte Version, keine Verhaltens-Prüfung. | Funktionaler Test: lade Prompt + Tool-Schema-Liste, prüfe dass jede Tool-Mention im Prompt einen passenden Eintrag in `SIDEKICK_REASONING_TOOLS` hat (und vice versa). |
| **HIGH** | `sidekick-policy.test.ts:1-541` und `sidekick-tools.test.ts:1-470` | Insgesamt 1011 Test-LOC für Files die laut Lauf 1 deprecated sein sollten (`sidekick-policy.ts`, `sidekick-tools.ts`). | Maintenance-Last auf totem Code. Bei jedem Refactor müssen Tests upgedated werden, die nichts beweisen das in Production läuft. | Nach Wiring (CRITICAL-1) plus Shadow-Mode delete diese drei Files inklusive Tests. Net code-reduction: 1869 LOC + 1562 Test-LOC = ~3400 LOC weg. |
| **MEDIUM** | `audit-runtime.test.ts:1-735` | Sehr gründlich (`classifyBashCommand` exhaustiv durchgetestet). Aber: keine Integration-Test der das Skill-Loading durch die Audit-Pipeline bis zum SDK-Call testet (vermutlich weil das den echten SDK braucht). | Read-only Sicherheits-Surface ist gut isoliert. Skill-Path-Failures (z.B. Lauf 1 §4 Backend §5 — `frameworkSkillsDir` dead) bleiben unerkannt. | Mock-SDK-Test: gibt dem audit-runtime einen geschriebenen Skill-File, validiert dass der Inhalt im Prompt landet. Skill not found → no-skill-prompt-Variante validieren. |
| **LOW** | `pipeline/lib/*.test.ts` Naming | Test-File-Existenz allein sagt nichts über Coverage. `sidekick-chat.test.ts` hat 614 LOC aber covered Production-Pfad nicht. Lokales `wc -l` erzeugt false sense of coverage. | Misleading metric. | Vitest mit `--coverage` als CI-Step + Threshold. Reports in Artifacts. |

**Pre-Conclusion Audit (QA):**
- Files reviewed: pipeline/lib/*.test.ts (Liste + LOC), sidekick-chat.ts test-seam (im Backend-Pass gelesen), audit-runtime.test.ts (Größe + Header)
- Items checked: tests die Mocks zu tief setzen (✓ sidekick-chat), always-pass-Tests (✓ snapshot ohne Verhalten), kritische untested Files (✓ 6 listed)
- Not verified: tatsächliche Coverage-Zahlen (kein vitest run), Snapshot-Test-Inhalte gelesen aber nicht ausgewertet.

### 3.5 Security

**Files gelesen:** `audit-runtime.ts` (full, im Backend-Pass), `sidekick-create.ts` Auth-Headers, `github-app.ts` (Header), `sidekick-attach.ts` env-Pattern, `expert-audit-scope.md`-Rule, `setup.sh` Plugin-Install.

| Severity | Datei:Zeile | Befund | Begründung | Vorschlag |
|---|---|---|---|---|
| **HIGH** | `pipeline/lib/sidekick-create.ts:453,509,576` und `pipeline/lib/sidekick-attach.ts:437` | `X-Pipeline-Key: cfg.apiKey` auf 4 Stellen direkt in fetch-Headers. Kein zentraler Wrapper, der versehentliches Logging des Keys verhindert. Wenn ein Logger den fetch-Request loggt (Sentry-Breadcrumb auf network call), landet der Key im Log. | CLAUDE.md sagt "never call the board API with raw curl + X-Pipeline-Key — it leaks the key". Im Code passiert genau das: roher Header. Für TS-Code bisher nicht problematisch (kein curl), aber Logging-Discipline ist im Code nicht enforced. | Zentraler `boardFetch(url, opts, cfg)`-Wrapper, der den Header injectet UND beim Logging redacted. Plus: ESLint-Rule die direkten `X-Pipeline-Key`-String in fetch-Headers verbietet außer im Wrapper. |
| **HIGH** | `pipeline/lib/audit-runtime.ts:228-491` (`classifyBashCommand`) | Bash-Allowlist ist sehr gründlich (Lauf 1 hat das auch positiv erwähnt). Aber: `awk` und `sed` sind komplex. Trotz der heuristischen Pattern-Checks ist eine Smuggling-Lücke nicht ausgeschlossen — und sie sind die einzigen Tools mit echter Code-Execution-Capability auf der Allowlist. | Defense-in-depth-Frage: warum `awk`/`sed` überhaupt in der Allowlist? Real-world-Auditor-Use-Cases sind selten (`Read`/`Grep`/`Glob` deckt 95%). | Move `awk` und `sed` in eine separate "advanced"-Kategorie und entweder rauswerfen aus AUDIT_ALLOWED oder mit zusätzlicher User-Confirm-Prompt versehen. Der Audit verliert ~5% Convenience, gewinnt 100% Confidence. |
| **MEDIUM** | `pipeline/lib/github-app.ts:123-183` | Token-Caching im in-memory `Map<number, InstallationToken>`. Refresh-Margin 5min vor Expiry. Sauber implementiert. **Aber**: kein Test für Failure-Modes (Network-Error beim Token-Refresh → bleibt der alte expired Token im Cache?). | Bei kurzem Outage könnte ein expired Token im Cache hängen bleiben und alle nachfolgenden API-Calls scheitern bis Server-Restart. | Test: simuliere `installToken()` `fetch`-Failure, validiere dass nächster Call den Token re-fetcht statt cached-expired zu returnen. |
| **MEDIUM** | `pipeline/lib/sidekick-attach.ts:311-312` | `process.env.SUPABASE_URL` und `process.env.SUPABASE_SERVICE_KEY` direkt aus env gelesen — **kein** Default-Fallback und keine Validation an einem zentralen Bootstrap-Punkt. | Wenn `SUPABASE_SERVICE_KEY` leer ist, wird das in jeder Funktion separat behandelt. Inkonsistente Error-Messages an User. | Zentraler `getEngineConfig()` mit Zod-Schema-Validation am Server-Start. Hard-Fail bei missing required env vars statt 500 später. |
| **MEDIUM** | Plugin-Install (`setup.sh:413-489`) | `plugin-security-gate.sh` läuft beim Install (laut Rule), aber **runtime** gibt es kein Re-Scan. Einmal installiertes Plugin-Skill kann beliebigen Markdown-Inhalt haben — wird in Agent-Kontext eingebracht ohne weitere Prüfung. | Gate ist install-time, nicht runtime. Wenn ein Plugin-Skill nach Install via filesystem geändert wird (lokaler Edit), keine Re-Validation. | Mindestens ein optional `--strict-runtime`-Mode der bei jeder Skill-Load das gleiche Pattern-Scanning macht. Performance-Impact nur bei aktiviertem Mode. |
| **LOW** | `pipeline/lib/audit-runtime.ts:269-274` | Heredoc/redirect-Reject ist gut. Aber `<<` matched auch in awk/sed-Scripts wenn dort als String enthalten — falsch positive möglich. Besser False-Positive als False-Negative, kein Bug. | Conservative-by-design. | — |
| **LOW** | `.gitignore` (nicht gelesen) | Sollte `.env*`, `.claude/.token-snapshot-*.json`, `*.local` enthalten. Stichprobe via `git status` zeigt: `.claude/.token-snapshot-T-723.json` etc. werden als untracked angezeigt — also nicht gitignored. Token-Snapshots im Repo? | Wenn diese Token-Snapshots Secrets enthalten, ist das ein Leak-Risk. Müssten geprüft werden. | `cat .claude/.token-snapshot-*.json` — wenn nichts Sensibles, dann gitignore. Wenn doch, sofort `git filter-repo`. |

**Pre-Conclusion Audit (Security):**
- Files reviewed: audit-runtime.ts (full, Backend-Pass), sidekick-create.ts grep, github-app.ts head, sidekick-attach.ts grep, setup.sh plugin-section
- Items checked: token-leakage (✓ X-Pipeline-Key in fetch ohne Wrapper), bash-injection (✓ awk/sed audit-runtime), input-validation an Endpoints (in pipeline/server.ts nicht systematisch geprüft, gestreift)
- Not verified: server.ts Endpoint-by-Endpoint Auth-Check, Sentry-Logger-Redaction-Behavior konkret, .env-Pattern in git-Log (nicht gelaufen).

### 3.6 Code Review (Architektur, Dead Code, Konventionen)

**Files gelesen:** Outputs der vorherigen Pässe, plus agents/orchestrator.md, agents/backend.md, alle Skill-Größen (`wc -l skills/*/SKILL.md`), commands-Größen, rules-Größen.

| Severity | Datei:Zeile | Befund | Begründung | Vorschlag |
|---|---|---|---|---|
| **HIGH** | `agents/backend.md:7-9` und `data-engineer.md`, `frontend.md`, `qa.md` (vier von zehn Agents) | `skills:` Frontmatter (Claude-Code-SDK-native Skill-Attachment) UND Body-Markdown `Read('skills/<role>/SKILL.md')` (T-1014 Pattern) **koexistieren in derselben Datei**. | Zwei konkurrierende Skill-Loading-Mechanismen. Wenn die SDK-Frontmatter funktioniert, ist der Markdown-Read redundant. Wenn nicht, ist der Markdown-Read der einzige Pfad. Niemand weiß welcher gewinnt. Maintenance-Risk: Future-Devs ändern den einen, vergessen den anderen, divergieren still. | Entscheiden welcher Mechanismus Source-of-Truth ist. Wenn SDK-Frontmatter (sauberer): alle Body-Markdown-Reads löschen, plus `agents/orchestrator.md:50-66` Spawn-Template (das den Read als ERSTER TOOL-CALL fordert) entfernen. Wenn Markdown-Read (T-1014 Pattern): Frontmatter `skills:` löschen. **Konsistenz herstellen**. |
| **HIGH** | `commands/develop.md:857`, `commands/just-ship-vps.md:608`, `commands/ship.md:505`, `commands/setup-just-ship.md:477` und `skills/develop/SKILL.md:806`, `skills/just-ship-vps/SKILL.md:608`, `skills/ticket-writer/SKILL.md:491` | Skills/Commands die das im Operating-Model definierte Limit `≤ 500 lines` deutlich überschreiten. Develop besonders kritisch (806 LOC). | Operating-Model § "Architecture of loaded context" sagt explizit ≤500. Längere Skills konkurrieren mit System-Prompts und anderen Skills um Attention. Bei `develop`, das bei JEDEM `/develop`-Run geladen wird, hat das User-spürbare Drift-Effekte. | Inhaltlicher Refactor von `develop` und `just-ship-vps`: Procedural-Detail in Sub-Skills oder Sub-Pages auslagern. Plus: CI-Step der `wc -l skills/*/SKILL.md` ausführt und bei >500 LOC failed. |
| **MEDIUM** | `skills/ticket/` und `skills/ticket-writer/` | Beide existieren (44 vs 491 LOC). `ticket-writer` ist groß und installed; `ticket` sieht aus wie ein Redirect/Stub. Nur `ticket-writer.md` ist installed in `.claude/skills/ticket-writer.md`, plus separat `ticket.md` (44 LOC). | Verwirrendes Naming. Ein Skill ist vermutlich dead. | Kläre Intent: löschen oder mergen. Falls beide notwendig (z.B. Sidekick-intake vs. ticket-writer), in einem Comment in beiden Files erwähnen. |
| **MEDIUM** | `agents/security.md` und `agents/devops.md` | Kein lokales Skill (`Read('CLAUDE.md')` als ersten Read laut orchestrator.md:64-65 — nicht in den Agent-Bodies selbst). | Diese zwei Agents arbeiten ohne Anti-Pattern-Catalog. Genau die Domains wo strukturelle Konsistenz am wichtigsten ist (Security vor allem) haben am wenigsten codified Wissen. | Entweder `skills/security/SKILL.md` und `skills/devops/SKILL.md` schreiben (und in agents-frontmatter binden), oder erkennen dass diese Domains durch Plugins (sentry-skills, security-review) abgedeckt sind und das im Agent-Body explizit referenzieren. |
| **MEDIUM** | `pipeline/server.ts` (2208 LOC, 14+ Sidekick-Endpoints) | `/api/sidekick/{conversations, threads, threads/:id, threads/:id/messages, create, create-project, attach, converse, chat}`. Operating-Model sagt: Path 2 = "Board calls an Engine endpoint" (singular). Realität: ein Fan-Out mit Sub-Hierarchie. | Vision drift. Code ist gewachsen, Dokumente sind nicht. PRODUCT.md erwähnt nur `/api/launch`, `/api/events`, `/api/answer`, `/api/ship`. | Operating-Model § "Two execution paths" updaten mit der echten Endpoint-Liste. Plus: gruppieren in einer Sub-Datei `pipeline/server-sidekick.ts` die handler exportiert, server.ts shrinken. |
| **LOW** | `agents/triage.md:tools` Frontmatter | `tools:` als leere Liste — Triage-Agent bekommt keine Tools. Plus `model: haiku`. | Vermutlich Absicht (reine Klassifikation), aber nicht im Body dokumentiert. | Comment in der Frontmatter warum `tools:` empty ist. |
| **LOW** | `commands/develop.md:348,450,452` und `agents/{backend,data-engineer,frontend,orchestrator,qa}.md` | 14 source-path-Reads `skills/.../SKILL.md` total (Lauf 1 hat das auch). Mit T-1014 explizit als Pattern eingeführt. | Wird in Customer-Repos brechen wenn Source-Pfad nicht existiert. Im Engine-Repo aktuell ok weil Source vorhanden. | Hauptmaßnahme = Skill-Injection via SDK (Lauf 1 Maßnahme 1). Bis dahin: Fallback im Markdown-Pattern explizit dokumentieren ("falls skills/ nicht existiert, .claude/skills/<name>.md probieren"). |

**Pre-Conclusion Audit (Code Review):**
- Files reviewed: agents/orchestrator.md (full), agents/backend.md (full), alle Frontmatter-Heads, wc-Listen für skills/agents/commands/rules
- Items checked: dead code (✓ ticket+ticket-writer), Konventionsbrüche (✓ skills+Read koexistieren), Skill-Length-Violations (✓ 4 Files), doppelter Code (Lauf 1 hat sidekick-policy/converse/tools schon flagged), Skill-without-Source-Pendant (✓ keine — alle Source-Skills auch installed)
- Not verified: vollständiges Lesen aller 10 Agent-Bodies, vollständige Inspektion aller 23 Skills inkl. plugin-Skills.

---

## 4. Phase 4 — Konsolidierung der Domain-Findings

Findings die **mehrfach** auftauchen (robustestes Signal):

| Finding | Backend | Data | DevOps | QA | Security | CodeRev | Lauf 1 |
|---|---|---|---|---|---|---|---|
| Sidekick `allowedTools: []` (Wiring fehlt) | CRIT | — | — | HIGH | — | — | CRIT (#1) |
| Source-vs-Install-Pfad in Markdown | — | — | HIGH (Hook-Lücke) | — | — | LOW | CRIT (#2) |
| Two-truth: sidekick-policy/converse/tools | HIGH | — | — | HIGH | — | — | HIGH |
| Untested runtime spine (worktree, qa-runner, …) | — | — | — | CRIT | — | — | HIGH (§3.E) |
| Snapshot-Tests vs. Verhaltens-Tests | — | — | — | HIGH | — | — | HIGH |
| Skill-Length > 500 LOC | — | — | — | — | — | HIGH | MED |
| RLS-Write-Gap / Token-leakage-Risk | — | MED | — | — | HIGH | — | LOW |
| Skill-Loading: 2 Mechanismen koexistieren (Frontmatter `skills:` + Body `Read`) | — | — | — | — | — | HIGH | (NEU) |

Drei Findings tauchen in 2+ Pässen auf — das sind die Maßnahmen mit höchstem Hebel.

---

## 4.5 NEUES CLUSTER — "Scope-Markierung als systemisches Problem"

### Verifikation der Hypothese

**Hypothese (vom Auftraggeber):** Artefakte (Rules, Skills, Agent-Definitionen) tragen ihren Anwendungs-Scope nicht klar an sich selbst. Empfänger applizieren sie auf den falschen Kontext. Es gibt keinen Hard-Fail wenn Kontext nicht passt.

**Evidenz aus dieser Codebase:**

#### a) `.claude/rules/*.md` Scope-Klassifikation

Verifiziert via: `wc -l .claude/rules/*.md` plus Inhaltsanalyse.

| Rule | Zeilen | Anwendungs-Scope (faktisch) | Frontmatter-Scope-Marker? |
|---|---|---|---|
| `sidekick-terminal-routing.md` | 171 | Terminal-Sidekick (Claude Code) | nein |
| `branch-check-before-edit.md` | 121 | Universal (vor jedem Edit/Write) | nein |
| `ship-trigger-context.md` | 114 | Universal (Trigger-Erkennung) | nein |
| `expert-audit-scope.md` | 106 | **Code-Runtime-Scope: gilt nur für Aufrufe via `pipeline/lib/audit-runtime.ts` (`runExpertAudit`)** | nein — Scope erwähnt aber nicht maschinenlesbar |
| `self-install-topology.md` | 89 | Source-Repo (just-ship engine), nicht Customer-Installs | nein |
| `decision-authority-enforcement.md` | 82 | Universal (alle Agents/Sidekick) | nein |
| `shopify-skill-awareness.md` | 39 | Projekte mit Shopify-Files | nein |
| `audit-completeness.md` | 29 | **Audit-Agents (gespawnt von `/just-ship-audit`)** | nein |
| `no-settings-data-edit.md` | 20 | Shopify-Theme-Projekte | nein |
| `framework-abstraction-check.md` | 20 | Universal vor Code-Edit | nein |
| `detect-stuck-tickets.md` | 18 | Session-Start (read-only) | nein |
| `brainstorming-design-awareness.md` | 18 | Brainstorming + Visual Companion | nein |
| `post-develop-feedback.md` | 15 | Nach `/develop`-Run | nein |
| `framework-version-check.md` | 12 | Session-Start | nein |
| `ticket-number-format.md` | 8 | Universal | nein |
| `no-premature-merge.md` | 7 | Universal | nein |
| `no-duplicate-finishing-skill.md` | 7 | Skill-System (superpowers) | nein |

**Zwischenergebnis:** 17 von 17 Rules haben **kein** maschinenlesbares Scope-Marker. Nur einige erwähnen ihren Scope im Body-Text — von diesen ist `expert-audit-scope.md` der gefährlichste Fall, weil der Scope als "audit agents" beschrieben ist (klingt wie eine Verhaltens-Klasse), faktisch aber ein konkretes Stück TS-Code (`audit-runtime.ts`) ist. Genau diese Mehrdeutigkeit hat den CTO-Lauf-1-Fehler ausgelöst (auch dieser Lauf hat es zunächst wieder so verstanden — siehe Header-Notiz).

#### b) Skills mit Source-Topology-Hardcodes

Verifiziert via `grep -rnE "Read\(['\"]?skills/" agents/ commands/ skills/`:

| Datei:Zeile | Hardcode | Scope-Realität |
|---|---|---|
| `agents/orchestrator.md:52` | `Read('skills/{role}/SKILL.md')` (Template) | Nur Source-Repo-valid, fragmentiert in Customer-Installs |
| `agents/qa.md:25` | `Read('skills/webapp-testing/SKILL.md')` | Nur Source-Repo |
| `agents/frontend.md:26,28` | `Read('skills/frontend-design/SKILL.md')`, `creative-design`, `design-lead` | Nur Source-Repo |
| `agents/backend.md:24` | `Read('skills/backend/SKILL.md')` | Nur Source-Repo |
| `agents/data-engineer.md:24` | `Read('skills/data-engineer/SKILL.md')` | Nur Source-Repo |
| `commands/develop.md:348` | `Read('skills/{role}/SKILL.md')` (Template) | Nur Source-Repo |
| `commands/develop.md:450,452` | `Read('skills/webapp-testing/SKILL.md')`, `test-driven-development` | Nur Source-Repo |
| `commands/implement.md:75` | `skills/{skill-name}/SKILL.md` (primärer Pfad) oder `.claude/skills/{skill-name}.md` (Fallback) | **Hat Fallback dokumentiert** — der einzige Ort wo das richtig gemacht ist |

**Zwischenergebnis:** 8 Source-Pfad-Hardcodes in 7 Files, nur `commands/implement.md:75` hat den korrekten Fallback. T-1014 (heute) hat das Pattern eingeführt; die übrigen waren vermutlich vorher über andere Mechanismen.

#### c) Agents mit gemischten Skill-Loading-Mechanismen

Verifiziert via `grep -l "^skills:" agents/*.md`:

| Agent | `skills:` Frontmatter (SDK-Mechanismus) | Body-Read-Hardcode (T-1014-Pattern) | Two-Truth? |
|---|---|---|---|
| backend | ✓ (`skills: - backend`) | ✓ (Zeile 24) | **JA** |
| data-engineer | ✓ | ✓ (Zeile 24) | **JA** |
| frontend | ✓ | ✓ (Zeile 26,28) | **JA** |
| qa | ✓ | ✓ (Zeile 25) | **JA** |
| orchestrator | nein | nein (gibt nur Template raus) | nein |
| code-review | nein | nein | nein |
| devops | nein | nein | nein |
| security | nein | nein | nein |
| triage / triage-enrichment | nein | nein | nein |

**Zwischenergebnis:** 4 von 10 Agents haben zwei konkurrierende Skill-Loading-Mechanismen — die SDK-native Frontmatter UND den expliziten Markdown-Read. Niemand hat dokumentiert, welcher gewinnt.

### Strukturelle Lösung — `applies_to:` Frontmatter + Loader-Enforcement

#### a) Frontmatter-Konvention

Jedes Artefakt unter `.claude/rules/`, `agents/`, `commands/`, `skills/<n>/SKILL.md` bekommt eine `applies_to:`-Zeile. Werte (kontrolliertes Vokabular):

| Wert | Bedeutung | Loader-Verhalten |
|---|---|---|
| `all-agents` | Universal — gilt überall | immer geladen |
| `orchestrator-only` | Nur im Orchestrator-Kontext | geladen wenn agent-name = orchestrator |
| `subagent-only` | Nur in gespawnten Subagents | geladen wenn agent-name ≠ orchestrator |
| `audit-runtime-only` | Nur via `audit-runtime.ts` (das `runExpertAudit`) | geladen nur wenn Aufruf aus `runExpertAudit`-Path |
| `sidekick-terminal-only` | Nur Terminal-Sidekick (Claude Code) | geladen wenn no SDK-Audit-Context |
| `sidekick-browser-only` | Nur Browser-Widget über `/api/sidekick/chat` | geladen serverside im Chat-Endpoint |
| `source-repo-only` | Nur im Engine-Source-Repo gültig | Hard-Fail wenn loaded in Install-Repo (heuristik: kein `pipeline/package.json` aber `.pipeline/package.json`) |
| `install-repo-only` | Nur in Customer-Install gültig | Hard-Fail wenn loaded in Source-Repo |
| `shopify-projects-only` | Nur wenn `sections/`/`templates/`/`layout/theme.liquid` vorhanden | Loader checked filesystem |
| `session-start-only` | Nur once-per-session | Loader marked nach erster Verwendung |

Mehrere Werte als Liste erlaubt: `applies_to: [orchestrator-only, source-repo-only]`.

#### b) Loader-Enforcement

`pipeline/lib/load-skills.ts`, `pipeline/lib/load-agents.ts` und `pipeline/lib/load-rules.ts` (NEU) bekommen eine `loadContext`-Param: `{ runtime: "orchestrator" | "subagent" | "audit-runtime" | "sidekick-chat", repo: "source" | "install", projectKind: "shopify" | "...", sessionStart: boolean }`. Beim Laden:

1. Parse `applies_to:` aus Frontmatter.
2. Filter: `if applies_to && !applies_to.some(scope => contextSatisfies(scope, loadContext))` → **Hard-Fail** mit klarer Message: `"Skill X cannot be loaded in context Y because applies_to=[...]"`.
3. Hard-Fail statt silent-skip — sonst reproduzieren wir den Bug, dass fehlende Skills generisches Verhalten erzeugen.

#### c) Pre-Commit-Validation

Neuer `.githooks/pre-commit`-Step (oder eigener Hook): bei jedem Commit auf `.claude/rules/*.md`, `agents/*.md`, `commands/*.md`, `skills/<n>/SKILL.md`:
- Frontmatter parsen.
- Wenn `applies_to:` fehlt → **block** mit `"Add applies_to: <scope> to <file>"`.
- Wenn `applies_to:`-Werte nicht im erlaubten Vokabular → block.

#### d) Migration

Step 1: Frontmatter mit `applies_to:` zu allen 17 Rules + 23 Skills + 10 Agents + 13 Commands hinzufügen (~63 Files). Default für unsicher: `all-agents` mit FIXME-Comment.

Step 2: Loader-Code schreiben + Test (`pipeline/lib/load-rules.test.ts`).

Step 3: Pre-Commit-Hook aktivieren.

Step 4: Über 1 Woche `applies_to:`-Defaults von `all-agents` auf den korrekten Wert verfeinern; jedes Refinement = ein Mini-PR.

#### e) Erfolgskriterium

- Wenn jemand eine Rule mit `applies_to: audit-runtime-only` aus einem normalen general-purpose-Agent referenziert, kommt ein deutlicher Loader-Error statt stillem Apply.
- Wenn jemand `agents/backend.md` ohne `applies_to:` committed, blockt der Pre-Commit.
- Lauf-1-Fehler (Auditor wendet `expert-audit-scope.md` auf sich selbst an) wäre nicht möglich gewesen, weil der Loader die Rule nur in `audit-runtime`-Kontext geladen hätte.

---

## 5. Phase 5 — Vision-Drift (Vertiefung Lauf 1)

Lauf 1 §5 hat die drei Drift-Achsen gut benannt (Code-ahead, Code-lags, Code-orthogonal). Vertiefungen:

### 5.1 Code-ahead-of-vision: bestätigt + ergänzt
- `audit-runtime.ts` bleibt der härteste Teil (Lauf 1 korrekt). Plus: das ist das einzige Stück Code mit echtem `canUseTool`-Enforcement; alle anderen "Sicherheits-Garantien" sind Markdown.
- **NEU:** `pipeline/server.ts` hat 14+ Sidekick-Endpoints mit Sub-Hierarchie (`/threads/:id/messages`, `/conversations`, …). Operating-Model § "Path 2" sagt "Board calls an Engine endpoint" (singular). PRODUCT.md listet 4 Endpoints. Realität: 4× mehr.

### 5.2 Code-lags-vision: bestätigt + Persistence-Split ergänzt
- Sidekick-Reasoning-Tools nicht wired (Lauf 1 §1, hier CRIT).
- Reporter, design-lead, sidekick-converse jetzt installed (Lauf 1 §3.C **resolved**), aber Verkabelung in `/develop` und `/ship` noch nicht via Integration-Test bewiesen — das war heute committed (T-997, T-999) ohne e2e-Test.
- **NEU:** Persistence-Split (Backend §HIGH-#5): in-memory `threads`-Map in `sidekick-chat.ts` + DB-backed `threads-store.ts` koexistieren, niemand hat dokumentiert was source-of-truth ist.

### 5.3 Code-orthogonal-zu-vision: bestätigt + GitHub-App ergänzt
- Plugin-System weiterhin nirgends in PRODUCT.md/Operating-Model erwähnt (Lauf 1).
- `github-app.ts` (T-1015) heute committed, immer noch nicht in PRODUCT.md.
- Coolify als second-class neben Vercel/Shopify — Lauf 1.
- **NEU:** Find-Skills (T-1016, heute) ist ein Skill-Discovery-Mechanismus, der vermutlich konkurriert mit dem Skill-Tool aus dem Operating-Model. Nicht in PRODUCT.md, nicht in Operating-Model.

### 5.4 Operating-Model-§Architecture-of-loaded-context — Realitätscheck

| Tier laut Operating-Model | Soll-Größe | Ist-Größe | Status |
|---|---|---|---|
| Constitution (CLAUDE.md) | ≤ 200 lines | 93 LOC | ✓ |
| Rules (.claude/rules/*.md) | "small" | 7-171 LOC, Total 876 LOC | mostly ✓ |
| Skills (skills/<n>/SKILL.md) | ≤ 500 lines body | **4 Files >500: develop 806, just-ship-vps 608, ticket-writer 491 (grenzwertig), setup-just-ship 477 (grenzwertig)** | ✗ |
| Agents (agents/*.md) | "role-specific" | 54-228 LOC | ✓ |
| Hooks (.claude/hooks/) | "deterministic must-fire" | 6 hooks vorhanden, aber **keine pre-tool-use für Branch-Check** | partial |

→ Konsequenz für Maßnahme: Skill-Length als CI-Gate (DevOps §HIGH).

---

## 6. Phase 6 — Root-Cause-Cluster-Tabelle (V2)

Sechs Cluster aus Lauf 1 + neues Cluster "Scope-Markierung":

| # | Cluster | Findings (V2-Quelle) | Symptom | Wurzel | Strukturelle Lösung | Symptom-Fix-Falle |
|---|---|---|---|---|---|---|
| 1 | **Source-vs-install topology drift** | 4.5 b), DevOps §HIGH-1+2, CodeRev §LOW-1 | Subagents in Customer-Installs arbeiten ohne Skill | Markdown-Read-Hardcode auf Pfad der nur in Source existiert; kein Hard-Fail bei Miss | Skill-Injection via `appendSystemPrompt` beim Spawn — Markdown-Reads löschen | Pfad-Patches (T-1014) machen es schlimmer — der Bug wandert nur um |
| 2 | **Built but not wired** | Backend §CRIT-1+2, §HIGH-1, QA §HIGH-1 | Reasoning-Sidekick gibt Chat-only-Antworten; Operating-Model-Versprechen brach | "Done" = "Tests in eigenem File grün". Niemand testet Konsumer-Erreichbarkeit | E2E-Smoke-Test als Merge-Gate für jeden Tool-Registry-Commit. Plus: Type-Lock `allowedTools` ↔ Registry. | Tools im nächsten Ticket "wiren" und genauso ohne e2e mergen → wiederholt sich |
| 3 | **Self-install rot** (heute behoben, strukturell offen) | DevOps §HIGH-1, Lauf 1 §3.C | Engine-Repo läuft gegen veraltete Installs (gestern wahr, heute resolved) | Kein CI-Step `setup.sh --check + git diff --exit-code` | CI-Job `self-install-up-to-date` als required-check auf main | Manuell den Hash bumpen — exakt das Antipattern der Topology-Rule |
| 4 | **Orchestrator/process bypass** | DevOps §MED-3, Lauf 1 §6 (Cluster 4), Incident 2026-04-21 | Code auf main ohne Ticket; Rolle-Anrede triggert direkt Implementation | Rules sind Markdown — der Model-Selektor entscheidet, nicht ein Hook | Branch-Check + Sidekick-Routing als deterministische `pre-tool-use`-Hooks unter `.claude/hooks/` | Mehr Markdown-Text in CLAUDE.md → bläht Constitution → andere Rules werden verdrängt |
| 5 | **Test-coverage on wrong files** | QA §CRIT-1, §HIGH-3+4 | Bug-of-the-week; "fix on fix"-Loops auf untested Code | Tests cluster auf neue Sidekick-Reasoning-Code (vom Spec gefordert), 0 Tests auf worktree-manager/qa-runner/event-hooks/watchdog | Coverage-Floor in CI auf 6 spezifischen Files; Tests als "Preis" für nächsten Feat der die Datei berührt | Tests an existing-tested Modulen hinzufügen — falsches Ziel |
| 6 | **Two-truth modules / dead code** | Backend §HIGH-3, §HIGH-4, CodeRev §HIGH-1, QA §HIGH-3 | Verwirrung im Maintenance: "Ich habe X geändert aber es hat nichts geholfen, weil die Live-Kopie eine andere ist" | Replacements (T-979, T-983) shippen *neben* Legacy statt sie zu ersetzen; Cleanup-Tickets werden "deferred" | Replace = Delete: Merge nur, wenn der ersetzte File im selben PR weg ist | Mehr Feats auf duplizierten Foundations — verstärkt das Problem |
| **7 NEU** | **Scope-Markierung fehlt** | Phase 4.5 a)+b)+c), Header-Notiz dieses Laufs | Drei Bugs in 48h derselben Klasse: T-1014 (Skill-Pfad nur in Source), Lauf-1 (Audit-Rule auf falschen Kontext appliziert), Reporter-Skill (gestern fehlend) | Markdown-Artefakte tragen ihren Anwendungs-Scope nicht maschinenlesbar; Loader hard-failen nicht bei Mismatch | `applies_to:`-Frontmatter + Loader-Hard-Fail + Pre-Commit-Validation (siehe §4.5 d) | Jeden Bug einzeln patchen (T-1014 hat das versucht für Skill-Pfade, hat aber neue Variante des Bugs eingeführt) |

---

## 7. Phase 7 — Sanierungs-Roadmap (V2)

5–7 Maßnahmen, sequenziell mit Risk-Assessment und Erfolgskriterien.

### Maßnahme 1 — Wire Sidekick reasoning tools end-to-end (CRITICAL, höchster User-Visibility-Hebel)

- **Kills:** Cluster 2 (built-but-not-wired), partial 6 (two-truth)
- **Effort:** M (3-5 Tage)
- **Risk:** **medium** — flipping `allowedTools: []` → `listSidekickReasoningToolNames()` ändert Sidekick-Verhalten auf jeder Browser-Widget-Message. Risiko: Regressionen auf Inputs die der bestehende Test-Korpus nicht abdeckt.
- **Risk-mitigation:** Shadow-Mode 48h: Log was das Modell gerne callen würde, aber nicht ausführen. Erst nach Beobachtung mit grünen Metriken aktivieren.
- **Was bricht möglicherweise:** Bestehende Browser-Widget-Konversationen die in der in-memory-Map des sidekick-chat hängen — Persistence-Migration nötig (siehe Maßnahme 5).
- **Erfolgskriterium:** Integration-Test sendet "create a ticket for X" an `/api/sidekick/chat`, asserted `tool_use` event für `create_ticket`, asserted Board-Row erschien. Zweiter Test für `create_epic`. Existierende 15-Beispiel-System-Prompt-Korpus läuft mit ≥90% Tool-Call-Rate (kein "I'd suggest you create a ticket"-Output ohne actual Tool-Call).

### Maßnahme 2 — Skill-Injection via SDK statt Markdown-Read in Subagent-Spawns

- **Kills:** Cluster 1 (Source-vs-install topology), partial 7 (Scope-Markierung)
- **Effort:** L (1-2 Wochen — touches 14 Markdown-Files + Orchestrator-Code + load-skills.ts + Tests)
- **Risk:** **medium** — wenn die Migration unvollständig ist, hat ein Subagent gar kein Skill (schlechter als falscher Pfad).
- **Risk-mitigation:** Feature-Flag `pipeline.skill_injection_mode = legacy_read | injected | both`. Default `both` während Migration: Skill-Inhalt sowohl injected als auch Read-Markdown drin. Nach 1 Woche stable: `injected`-only.
- **Was bricht möglicherweise:** Customer-Repos mit gestern-installierten Stand (`.template-hash` alt) sehen anderes Verhalten — `setup.sh --update` muss vor erstem Skill-Injection-Run laufen.
- **Erfolgskriterium:** `grep -rn "Read('skills/" agents/ commands/` returnt 0. E2E-Test spawnt Backend-Subagent in fresh Customer-Install (per `setup.sh` in tmp dir) und asserted `⚡ Backend Dev joined` im ersten Output.

### Maßnahme 3 — `applies_to:` Frontmatter + Loader-Enforcement (NEU)

- **Kills:** Cluster 7 (Scope-Markierung), reinforces 1+4
- **Effort:** L (1 Woche Implementation + 1-2 Wochen schrittweise Frontmatter-Defaults verfeinern)
- **Risk:** **low** — jede Rule/Skill bekommt zunächst `applies_to: all-agents` als Default → kein Verhaltens-Change. Loader-Hard-Fail kommt erst nach Refinement.
- **Risk-mitigation:** Migration in zwei Phasen: (1) Frontmatter überall hinzufügen, Default `all-agents`, kein Hard-Fail. (2) Frontmatter-Werte verfeinern mit Hard-Fail aktiviert.
- **Was bricht möglicherweise:** Wenn ein Skill sein eigenes `applies_to:` falsch setzt, wird es nicht mehr geladen — Tests müssen das fangen.
- **Erfolgskriterium:** Pre-Commit-Hook blockt Commit ohne `applies_to:`. Loader wirft hard error wenn Scope nicht passt. Replay des Lauf-1-Szenarios: `expert-audit-scope.md` mit `applies_to: audit-runtime-only` würde von einem general-purpose-Agent nicht mehr fälschlich gelesen.

### Maßnahme 4 — Self-install drift CI-gate (Cluster 3)

- **Kills:** Cluster 3 (self-install rot), reinforces 1
- **Effort:** S (1-2 Tage)
- **Risk:** **low** — fügt CI-Step hinzu. Risiko: noisy wenn `setup.sh` nicht-deterministisch bei Timestamps. Mitigation: diff ignoriert `framework.updated_at` und `.template-hash`.
- **Was bricht möglicherweise:** Erste paar PRs nach Activation werden von alten Devs als überraschend empfunden ("warum failed CI obwohl ich nichts an `agents/` angefasst habe?" — weil die Install-Kopie outdated war).
- **Erfolgskriterium:** GitHub-Action `self-install-up-to-date` required auf `main`. `framework.updated_at` trail't den letzten Pipeline-affecting commit max 1 Tag.

### Maßnahme 5 — Threads-Persistence vereinheitlichen + dead-code cull (Cluster 6)

- **Kills:** Cluster 6 (two-truth), partial 2
- **Effort:** M (1 Woche)
- **Risk:** **medium** — Löschung von `sidekick-policy.ts`, `sidekick-converse.ts`, `sidekick-tools.ts` (1869 LOC + 1562 Test-LOC) plus `/api/sidekick/converse` Endpoint plus in-memory `threads`-Map in `sidekick-chat.ts`.
- **Risk-mitigation:** Erst nach Maßnahme 1 stabil 1 Woche. Tag-Commit `[remove-after-1-week-stable]`.
- **Was bricht möglicherweise:** Browser-Widget-Code im just-ship-board-Repo der noch `/api/sidekick/converse` calls — koordinieren.
- **Erfolgskriterium:** Net code-reduction ~3400 LOC. CI grün. 48h Sentry zeigt 0 Errors für removed names.

### Maßnahme 6 — Test-coverage spine (Cluster 5)

- **Kills:** Cluster 5
- **Effort:** L (parallelisierbar — 1-2 Tickets pro untested File)
- **Risk:** **low** — Test-Code kann Production nicht brechen.
- **Was bricht möglicherweise:** Nichts direkt, aber Time-Trade-off gegen Features.
- **Risk-mitigation:** Tests als Preis für nächsten Feat der die Datei berührt — kein dedizierter Test-Sprint.
- **Erfolgskriterium:** Vitest-Coverage-Report in CI; `pipeline/lib/{worktree-manager,qa-runner,event-hooks,watchdog,drain,config}.ts` ≥60% Line-Coverage. Block-merge below threshold.

### Maßnahme 7 — Branch-Check als deterministischer Hook (Cluster 4)

- **Kills:** Cluster 4 (process bypass)
- **Effort:** S (1-2 Tage)
- **Risk:** **medium** — wenn der Hook overzealous ist, blockt er legitimes Arbeiten.
- **Risk-mitigation:** Konservativer als die Markdown-Rule heute: nur block bei `main` + Pipeline-configured + Edit/Write tool. Override via `JUST_SHIP_ALLOW_MAIN_EDIT=1` env.
- **Was bricht möglicherweise:** Direkt-Edit-Workflows (CHANGELOG-Fix, README-Tweak) brauchen den Override — Doku notwendig.
- **Erfolgskriterium:** `.claude/hooks/pre-tool-use-branch-check.sh` aktiv in `.claude/settings.json`. Replay 2026-04-21-Incident: blockt erfolgreich.

---

## 8. Phase 8 — Process-Fixes

Was hätte die einzelnen Cluster gefangen, **wenn vorhanden**:

| Cluster | Was hätte es gefangen | Wo sollte es leben |
|---|---|---|
| 1 (topology) | E2E-Test der einen Subagent spawnt und über Sentry-Breadcrumb prüft, ob das Skill im System-Prompt ankam | `pipeline/lib/load-skills.e2e.test.ts` (NEU); Breadcrumb-Sink |
| 1 (topology) | CI-Step: `grep -rn "Read('skills/" agents/ commands/` exit non-zero | `.github/workflows/build-pipeline.yml` Step `verify-no-source-paths-in-prompts` |
| 2 (built-not-wired) | Type-Lock zwischen Tool-Registry und SDK-`allowedTools` | `pipeline/lib/sidekick-chat.ts` — `allowedTools: listSidekickReasoningToolNames()` |
| 2 (built-not-wired) | Mandatory Integration-Test wenn ein Ticket "Tool-Registry"/"Endpoint-List"/"Hook-Set" baut | `.claude/rules/wire-or-delete.md` (NEU) — codifiziert |
| 3 (self-install rot) | `setup.sh --check` failing in CI | `.github/workflows/self-install-up-to-date.yml` (NEU) |
| 3 (self-install rot) | Pre-commit-Hook: `framework.updated_at` darf nicht älter sein als letzter Commit auf `agents/`/`commands/`/`skills/`/`pipeline/` | `.githooks/pre-commit` extension |
| 4 (process bypass) | Branch-Check als deterministischer Hook, nicht Markdown | `.claude/hooks/pre-tool-use-branch-check.sh` (NEU) |
| 4 (process bypass) | Sidekick-Routing als deterministischer Hook für ersten User-Message in Session | `.claude/hooks/on-user-prompt-submit-sidekick-route.sh` (NEU) |
| 5 (test coverage) | Coverage-Threshold-Check in CI | `.github/workflows/build-pipeline.yml` add `npm run coverage:check` |
| 5 (test coverage) | Mandatory Test für jede neue Datei unter `pipeline/lib/` | `.claude/rules/no-prod-without-test.md` (NEU) |
| 6 (two-truth) | Lint-Rule: `@deprecated` JSDoc-Tag failed Build wenn nicht innerhalb N Tagen gelöscht | `pipeline/eslint.config.ts` (NEU) |
| **7 (Scope-Markierung)** | `applies_to:`-Frontmatter + Pre-Commit + Loader-Enforcement | `.githooks/pre-commit` + `pipeline/lib/load-rules.ts` (NEU) |

---

## 9. Phase 9 — Memory-Update-Vorschläge

| Ziel | Inhalt | Begründung |
|---|---|---|
| **Mem0** (user-level, projektübergreifend) | "Just Ship: jedes Markdown-Artefakt (Rule, Skill, Agent, Command) sollte ein `applies_to:`-Frontmatter-Feld haben, das maschinenlesbar Anwendungs-Scope deklariert. Loader hard-failed bei Scope-Mismatch. Wurzel-Lehre aus 3 Bugs in 48h (T-1014, CTO-Audit-V1-Scope, Reporter-Install)." | Generalisierbares Pattern, gilt für jedes self-installing framework. Pattern: "every artifact knows where it lives". |
| **Mem0** | "Just Ship Sidekick-Wave April 2026: Built-but-not-wired-Pattern. Tool-Registries (sidekick-reasoning-tools.ts) wurden entwickelt aber `allowedTools: []` in Konsumer (sidekick-chat.ts:394). Tests im Tool-File grün, Production tot. Vor Approval immer Konsumer-Test fordern." | Lehre aus T-983/986. Verhindert Wiederholung. |
| `.claude/rules/wire-or-delete.md` (NEU) | "Wenn ein Ticket eine Tool-Registry, Endpoint-Liste, oder Hook-Set baut, muss die selbe PR einen Integration-Test enthalten, der beweist dass mindestens ein Konsumer die Registry tatsächlich aufruft. Sonst gilt das Ticket als unfertig." | Cluster 2 root cause |
| `.claude/rules/no-source-path-in-prompts.md` (NEU) | "Markdown-Strings in `agents/`, `commands/`, `skills/` dürfen keinen Pfad enthalten der `skills/<x>/SKILL.md` (Source) oder `.claude/skills/<x>.md` (Install) lautet. Stattdessen via Skill-Tool oder via Pipeline-Injection. Hook prüft das pre-commit." | Cluster 1 root cause |
| `.claude/rules/applies-to-required.md` (NEU) | "Jede Datei unter `.claude/rules/`, `agents/`, `commands/`, `skills/<n>/SKILL.md` MUSS eine `applies_to:`-Frontmatter-Zeile haben. Loader hard-failed bei Mismatch. Werte aus kontrolliertem Vokabular (s. `pipeline/lib/load-rules.ts`)." | Cluster 7 root cause |
| `.claude/rules/setup-sh-required-after-source-edit.md` (NEU) | "Nach einem Edit in `agents/`, `commands/`, `skills/`, `pipeline/`, oder `templates/` MUSS der nächste Commit einen aktualisierten `framework.updated_at`-Stempel haben (via `setup.sh --update`). Pre-commit-Hook enforced." | Cluster 3 |
| **CLAUDE.md** (Constitution) | Add line under "Execution posture": "Built artifact ≠ shipped feature — every new tool, endpoint, hook, or skill MUST have at least one integration test proving the consumer reaches it before the ticket can close." | Cluster 2 deserves constitutional protection |
| **CLAUDE.md** (Constitution) | Add line: "Every artifact under `.claude/rules/`, `agents/`, `commands/`, `skills/` declares its scope via `applies_to:` frontmatter. The loader hard-fails on mismatch." | Cluster 7 deserves constitutional reference |
| `docs/just-ship-operating-model.md` | Refine § "Architecture of loaded context": "Skill content is injected into agent prompts at spawn time via `appendSystemPrompt`, NOT loaded by the agent through markdown instructions. The agent never reads its own skill file." Plus add a column "applies_to defaults" to the tier table. | Reflects fix from Maßnahme 2+3 — Vision und Code align. |
| `docs/just-ship-operating-model.md` | Refine § "Two execution paths" mit der echten Endpoint-Liste (14 Sidekick-Endpoints + Path-1+2). | Vision-Drift Code-Review §MED-5. |

---

## 10. Caveats & What I Did NOT Verify (V2)

- **Keine echten parallelen Subagents.** Erklärt im Header — `Agent`/`Task`-Tool nicht im SDK verfügbar. Single-Context mit erweitertem Tool-Use als Kompensation.
- **Vitest nicht ausgeführt.** Coverage-Aussagen sind LOC-basiert (Test-File da/nicht da), nicht Coverage-%-basiert.
- **`pipeline/server.ts` (2208 LOC) nur via grep durchgegangen.** Endpoint-Liste verifiziert; einzelne Handler nicht zeile-für-zeile gelesen.
- **`just-ship-board`/`-bot`/`-web` Source-Trees nicht gelesen.** Cross-Repo-Schema-Drift, Browser-Sidekick-Code, Bot-Auth-Pfade — out of scope. Empfehlung im Report ist auf gleiche Vorgehensweise pro-Repo zu pushen.
- **Sentry-Instrumentation Names verifiziert (`audit-runtime.ts`, `sidekick-chat.ts`), aber Live-Feuern nicht beobachtet.**
- **Coolify/VPS-Deploy-Pfade** (`coolify-preview.ts`, `vps/Dockerfile`) nicht geprüft.
- **Git-Log-Pattern für `.env` Leakage nicht ausgeführt** (Security §LOW). Empfehlung explizit.
- **`.claude/.token-snapshot-T-*.json` Inhalt nicht inspiziert** (Security §LOW). Sind als untracked — wenn Secrets enthalten, wäre das ein dringender Findings-Upgrade.
- **MCP-Server-Validation** (`@shopify/dev-mcp` etc.) nicht geprüft — vertraut auf die Konfiguration.
- **Single time-point.** Snapshot. State kann sich ändern.

---

**Ende des Reports — V2.**

Lauf 1 (`docs/audits/2026-04-25-cto-deep-audit.md`) bleibt unverändert für Audit-Trail.

Wenn nur drei Maßnahmen umgesetzt werden, sollte die Reihenfolge sein:
1. Sidekick reasoning tools verkabeln (Maßnahme 1).
2. `applies_to:`-Frontmatter + Loader-Enforcement (Maßnahme 3) — verhindert dass Maßnahme 1 in Customer-Installs wieder bricht.
3. CI-Drift-Gate (Maßnahme 4) — sichert die ersten beiden gegen schleichende Regression ab.
