---
name: ship
description: Alles abschliessen — commit, push, PR, merge, zurück auf main. Vollständig autonom, NULL Rückfragen. Unterstützt /ship T-{N} für direkten Branch-Zugriff.
---

# /ship — Ticket abschließen

**Du selbst (Hauptkontext) führst KEINE Ship-Schritte aus.** Deine einzige Aufgabe in diesem Command: einen `orchestrator`-Subagent spawnen, der die Pre-Merge-Checks, Push, PR-Erstellung, Merge und Cleanup ausführt. Du siehst alles live im Stream (`⚡ Orchestrator joined`, `▶ build · running`, `✓ merge · squashed`, etc.) — keine Hintergrundprozesse.

## Trigger

- `/ship`
- `/ship T-{N}` — direkter Branch-Zugriff
- "passt", "done", "fertig", "klappt", "sieht gut aus", "ship it", "merge", "mach den PR rein" — kontextsensitiv per `.claude/rules/ship-trigger-context.md`

## Ausführung

### Schritt 1 — Branch + Ticket-Nummer ermitteln

```bash
TICKET_NUMBER=$(echo "$ARGUMENTS" | grep -oE '[0-9]+' | head -1)
if [ -z "$TICKET_NUMBER" ]; then
  TICKET_NUMBER=$(git branch --show-current | grep -oE 'T-[0-9]+' | head -1 | sed 's/T-//')
fi
if [ -z "$TICKET_NUMBER" ] && [ -f .claude/.active-ticket ]; then
  TICKET_NUMBER=$(cat .claude/.active-ticket | grep -oE '[0-9]+' | head -1)
fi
if [ -z "$TICKET_NUMBER" ]; then
  echo "ERROR: /ship benötigt Ticket-Nummer (z.B. /ship T-123) oder Feature-Branch mit T-{N}-Pattern" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR="$REPO_ROOT/.worktrees/T-$TICKET_NUMBER"
[ ! -d "$WORKTREE_DIR" ] && WORKTREE_DIR="$REPO_ROOT"

CURRENT_BRANCH=$(git -C "$WORKTREE_DIR" branch --show-current)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  # Falls /ship T-N auf main aufgerufen — switche in den Worktree
  if [ -d "$WORKTREE_DIR" ] && [ "$WORKTREE_DIR" != "$REPO_ROOT" ]; then
    CURRENT_BRANCH=$(git -C "$WORKTREE_DIR" branch --show-current)
  else
    echo "ERROR: Auf main, kein Worktree für T-$TICKET_NUMBER. Nichts zu shippen." >&2
    exit 1
  fi
fi

echo "▶ Ticket T-$TICKET_NUMBER · branch $CURRENT_BRANCH"
```

### Schritt 2 — Orchestrator-Subagent spawnen

**Das ist der einzige Implementation-Schritt.** Spawne via Agent-Tool:

```
subagent_type: "orchestrator"
description: "Ship T-{TICKET_NUMBER}"
prompt: |
  ERSTER TOOL-CALL DIESER SESSION (vor allem anderen):
  Read('.claude/agents/orchestrator.md')

  Diese Datei enthält deine Identity, deinen Workflow und deine Skill-Mapping-Tabelle. Befolge sie wörtlich.

  Arbeitsverzeichnis: {WORKTREE_DIR — siehe Schritt 1}
  Branch: {CURRENT_BRANCH — siehe Schritt 1}
  Ticket: T-{TICKET_NUMBER}

  ## Aufgabe

  Ship T-{TICKET_NUMBER} Ende-zu-Ende. Du implementierst nichts mehr — der Branch hat schon Code. Du verifizierst, mergest und räumst auf.

  Pre-Merge-Phase (alle drei MÜSSEN grün sein, sonst Abbruch):
  1. Build-Check: lies `build.web` aus `project.json`, führe aus. Bei Fehler → DevOps-Subagent spawnen, dann Build erneut prüfen.
  2. Tests-Re-Run: lies `build.test` aus `project.json`, führe aus. Bei Fehler → STOPP.
  3. Conflict-Check: `git fetch origin main && git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main` darf keine `<<<<<<<`-Marker enthalten.

  Merge-Phase:
  4. Falls uncommitted changes: `git add <files>` + Commit mit Message-Pattern `feat(T-{N}): {Beschreibung}`.
  5. Push: `git push -u origin <branch>`. Bei Reject: `git pull --rebase`, dann erneut.
  6. PR: `gh pr view 2>/dev/null || gh pr create --title "..." --body "..."`. PR-URL extrahieren.
  7. Falls Pipeline konfiguriert (`pipeline.workspace_id` in project.json): patch `review_url` aufs Ticket via `bash .claude/scripts/board-api.sh patch "tickets/{N}" '{"review_url": "..."}'`.
  8. Merge: `gh pr merge --squash --delete-branch`.

  Post-Merge-Phase:
  9. `cd $REPO_ROOT && git checkout main && git pull origin main`.
  10. Worktree cleanup: `git worktree remove .worktrees/T-{N} --force` falls vorhanden.
  11. Lokalen Branch löschen: `git branch -D feature/T-{N}` (falls noch vorhanden).
  12. Falls Pipeline: status auf `done` patchen, kurze summary mitsenden via `board-api.sh`.
  13. Falls Hosting (`hosting.provider` gesetzt): preview-URL ins Ticket via `bash .claude/scripts/get-preview-url.sh`.

  Befolge die Reporter-Voice (`skills/reporter/SKILL.md`) für alle User-sichtbaren Ausgaben — `▶`/`✓`/`↻`/`✗`-Zeilen. Render am Ende `bash .claude/scripts/ship-summary.sh` mit den richtigen Argumenten.

  Verboten: `git add -A`, `git add .`, `--force` push, `--amend`, `--no-verify`. Bei Konflikt: STOPP, User informieren.

  Output: kurze Zusammenfassung am Ende. Keine Optionen-Listen, keine Rückfragen.
```

### Schritt 3 — Ergebnis anzeigen

Wenn der Orchestrator-Subagent zurückkommt, zeige sein Output direkt an. Keine zusätzliche Prosa.

## Was DU (Hauptkontext) NICHT tust

- Keine Build-Checks selbst.
- Keinen Push selbst.
- Keine PR-Erstellung selbst.
- Keinen Merge selbst.
- Keine Worktree-Cleanups selbst.
- Keine Status-Patches selbst.

## Fehlerbehandlung

- **Auf main:** Hard-Stop, exit 1.
- **Kein Ticket-Argument + kein T-{N}-Branch:** Hard-Stop, exit 1.
- **Build/Tests/Conflict-Check fehlschlägt:** Orchestrator-Subagent meldet zurück, kein Merge.
- **Merge-Konflikte:** Orchestrator stoppt, User entscheidet.
