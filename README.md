# Agentic Dev Pipeline

A portable multi-agent system for autonomous software development with Claude Code.

## What is this?

A framework of generic agents, commands, and a pipeline runner that can be installed into any project. It provides:

- **7 specialized agents** (Orchestrator, Backend, Frontend, Data-Engineer, DevOps, QA, Security)
- **5 slash-commands** (`/ticket`, `/ship`, `/merge`, `/setup-pipeline`, `/update-pipeline`)
- **Pipeline runner** for VPS/CI execution
- **Supabase integration** for ticket management
- **Update mechanism** with version tracking and dry-run preview

## Quick Start

```bash
# 1. Clone the framework (once)
git clone https://github.com/yves-s/agentic-dev-pipeline.git ~/agentic-dev-pipeline

# 2. Switch to your project
cd /path/to/your/project

# 3. Run setup (interactive)
~/agentic-dev-pipeline/setup.sh

# 4. Open in Claude Code and run /setup-pipeline
#    (auto-detects stack, fills project.json, connects Dev Board)
claude
> /setup-pipeline

# 5. Start working
> /ticket
```

## Setup & Update

### First Installation

```bash
cd /path/to/your/project
/path/to/agentic-dev-pipeline/setup.sh
```

Interactive wizard: asks for project name, package manager, build commands, and Supabase config. Creates all necessary files.

### Update

Improved agents, skills, or commands? Push them to every project:

```bash
cd /path/to/your/project
/path/to/agentic-dev-pipeline/setup.sh --update
```

> **Tip:** Save the path as an alias for convenience:
> ```bash
> # ~/.zshrc or ~/.bashrc
> alias pipeline-update='/path/to/agentic-dev-pipeline/setup.sh --update'
> ```
> Then just run `cd my-project && pipeline-update`.

Updates **only framework files** and never touches project-specific files:

| Updated | Never overwritten |
|---------|-------------------|
| `.claude/agents/*` | `CLAUDE.md` |
| `.claude/commands/*` | `project.json` |
| `.claude/skills/<framework-skill>.md` | `.claude/skills/<your-custom-skill>.md` |
| `.claude/scripts/*` | |
| `.claude/settings.json` | |
| `.pipeline/run.sh` | |

Framework skills are added/updated. Custom skills in `.claude/skills/` that are not part of the framework are never touched.

If templates (CLAUDE.md structure, workflow tables) have changed, the script will prompt you to run `/update-pipeline` in Claude Code. This intelligently merges template changes into your project files without overwriting your customizations.

### Dry Run

Preview what would change before updating:

```bash
cd /path/to/your/project
/path/to/agentic-dev-pipeline/setup.sh --update --dry-run
```

Shows which files would be added, changed, or removed — without making any changes.

### Version Tracking

Each installation writes the framework version to `.claude/.pipeline-version`. On update you'll see:

```
Installed: abc1234 (2026-02-28)
Available: def5678 (2026-03-02)
```

## Structure

### Framework (this repo)

```
agentic-dev-pipeline/
├── setup.sh                # Install + update script
├── agents/                 # Generic agent definitions
│   ├── orchestrator.md     # Plans, delegates, ships
│   ├── backend.md          # API, hooks, business logic
│   ├── frontend.md         # UI components (design-aware)
│   ├── data-engineer.md    # DB migrations, RLS, types
│   ├── devops.md           # Build checks, fixes
│   ├── qa.md               # AC verification, tests, security
│   └── security.md         # Security review
├── commands/               # Slash-commands
│   ├── ticket.md           # Ticket → autonomous workflow → PR
│   ├── ship.md             # Commit + push + PR
│   ├── merge.md            # Squash merge after approval
│   ├── setup-pipeline.md   # Project config + Dev Board setup
│   └── update-pipeline.md  # Sync CLAUDE.md + project.json after update
├── skills/                 # Framework skills (auto-deployed)
│   ├── brainstorming.md
│   ├── writing-plans.md
│   ├── executing-plans.md
│   ├── subagent-driven-development.md
│   ├── dispatching-parallel-agents.md
│   ├── test-driven-development.md
│   ├── systematic-debugging.md
│   ├── verification-before-completion.md
│   ├── finishing-a-development-branch.md
│   ├── requesting-code-review.md
│   ├── receiving-code-review.md
│   ├── using-git-worktrees.md
│   ├── design.md
│   ├── frontend-design.md
│   ├── creative-design.md
│   ├── webapp-testing.md
│   ├── backend.md
│   └── data-engineer.md
├── scripts/                # Utility scripts (used by skills)
│   └── with_server.py      # Server lifecycle for Playwright tests
├── pipeline/
│   └── run.sh              # VPS/CI pipeline runner
├── migrations/
│   └── 001_create_tables.sql  # Supabase schema
├── settings.json           # Template for .claude/settings.json
└── templates/
    ├── project.json        # Project configuration template
    └── CLAUDE.md           # Project instructions template
```

### Target project (after setup)

```
your-project/
├── CLAUDE.md               # Project-specific instructions (customize this!)
├── project.json            # Config: Supabase IDs, build commands, paths
├── .claude/
│   ├── agents/             # Agent definitions (from framework, auto-updated)
│   ├── commands/           # Slash-commands (from framework, auto-updated)
│   ├── skills/             # Skills (framework + your custom skills)
│   │   ├── brainstorming.md        # ← from framework (updated with --update)
│   │   ├── backend.md              # ← from framework
│   │   ├── my-custom-skill.md      # ← project-specific (never touched)
│   │   └── ...
│   ├── scripts/
│   │   └── with_server.py
│   ├── settings.json       # Permissions (from framework)
│   └── .pipeline-version   # Installed framework version
└── .pipeline/
    └── run.sh              # Pipeline runner (from framework)
```

## Configuration

### project.json

Central configuration file. All agents and commands read from this.

| Field | Purpose |
|-------|---------|
| `name` | Project name (kebab-case) |
| `stack` | Tech stack (framework, DB, etc.) |
| `build.web` | Build command |
| `build.test` | Test command |
| `paths` | Key directories |
| `supabase.project_id` | Supabase project ID |
| `supabase.tasks_table` | Table name for tickets |
| `conventions` | Branch prefix, commit format |

### CLAUDE.md

Project-specific instructions used by agents as context:
- Architecture and directory structure
- Code conventions and import patterns
- Security requirements
- Domain-specific knowledge

## Workflow

```
/ticket
  ├── Phase 1: Orchestrator reads affected files (5–10)
  ├── Phase 2: Agents in parallel (data-engineer, backend, frontend)
  ├── Phase 3: Build check (Bash)
  ├── Phase 4: Review (QA agent, optionally Security agent)
  └── Phase 5: /ship (commit → PR → ticket marked "Ready to review") ← STOP

User reviews PR → "looks good" / /merge
  └── /merge (squash merge → delete branch → ticket marked "Done")
```

## VPS/CI Execution

```bash
.pipeline/run.sh <TICKET_ID> <TICKET_TITLE> [DESCRIPTION] [LABELS]
# → claude --agent orchestrator --dangerously-skip-permissions
```

The pipeline runner outputs JSON at the end (for n8n or other automation):

```json
{
  "status": "completed",
  "ticket_id": "T-162",
  "branch": "feature/T-162-short-description",
  "project": "my-project"
}
```

## Cost

- ~€2–5 per ticket (Anthropic API)
- Haiku for routine tasks (DB, build, review)
- Sonnet for creative work (UI, logic)
- Opus for the orchestrator

## License

MIT — see [LICENSE](LICENSE)
