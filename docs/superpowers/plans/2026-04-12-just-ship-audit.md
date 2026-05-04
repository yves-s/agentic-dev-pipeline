# Just Ship Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/just-ship-audit` command that discovers `category: audit` skills, dispatches parallel agents, and produces a consolidated severity-sorted report.

**Architecture:** The command is a markdown file (`commands/just-ship-audit.md`) interpreted by the executing agent. It globs `.claude/skills/*.md` for `category: audit` frontmatter, spawns one Agent per skill in parallel, collects JSON findings, deduplicates, and writes a report to `docs/audit/`. Plugin skills get `category` and `audit_scope` fields added to their frontmatter. The pipeline's `load-skills.ts` is extended to parse these new fields.

**Tech Stack:** Markdown commands, YAML frontmatter, Claude Code Agent tool, TypeScript (load-skills.ts)

---

## Task 1: Extend `SkillFrontmatter` to include `category` and `audit_scope`

**Files:**
- Modify: `.pipeline/lib/load-skills.ts:29-34` (SkillFrontmatter interface)
- Modify: `.pipeline/lib/load-skills.ts:53-112` (parseSkillFrontmatter function)
- Test: `.pipeline/lib/load-skills.test.ts`

- [ ] **Step 1: Write failing tests for new frontmatter fields**

In `.pipeline/lib/load-skills.test.ts`, add tests:

```typescript
describe("parseSkillFrontmatter - audit fields", () => {
  it("parses category and audit_scope from frontmatter", () => {
    const content = `---
name: security-review
description: OWASP security analysis
category: audit
audit_scope: full
---

# Security Review
Body content here.`;

    const result = parseSkillFrontmatter(content);
    expect(result).not.toBeNull();
    expect(result!.category).toBe("audit");
    expect(result!.auditScope).toBe("full");
  });

  it("defaults auditScope to 'both' when category is audit but audit_scope is missing", () => {
    const content = `---
name: find-bugs
description: Find bugs
category: audit
---

# Find Bugs`;

    const result = parseSkillFrontmatter(content);
    expect(result!.category).toBe("audit");
    expect(result!.auditScope).toBe("both");
  });

  it("returns undefined category when not set", () => {
    const content = `---
name: frontend-design
description: Design skill
---

# Frontend Design`;

    const result = parseSkillFrontmatter(content);
    expect(result!.category).toBeUndefined();
    expect(result!.auditScope).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/yschleich/Developer/just-ship && npx vitest run .pipeline/lib/load-skills.test.ts`
Expected: FAIL — `category` and `auditScope` properties don't exist on `SkillFrontmatter`

- [ ] **Step 3: Add fields to SkillFrontmatter interface**

In `.pipeline/lib/load-skills.ts`, modify the interface:

```typescript
/** Parsed frontmatter from a skill file */
export interface SkillFrontmatter {
  name: string;
  description: string;
  triggers: string[];
  filePath: string;
  category?: string;
  auditScope?: string;
}
```

- [ ] **Step 4: Parse category and audit_scope in parseSkillFrontmatter**

In `.pipeline/lib/load-skills.ts`, add parsing before the `return` statement (before line 112):

```typescript
  // category (e.g. "audit")
  const categoryMatch = frontmatter.match(/^category:\s*(.+)$/m);
  const category = categoryMatch ? categoryMatch[1].trim() : undefined;

  // audit_scope — only meaningful when category is "audit"
  const auditScopeMatch = frontmatter.match(/^audit_scope:\s*(.+)$/m);
  const auditScope = category === "audit"
    ? (auditScopeMatch ? auditScopeMatch[1].trim() : "both")
    : undefined;

  if (!name) return null;

  return { name, description, triggers, filePath: "", category, auditScope };
```

Remove the existing `if (!name) return null;` and `return` on lines 110-112 since they're replaced above.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/yschleich/Developer/just-ship && npx vitest run .pipeline/lib/load-skills.test.ts`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add .pipeline/lib/load-skills.ts .pipeline/lib/load-skills.test.ts
git commit -m "feat: parse category and audit_scope from skill frontmatter"
```

---

## Task 2: Add `category: audit` and `audit_scope` to plugin skills

**Files:**
- Modify: `.claude/skills/plugin--sentry-skills--security-review.md` (lines 1-6)
- Modify: `.claude/skills/plugin--sentry-skills--find-bugs.md` (lines 1-4)
- Modify: `.claude/skills/plugin--sentry-skills--code-review.md` (lines 1-4)
- Modify: `.claude/skills/plugin--sentry-skills--gha-security-review.md` (lines 1-5)
- Modify: `.claude/skills/plugin--differential-review--differential-review.md` (lines 1-8)
- Modify: `.claude/skills/plugin--insecure-defaults--insecure-defaults.md` (lines 1-8)

- [ ] **Step 1: Add frontmatter to security-review**

In `.claude/skills/plugin--sentry-skills--security-review.md`, add after `license: LICENSE`:

```yaml
category: audit
audit_scope: full
```

- [ ] **Step 2: Add frontmatter to find-bugs**

In `.claude/skills/plugin--sentry-skills--find-bugs.md`, add after `description:`:

```yaml
category: audit
audit_scope: diff
```

- [ ] **Step 3: Add frontmatter to code-review**

In `.claude/skills/plugin--sentry-skills--code-review.md`, add after `description:`:

```yaml
category: audit
audit_scope: both
```

- [ ] **Step 4: Add frontmatter to gha-security-review**

In `.claude/skills/plugin--sentry-skills--gha-security-review.md`, add before the closing `---` of the frontmatter block:

```yaml
category: audit
audit_scope: full
```

- [ ] **Step 5: Add frontmatter to differential-review**

In `.claude/skills/plugin--differential-review--differential-review.md`, add before the closing `---` of the frontmatter block (after the last `- Write` line):

```yaml
category: audit
audit_scope: diff
```

- [ ] **Step 6: Add frontmatter to insecure-defaults**

In `.claude/skills/plugin--insecure-defaults--insecure-defaults.md`, add before the closing `---` of the frontmatter block (after the last `- Bash` line):

```yaml
category: audit
audit_scope: full
```

- [ ] **Step 7: Verify all 6 skills have correct frontmatter**

Run: `cd /Users/yschleich/Developer/just-ship && grep -l "category: audit" .claude/skills/plugin--*.md | wc -l`
Expected: `6`

Run: `grep -A1 "category: audit" .claude/skills/plugin--*.md`
Expected: Each file shows `category: audit` followed by `audit_scope: full|diff|both`

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/plugin--*.md
git commit -m "feat: add category: audit frontmatter to plugin skills"
```

---

## Task 3: Create the `/just-ship-audit` command

**Files:**
- Create: `commands/just-ship-audit.md`

- [ ] **Step 1: Create the command file**

Create `commands/just-ship-audit.md` with the following content:

````markdown
---
name: just-ship-audit
description: /just-ship-audit — Paralleles Security- und Quality-Audit via discovered Skills
---

# /just-ship-audit — Parallel Audit

Discovert alle `category: audit` Skills im Projekt und dispatcht sie parallel als Agents. Konsolidiert Findings in einem Report.

## Konfiguration

Keine Pipeline-Verbindung noetig. Der Command funktioniert standalone in jedem Projekt mit installierten Audit-Skills.

## CLI Interface

```
/just-ship-audit                                    # Full Audit, alle discovered Skills
/just-ship-audit --diff                             # Nur Branch-Diff gegen main
/just-ship-audit --skills security-review,find-bugs # Nur bestimmte Skills
```

`$ARGUMENTS` wird geparsed:
- Enthält `--diff` → Diff-Modus (nur `diff` und `both` Skills)
- Enthält `--skills skill1,skill2` → nur diese Skills ausfuehren
- Leer oder ohne Flags → Full-Modus (nur `full` und `both` Skills)

## Ausfuehrung

### 1. Skills discovern

Glob `.claude/skills/*.md` und lese jede Datei. Parse das YAML-Frontmatter und filtere nach `category: audit`.

Extrahiere fuer jeden Audit-Skill:
- `name` — Skill-Name
- `audit_scope` — `full`, `diff` oder `both` (Default: `both`)
- Den gesamten Dateiinhalt als Skill-Instruktion

Falls `--skills` angegeben: filtere zusaetzlich nach den angegebenen Namen.

**Falls keine Audit-Skills gefunden:**

```
Keine Audit-Skills gefunden. Installiere Audit-Plugins in project.json:

  "plugins": {
    "dependencies": [
      {"plugin": "sentry-skills@sentry-skills", "skills": ["security-review", "find-bugs"]},
      "insecure-defaults@trailofbits"
    ]
  }

Dann fuehre setup.sh aus um die Skills zu installieren.
```

Stoppe hier — keine Agents dispatchen.

### 2. Scope bestimmen

- **Full-Modus** (Default): Filtere Skills mit `audit_scope: full` oder `audit_scope: both`
- **Diff-Modus** (`--diff`): Filtere Skills mit `audit_scope: diff` oder `audit_scope: both`

Falls Diff-Modus, hole den Diff:
```bash
git diff $(git merge-base HEAD main)...HEAD
```

Falls der Diff leer ist (kein Unterschied zu main), melde:
```
Kein Diff zu main — nichts zu auditen im Diff-Modus.
```
Stoppe hier.

Zeige dem User welche Skills ausgefuehrt werden:
```
Audit startet — {N} Skills discovered:
  - {skill_name} ({audit_scope})
  - ...

Scope: {Full project | Branch diff (X files changed)}
```

### 3. Agents parallel dispatchen

Dispatche **alle** Agents in einem einzigen Response-Block (parallel). Jeder Agent bekommt:

**Agent-Typ:** `general-purpose`

**Agent-Prompt (pro Skill):**

```
Du fuehrst ein Audit dieses Projekts durch mit dem "{skill_name}" Skill.

## Scope
{Im Full-Modus: "Analysiere die gesamte Codebase. Lies relevante Dateien, verstehe die Architektur, und fuehre das Audit gemaess den Skill-Instruktionen durch."
 Im Diff-Modus: "Analysiere NUR den Branch-Diff gegen main. Hier ist der Diff:\n\n{diff_output}"}

## Skill-Instruktionen
{gesamter Skill-Dateiinhalt}

## Output-Format

Gib deine Findings als JSON-Array zurueck. Wrape das JSON in einen ```json Code-Block.
Jedes Finding hat diese Struktur:

```json
[
  {
    "id": "{SKILL-PREFIX}-001",
    "severity": "critical|high|medium|low",
    "title": "Kurze Beschreibung",
    "location": "pfad/zur/datei.ts:42",
    "description": "Was ist falsch und warum",
    "fix": "Wie man es behebt",
    "confidence": "high|medium",
    "source": "{skill_name}"
  }
]
```

Regeln:
- Prefix fuer IDs: Verwende einen kurzen Prefix basierend auf dem Skill-Namen (z.B. SEC fuer security-review, BUG fuer find-bugs, DEF fuer insecure-defaults, GHA fuer gha-security-review, DIFF fuer differential-review, CR fuer code-review)
- Nur HIGH und MEDIUM Confidence Findings reporten
- Falls keine Findings: gib ein leeres Array zurueck: []
- Kein zusaetzlicher Text ausserhalb des JSON-Blocks
```

### 4. Findings konsolidieren

Nachdem alle Agents fertig sind:

1. **JSON extrahieren:** Fuer jeden Agent-Output, extrahiere das JSON aus dem ```json Code-Block. Falls kein Code-Block vorhanden, versuche den gesamten Output als JSON zu parsen. Falls beides scheitert, logge eine Warnung fuer diesen Skill.

2. **Deduplizieren:** Zwei Ebenen:
   - **Identitaet:** Jedes Finding ist eindeutig via `source + id` (z.B. `security-review/SEC-001` ist verschieden von `find-bugs/SEC-001`)
   - **Cross-Skill-Duplikate:** Falls zwei Findings von verschiedenen Skills die gleiche `location + title` haben, behalte das mit der hoeheren Severity und notiere den Duplikat-Source.

3. **Sortieren:** Critical → High → Medium → Low. Innerhalb einer Severity-Stufe nach Location sortieren.

4. **Zaehlen:** Findings pro Severity-Stufe zaehlen.

### 5. Report schreiben

Erstelle `docs/audit/` Verzeichnis falls es nicht existiert:
```bash
mkdir -p docs/audit
```

Schreibe den Report nach `docs/audit/{YYYY-MM-DD}-audit-report.md`:

```markdown
# Audit Report — {YYYY-MM-DD}

## Summary
| Metric | Value |
|---|---|
| Skills executed | {N} |
| Skills failed | {M} (falls > 0) |
| Scope | Full project / Branch diff |
| Findings | {total} |
| Critical | {count} |
| High | {count} |
| Medium | {count} |
| Low | {count} |

## Skills Executed
- {skill_name_1} (scope: {audit_scope})
- {skill_name_2} (scope: {audit_scope})
{Falls Skills gefailed: }
- ⚠ {skill_name} — FAILED: {grund}

## Critical

### [{id}] {title}
- **Source:** {source}
- **Location:** `{location}`
- **Confidence:** {confidence}
- **Description:** {description}
- **Fix:** {fix}

## High
{gleiche Struktur}

## Medium
{gleiche Struktur}

## Low
{gleiche Struktur}
```

### 6. Terminal Summary

Zeige eine kompakte Zusammenfassung:

```
Audit complete — {N} skills, {total} findings

  {X} Critical  {bar}
  {Y} High      {bar}
  {Z} Medium    {bar}
  {W} Low       {bar}

  Full report: docs/audit/{YYYY-MM-DD}-audit-report.md
```

Die Bars sind proportionale Unicode-Bloecke (█). Laengster Bar = 20 Zeichen, andere proportional.

Falls keine Findings:
```
Audit complete — {N} skills, 0 findings

  Clean bill of health.

  Full report: docs/audit/{YYYY-MM-DD}-audit-report.md
```
````

- [ ] **Step 2: Verify the command file is valid markdown with frontmatter**

Run: `head -5 /Users/yschleich/Developer/just-ship/commands/just-ship-audit.md`
Expected: Shows `---`, `name:`, `description:`, `---` frontmatter block

- [ ] **Step 3: Commit**

```bash
git add commands/just-ship-audit.md
git commit -m "feat: add /just-ship-audit command for parallel skill-based auditing"
```

---

## Task 4: Copy the command into `.claude/commands/`

**Files:**
- Create: `.claude/commands/just-ship-audit.md` (copy)

Commands in `commands/` are the source of truth. `setup.sh` copies them into `.claude/commands/` for Claude Code to discover. For development, copy manually.

- [ ] **Step 1: Copy the command file**

```bash
cd /Users/yschleich/Developer/just-ship
cp commands/just-ship-audit.md .claude/commands/just-ship-audit.md
```

- [ ] **Step 2: Verify the copy is identical**

Run: `diff commands/just-ship-audit.md .claude/commands/just-ship-audit.md && echo "IDENTICAL"`
Expected: `IDENTICAL`

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/just-ship-audit.md
git commit -m "chore: copy just-ship-audit command into .claude/commands/"
```

---

## Task 5: Integration test — dry run

This task validates the full flow manually.

- [ ] **Step 1: Verify skill discovery works**

Run: `cd /Users/yschleich/Developer/just-ship && grep -l "category: audit" .claude/skills/*.md`
Expected: Lists all 6 plugin skills with `category: audit`

- [ ] **Step 2: Verify each skill has the correct audit_scope**

Run: `cd /Users/yschleich/Developer/just-ship && for f in $(grep -l "category: audit" .claude/skills/*.md); do echo "$(basename $f): $(grep 'audit_scope:' $f | head -1)"; done`
Expected:
```
plugin--sentry-skills--security-review.md: audit_scope: full
plugin--sentry-skills--find-bugs.md: audit_scope: diff
plugin--sentry-skills--code-review.md: audit_scope: both
plugin--sentry-skills--gha-security-review.md: audit_scope: full
plugin--differential-review--differential-review.md: audit_scope: diff
plugin--insecure-defaults--insecure-defaults.md: audit_scope: full
```

- [ ] **Step 3: Verify the command is discoverable**

Run: `test -f /Users/yschleich/Developer/just-ship/.claude/commands/just-ship-audit.md && echo "EXISTS"`
Expected: `EXISTS`

- [ ] **Step 4: Run the full test suite**

Run: `cd /Users/yschleich/Developer/just-ship && npx vitest run`
Expected: All tests pass, including the new load-skills tests

- [ ] **Step 5: Final commit if any fixes needed**

Only if previous steps required fixes:
```bash
git add -A
git commit -m "fix: address integration test findings for just-ship-audit"
```
