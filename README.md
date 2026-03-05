# Claude Pipeline Framework

Portables Multi-Agent-System für autonome Software-Entwicklung mit Claude Code.

## Was ist das?

Ein Framework aus generischen Agents, Commands und einem Pipeline-Runner, das in jedes Projekt installiert werden kann. Es bietet:

- **7 spezialisierte Agents** (Orchestrator, Backend, Frontend, Data-Engineer, DevOps, QA, Security)
- **4 Slash-Commands** (/ticket, /ship, /merge, /status)
- **Pipeline-Runner** für VPS/CI-Ausführung
- **Notion-Integration** für Ticket-Management
- **Update-Mechanismus** mit Versionstracking und Dry-Run-Preview

## Quick Start

```bash
# 1. Framework klonen (einmalig)
git clone https://github.com/yves-s/claude-pipeline.git ~/claude-pipeline

# 2. In dein Projekt wechseln
cd /path/to/your/project

# 3. Setup ausführen (interaktiv)
~/claude-pipeline/setup.sh

# 4. CLAUDE.md anpassen (Architektur, Konventionen)
# 5. project.json vervollständigen (Stack, Pfade)

# 6. Loslegen
claude
> /ticket
```

## Setup & Update

### Erstinstallation

```bash
cd /path/to/your/project
/path/to/claude-pipeline/setup.sh
```

Interaktiver Wizard: fragt Projektname, Package Manager, Build-Commands, Notion-URL ab. Erzeugt alle nötigen Dateien.

### Update

Framework-Agents, -Skills oder -Commands verbessert? In jedes Projekt pushen:

```bash
cd /path/to/your/project
/path/to/claude-pipeline/setup.sh --update
```

> **Tipp:** Den korrekten Pfad zum Framework einmalig als Alias anlegen:
> ```bash
> # ~/.zshrc oder ~/.bashrc
> alias pipeline-update='/path/to/claude-pipeline/setup.sh --update'
> ```
> Danach reicht `cd my-project && pipeline-update`.

Das Update überschreibt **nur Framework-Files** und fasst projektspezifische Dateien nie an:

| Wird aktualisiert | Wird nie überschrieben |
|---|---|
| `.claude/agents/*` | `CLAUDE.md` |
| `.claude/commands/*` | `project.json` |
| `.claude/skills/<framework-skill>.md` | `.claude/skills/<eigener-skill>.md` |
| `.claude/settings.json` | |
| `.pipeline/run.sh` | |

Framework-Skills werden hinzugefügt/aktualisiert. Eigene Custom-Skills in `.claude/skills/` die nicht Teil des Frameworks sind, werden nie angefasst.

### Dry Run

Vorher prüfen was sich ändern würde:

```bash
cd /path/to/your/project
/path/to/claude-pipeline/setup.sh --update --dry-run
```

Zeigt welche Files neu, geändert oder entfernt werden — ohne etwas zu ändern.

### Versionstracking

Jede Installation schreibt die Framework-Version nach `.claude/.pipeline-version`. Beim Update siehst du:

```
Installed: abc1234 (2026-02-28)
Available: def5678 (2026-03-02)
```

## Struktur

### Framework (dieses Repo)

```
claude-pipeline/
├── setup.sh                # Install + Update Script
├── agents/                 # Generische Agent-Definitionen
│   ├── orchestrator.md     # Plant, delegiert, shippt
│   ├── backend.md          # API, Hooks, Business Logic
│   ├── frontend.md         # UI Components (design-affin)
│   ├── data-engineer.md    # DB Migrations, RLS, Types
│   ├── devops.md           # Build-Checks, Fixes
│   ├── qa.md               # AC-Verification, Tests, Security
│   └── security.md         # Security Review
├── commands/               # Slash-Commands
│   ├── ticket.md           # Ticket → autonomer Workflow → PR
│   ├── ship.md             # Commit + Push + PR
│   ├── merge.md            # Squash Merge nach Freigabe
│   └── status.md           # Aktueller Stand
├── skills/                 # Framework Skills (auto-deployed)
│   ├── brainstorming.md            # Requirement-Klärung vor Code
│   ├── writing-plans.md            # Implementierungsplan erstellen
│   ├── executing-plans.md          # Plan mit Checkpoints ausführen
│   ├── subagent-driven-development.md  # Multi-Agent Workflows
│   ├── dispatching-parallel-agents.md  # Parallele Tasks
│   ├── test-driven-development.md  # TDD erzwingen
│   ├── systematic-debugging.md     # Root Cause first
│   ├── verification-before-completion.md  # Kein "done" ohne Beweis
│   ├── finishing-a-development-branch.md  # Branch sauber abschliessen
│   ├── requesting-code-review.md   # Code Review Workflow
│   ├── receiving-code-review.md    # Review-Feedback verarbeiten
│   ├── using-git-worktrees.md      # Isolierte Workspaces
│   ├── design.md                   # Design-Token-Standards, Visual QA
│   ├── frontend-design.md          # Component-Implementierung
│   ├── backend.md                  # API-Patterns, Error Handling
│   └── data-engineer.md            # Migration-Safety, RLS
├── pipeline/
│   └── run.sh              # VPS/CI Pipeline Runner
├── settings.json           # Template .claude/settings.json
└── templates/
    ├── project.json        # Template für Projektkonfiguration
    └── CLAUDE.md           # Template für Projektinstruktionen
```

### Zielprojekt (nach Setup)

```
your-project/
├── CLAUDE.md               # Projektspezifische Instruktionen (anpassen!)
├── project.json            # Konfiguration: Notion-IDs, Build-Commands, Pfade
├── .claude/
│   ├── agents/             # Agent-Definitionen (vom Framework, auto-updated)
│   ├── commands/           # Slash-Commands (vom Framework, auto-updated)
│   ├── skills/             # Skills (Framework-Skills + eigene Custom-Skills)
│   │   ├── brainstorming.md        # ← vom Framework (wird bei --update aktualisiert)
│   │   ├── backend.md              # ← vom Framework
│   │   ├── mein-custom-skill.md    # ← projektspezifisch (wird NIE angefasst)
│   │   └── ...
│   ├── settings.json       # Permissions (vom Framework)
│   └── .pipeline-version   # Installierte Framework-Version
└── .pipeline/
    └── run.sh              # Pipeline Runner (vom Framework)
```

## Konfiguration

### project.json

Zentrale Konfigurationsdatei. Alle Agents und Commands lesen hieraus.

| Feld | Zweck |
|------|-------|
| `name` | Projektname (kebab-case) |
| `stack` | Tech-Stack (Framework, DB, etc.) |
| `build.web` | Build-Command |
| `build.test` | Test-Command |
| `paths` | Wichtige Verzeichnisse |
| `notion.tasks_db` | Database ID (32 hex chars aus der Notion-URL) |
| `notion.project_filter` | Projektname (exakter Match gegen Projekt-Relation) |
| `conventions` | Branch-Prefix, Commit-Format |

Die **Data Source URL** wird zur Laufzeit automatisch aufgelöst — sie steht nicht in der Config. Claude resolved sie beim ersten Notion-Zugriff via `notion-fetch` auf die DB und cached sie für die Session.

### CLAUDE.md

Projektspezifische Instruktionen die Agents als Kontext nutzen:
- Architektur und Verzeichnisstruktur
- Code-Konventionen und Import-Muster
- Sicherheitsanforderungen
- Domain-spezifisches Wissen

## Workflow

```
/ticket
  ├── Phase 1: Orchestrator liest betroffene Dateien (5-10)
  ├── Phase 2: Agents parallel (data-engineer, backend, frontend)
  ├── Phase 3: Build-Check (Bash)
  ├── Phase 4: Review (QA-Agent, ggf. Security-Agent)
  └── Phase 5: /ship (Commit → PR → Notion "Ready to review") ← STOPP

User reviewed PR → "passt" / /merge
  └── /merge (Squash Merge → Delete Branch → Notion "Done")
```

## VPS/CI Ausführung

```bash
.pipeline/run.sh <TICKET_ID> <TICKET_TITLE> [DESCRIPTION] [LABELS]
# → claude --agent orchestrator --dangerously-skip-permissions
```

Der Pipeline-Runner gibt am Ende JSON für n8n aus:

```json
{
  "status": "completed",
  "ticket_id": "T--162",
  "branch": "feature/T--162-kurzbeschreibung",
  "project": "my-project"
}
```

## Kosten

- ~2-5€ pro Ticket (Anthropic API)
- Haiku für Routine (DB, Build, Review)
- Sonnet für Kreatives (UI, Logic)
- Opus für den Orchestrator
