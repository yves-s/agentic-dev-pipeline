---
applies_to: customer-projects-only
---

At session start in a **consumer project**, check if the installed framework version may be outdated.

**IMPORTANT: This rule is READ-ONLY. Do NOT run any bash commands. Only use the Read tool to check files, then report findings as text.**

This rule is scoped `customer-projects-only` because the engine repo itself does not maintain a `.pipeline/` install copy or a `.claude/.pipeline-version` stamp (T-1064) — there is nothing to be "out of date" with. Consumer projects, which receive the framework via `setup.sh`, still need this informational hint.

1. Read `project.json` and extract `framework.version` and `framework.updated_at`
2. If `framework` is not set or `updated_at` is empty, stop silently — project was installed before versioning existed
3. Compare `updated_at` to today's date. If the framework was updated within the last 14 days, stop silently
4. If older than 14 days, show once:

> ⚠ Framework zuletzt aktualisiert: {updated_at} ({version}). Run `setup.sh --check` to see if updates are available.

This check runs ONCE at session start. Do not repeat it during the session. Do not block work — it is an informational hint only.
