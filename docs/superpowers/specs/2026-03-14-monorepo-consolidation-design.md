# Monorepo Consolidation: Pipeline + Board + Telegram Bot

**Date:** 2026-03-14
**Status:** Draft
**Scope:** Merge `agentic-dev-board` and `agentic-dev-telegram-bot` into `agentic-dev-pipeline` as a single monorepo.

---

## Motivation

Three separate repos (`agentic-dev-pipeline`, `agentic-dev-board`, `agentic-dev-telegram-bot`) share the same Supabase DB, duplicate the pipeline SDK, and require separate maintenance. For open source, a single `git clone` should give users the complete experience: framework, dashboard, and Telegram-based ticket intake.

### Goals

- **One repo, one clone** — Complete experience without pulling three repos
- **Less maintenance** — One issue tracker, one CI, one place for changes
- **Better local DX** — `npm install && npm run dev` starts everything
- **Simplicity** — Minimal tooling, no over-engineering

### Non-Goals

- Shared type packages at this stage (extract later when real need arises)
- Changes to `setup.sh` behavior (still copies only framework files into target projects)
- Changing how target projects consume the pipeline SDK (still a copy via `.pipeline/`)

---

## Architecture

### Monorepo Structure

```
agentic-dev-pipeline/
├── agents/                    # Agent definitions (unchanged)
├── commands/                  # Slash commands (unchanged)
├── skills/                    # Pipeline skills (unchanged)
├── pipeline/                  # SDK Runner — npm workspace "pipeline"
│   ├── package.json
│   ├── run.ts
│   ├── worker.ts
│   ├── server.ts
│   └── lib/
├── apps/
│   ├── board/                 # Next.js Dashboard — npm workspace "board"
│   │   ├── package.json
│   │   ├── src/
│   │   ├── next.config.ts
│   │   └── ...
│   └── bot/                   # Telegram Bot — npm workspace "bot"
│       ├── package.json
│       ├── bot.ts
│       ├── lib/
│       └── ...
├── templates/                 # CLAUDE.md + project.json templates
├── vps/                       # VPS infrastructure (systemd services)
│   ├── setup-vps.sh
│   ├── agentic-dev-pipeline@.service
│   ├── agentic-dev-bot.service
│   └── README.md
├── docs/
├── scripts/
├── setup.sh                   # Copies only framework files (unchanged)
├── package.json               # Root: npm workspaces config
├── CLAUDE.md
└── README.md
```

### npm Workspaces

Root `package.json`:

```json
{
  "name": "agentic-dev-pipeline",
  "private": true,
  "workspaces": [
    "pipeline",
    "apps/*"
  ],
  "scripts": {
    "dev:board": "npm run dev -w board",
    "dev:bot": "npm run dev -w bot",
    "dev": "npm run dev:board & npm run dev:bot",
    "build:board": "npm run build -w board",
    "start:bot": "npm run start -w bot",
    "lint": "npm run lint -w board"
  }
}
```

One `npm install` at root installs all dependencies. Shared deps (e.g., `@supabase/supabase-js`, `tsx`) are hoisted to root `node_modules/`.

### What changes, what doesn't

| Element | Changes? | Details |
|---|---|---|
| `agents/`, `commands/`, `skills/` | No | Stay at root |
| `pipeline/` | Minimal | Stays at root, becomes npm workspace |
| `setup.sh` | No | Still copies from root-level paths |
| `vps/` | Slightly | Bot systemd service added |
| Board code | Move only | `agentic-dev-board/*` → `apps/board/` |
| Bot code | Move only | `agentic-dev-telegram-bot/*` → `apps/bot/` |
| `.pipeline/` in Board + Bot | Removed | Both import directly from `../../pipeline` |
| `.claude/` in Board + Bot | Removed | Root `.claude/` config applies to all |

---

## Migration Strategy

### Git History Preservation

Use `git subtree add` to bring in full commit history from both repos:

1. `git subtree add --prefix=apps/board <board-remote> main`
2. `git subtree add --prefix=apps/bot <bot-remote> main`

All commits preserved, `git blame` works.

### Migration Steps

1. **Add Board:** `git subtree add --prefix=apps/board` from board remote
2. **Add Bot:** `git subtree add --prefix=apps/bot` from bot remote
3. **Clean Board:** Remove `apps/board/.pipeline/`, `apps/board/.claude/`
4. **Clean Bot:** Remove `apps/bot/.pipeline/`, `apps/bot/.claude/`, move `apps/bot/telegram-bot.service` to `vps/agentic-dev-bot.service`
5. **Create root `package.json`** with workspaces config and scripts
6. **Run `npm install`** at root to verify workspace resolution
7. **Reconfigure Vercel:** Set root directory to `apps/board`
8. **Update VPS:** Update systemd service paths, `git pull`, restart services
9. **Archive old repos:** Set to read-only with pointer to monorepo

---

## Deployment

### Board — Vercel

Vercel project settings:
- **Root Directory:** `apps/board`
- **Build Command:** `npm run build` (Vercel detects Next.js)
- **Install Command:** `npm install` (runs at monorepo root, Vercel supports npm workspaces)

Environment variables, domain (`app.agentic-dev.xyz`), preview deploys — all unchanged.

### Bot + Pipeline Worker — VPS

Both are long-running polling processes, deployed as systemd services:

```
vps/
├── agentic-dev-pipeline@.service    # Pipeline worker (path unchanged)
├── agentic-dev-bot.service          # Telegram bot (new path: apps/bot/)
└── setup-vps.sh                     # VPS initialization
```

Bot service working directory change:
- Before: `/home/claude-dev/agentic-dev-telegram-bot`
- After: `/home/claude-dev/agentic-dev-pipeline/apps/bot`

### Deployment Flow

```
git push origin main
    │
    ├──→ Vercel: builds apps/board automatically
    │
    └──→ VPS: git pull + systemctl restart
         ├── agentic-dev-bot.service
         └── agentic-dev-pipeline@{slug}.service
```

---

## Shared Code Strategy

### Current Duplication

Board and Bot share:
- Supabase client creation
- TypeScript types (`Ticket`, `Workspace`, `Project`, `TaskEvent`)
- Constants (status values, priorities, agent types)

### Decision: No `packages/shared` at start

Reasons:
- Board uses `@supabase/ssr` (SSR), Bot uses `@supabase/supabase-js` directly — different client patterns
- Types are similar but not identical (Board has UI-specific fields, Bot has Telegram-specific)
- A shared package adds build complexity (TypeScript compilation, exports config)

The `packages/` directory structure is prepared. Extract shared code when real duplication proves painful after migration — not before.

---

## Local Developer Experience

### Quick Start

```bash
git clone <repo>
npm install
cp apps/board/.env.example apps/board/.env.local
cp apps/bot/.env.example apps/bot/.env
npm run dev
```

### Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Starts Board + Bot in parallel |
| `npm run dev:board` | Board only (Next.js dev server) |
| `npm run dev:bot` | Bot only (tsx --watch) |
| `npm run build:board` | Production build for Board |
| `npm run start:bot` | Production start for Bot |
| `npm run lint` | Lint Board |

### Board Local

Two modes:
1. **Against hosted Supabase** — Same DB as production, only UI runs locally
2. **Against local Supabase** — `supabase start` for fully isolated setup (for contributors without production access)

### Bot Local

Requires per-developer credentials:
- Telegram Bot Token (via @BotFather)
- Anthropic API Key
- OpenAI API Key (Whisper)

`.env.example` documents all required variables.

---

## Impact on `setup.sh` and Target Projects

### `setup.sh` — No changes

Copies from root-level paths that don't change:
- `agents/` → `.claude/agents/`
- `commands/` → `.claude/commands/`
- `skills/` → `.claude/skills/`
- `pipeline/` → `.pipeline/`

Board and Bot under `apps/` are ignored.

### Existing Target Projects

Projects with the framework already installed (Aime, Aime Web, etc.) are unaffected. Their next `setup.sh --update` pulls from the same paths.

### `.pipeline/` in Target Projects

Target projects still receive a **copy** of the pipeline SDK to `.pipeline/`. They don't import from the monorepo — that would create a dependency on the monorepo being present locally.

Board and Bot within the monorepo import directly from `../../pipeline` — no more duplicated SDK code for internal apps.

---

## Open Questions

None — all decisions made during design discussion.

---

## Summary of Decisions

1. **Approach B** — `apps/board`, `apps/bot`, framework stays at root
2. **npm Workspaces** — one `npm install`, shared dependency hoisting
3. **Git Subtree** — preserve full history from both repos
4. **No shared package** at start — extract when real need arises
5. **Deployment split:** Board on Vercel (`apps/board`), Bot + Worker on VPS
6. **`setup.sh` unchanged** — copies only framework files into target projects
7. **Board:** hosted (Vercel) + local-capable for self-hosting
8. **Bot:** fully integrated feature, not optional plugin
