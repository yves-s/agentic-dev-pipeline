# Just Ship Audit — Design Spec

**Date:** 2026-04-12
**Status:** Draft

## Problem

Just-ship projects can install audit-quality skills via plugins (sentry-skills, differential-review, insecure-defaults), but there is no unified way to run them. Users must invoke each skill manually, interpret separate outputs, and mentally consolidate findings. There is no `/audit` command, no discovery mechanism, and no consolidated report.

## Solution

A `/just-ship-audit` command that:

1. Discovers all audit-capable skills in the project via frontmatter metadata
2. Dispatches one agent per skill in parallel
3. Consolidates findings into a single severity-sorted report
4. Outputs a summary to the terminal and a full report to `docs/audit/`

## Design

### Frontmatter Extension

Skills opt into audit discovery by adding two fields to their YAML frontmatter:

```yaml
---
name: security-review
description: OWASP security analysis
category: audit
audit_scope: full
---
```

| Field | Type | Required | Values | Default |
|---|---|---|---|---|
| `category` | string | Yes (for audit) | `audit` | — |
| `audit_scope` | string | No | `full`, `diff`, `both` | `both` |

- `full` — skill scans the entire codebase
- `diff` — skill scans only the branch diff against main
- `both` — skill can do either, command decides based on `--diff` flag

### Discovery

The command reads all skill files from `.claude/skills/` (which includes plugin-installed skills). It parses frontmatter and filters for `category: audit`.

If no audit skills are found, the command prints a helpful message:

```
No audit skills found. Install audit plugins in project.json:

  "plugins": {
    "dependencies": [
      {"plugin": "sentry-skills@sentry-skills", "skills": ["security-review", "find-bugs"]},
      "insecure-defaults@trailofbits"
    ]
  }
```

### Scope

| Mode | Trigger | Behavior |
|---|---|---|
| Full project | Default (no flag) | All `full` and `both` skills run on full codebase |
| Branch diff | `--diff` flag | All `diff` and `both` skills run on `git diff main...HEAD` |

Skills with mismatched scope are skipped silently (e.g., a `diff`-only skill is skipped in full-project mode).

### Execution

The command is a markdown file interpreted by an agent (not a script). Discovery, dispatch, and consolidation are all performed by the executing agent following the command instructions.

1. **Discover** — glob `.claude/skills/*.md`, read each file's frontmatter, filter `category: audit`
2. **Scope** — determine full vs diff mode from CLI args
3. **Filter** — exclude skills whose `audit_scope` does not match the mode
4. **Dispatch** — the executing agent spawns one Agent tool call per discovered skill, all in a single response block (parallel execution). Each agent receives:
   - The skill content as system instruction
   - The scope context (full codebase description or diff output)
   - A standardized output format template (see Agent Prompt Template below)
5. **Collect** — wait for all agents to complete
6. **Consolidate** — merge findings from all agents. Extract JSON from markdown code fences if agents wrap their output. Handle partial or malformed output by logging a warning and including whatever findings could be parsed.
7. **Deduplicate** — group by `source + id` (each skill prefixes its own IDs, so `security-review/SEC-001` is distinct from `find-bugs/SEC-001`). If two findings from different skills share the same `location + title`, keep the higher-severity one and note the duplicate source.
8. **Output** — summary to terminal, full report to file

### Error Handling

- **Agent timeout/failure**: If an agent fails or returns no parseable findings, the consolidation step includes a warning in the report listing which skills failed and why. Partial results from successful agents are still reported.
- **No audit skills found**: Print a helpful message with example `project.json` config (see Discovery section). Do not dispatch any agents.
- **Malformed JSON**: The consolidating agent extracts JSON from fenced code blocks (```` ```json ... ``` ````), strips commentary, and attempts to parse. Unparseable output is logged as a skill failure.

### Agent Prompt Template

Each dispatched agent receives:

```
You are running an audit of this project using the {skill_name} skill.

## Scope
{full: "Analyze the entire codebase." | diff: "Analyze only the branch diff:\n{diff_output}"}

## Skill Instructions
{skill_content}

## Output Format
Report your findings as a JSON array:
[
  {
    "id": "SEC-001",
    "severity": "critical|high|medium|low",
    "title": "Short description",
    "location": "file:line",
    "description": "What is wrong and why",
    "fix": "How to fix it",
    "confidence": "high|medium",
    "source": "{skill_name}"
  }
]

If no findings, return an empty array: []
```

### CLI Interface

```
/just-ship-audit                                    # Full audit, all discovered skills
/just-ship-audit --diff                             # Branch diff only
/just-ship-audit --skills security-review,find-bugs # Only specific skills
```

### Report Format

#### Terminal Summary

```
Audit complete — 5 skills, 12 findings

  2 Critical  ████████
  4 High      ████████████████
  3 Medium    ████████████
  3 Low       ████████████

  Full report: docs/audit/2026-04-12-audit-report.md
```

#### File Report (`docs/audit/YYYY-MM-DD-audit-report.md`)

```markdown
# Audit Report — 2026-04-12

## Summary
| Metric | Value |
|---|---|
| Skills executed | 5 |
| Scope | Full project |
| Findings | 12 |
| Critical | 2 |
| High | 4 |
| Medium | 3 |
| Low | 3 |

## Skills Executed
- security-review (sentry-skills)
- find-bugs (sentry-skills)
- insecure-defaults (trailofbits)
- differential-review (trailofbits)
- code-review (sentry-skills)

## Critical

### [SEC-001] SQL Injection in user endpoint
- **Source:** security-review
- **Location:** `src/api/users.ts:42`
- **Confidence:** High
- **Description:** User input interpolated directly into SQL query...
- **Fix:** Use parameterized query...

## High
...

## Medium
...

## Low
...
```

## Files to Change

| File | Action | Description |
|---|---|---|
| `commands/just-ship-audit.md` | Create | New command definition |
| `.claude/skills/plugin--sentry-skills--security-review.md` | Edit | Add `category: audit`, `audit_scope: full` |
| `.claude/skills/plugin--sentry-skills--find-bugs.md` | Edit | Add `category: audit`, `audit_scope: diff` |
| `.claude/skills/plugin--sentry-skills--code-review.md` | Edit | Add `category: audit`, `audit_scope: both` |
| `.claude/skills/plugin--sentry-skills--gha-security-review.md` | Edit | Add `category: audit`, `audit_scope: full` |
| `.claude/skills/plugin--differential-review--differential-review.md` | Edit | Add `category: audit`, `audit_scope: diff` |
| `.claude/skills/plugin--insecure-defaults--insecure-defaults.md` | Edit | Add `category: audit`, `audit_scope: full` |
| `.pipeline/lib/load-skills.ts` | Edit | Parse `category` and `audit_scope` from frontmatter (only if pipeline needs audit awareness later — optional for v1) |

## Out of Scope

- Pipeline integration (automatic audit on every ticket) — future enhancement
- Framework-bundled audit skills — projects bring their own via plugins
- Auto-fix of findings — report only, user decides what to address
- CI/CD integration — manual command only for now
