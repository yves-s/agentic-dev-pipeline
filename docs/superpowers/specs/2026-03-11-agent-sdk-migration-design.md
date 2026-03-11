# Agent SDK Migration — Design Spec

## Goal

Replace the shell-based pipeline orchestration (`run.sh`, `worker.sh`, `send-event.sh`, `devboard-hook.sh`) with a TypeScript service built on `@anthropic-ai/claude-agent-sdk`. This enables native event streaming to the Dev Board and parallel agent execution while keeping the orchestrator's natural-language intelligence intact.

## Approach: Hybrid (Ansatz C)

The SDK handles infrastructure (agent spawning, lifecycle hooks, streaming). The orchestrator and sub-agent definitions remain in Markdown files — natural language, editable, versionable.

## SDK API Surface

The `@anthropic-ai/claude-agent-sdk` (npm) exposes a `query()` function that spawns an autonomous agent session. Key imports and types:

```typescript
import {
  query,
  type Options,
  type Query,
  type AgentDefinition,
  type SDKMessage,
  type HookCallback,
  type PreToolUseHookInput,
  type PostToolUseHookInput,
} from "@anthropic-ai/claude-agent-sdk";
```

### How query() works

```typescript
const q = query({
  prompt: "Implement ticket #42",
  options: {
    cwd: "/path/to/project",
    model: "opus",
    permissionMode: "bypassPermissions",
    allowedTools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Agent"],
    agents: { /* AgentDefinition map */ },
    hooks: { /* HookEvent → HookCallbackMatcher[] */ },
    maxTurns: 200,
  }
});

for await (const message of q) {
  // message.type: "system" | "assistant" | "tool_call" | "tool_result" | "result" | "error"
}
```

### How sub-agents work with the SDK

The SDK pre-registers agents via the `agents` option. The orchestrator LLM then **autonomously decides** to use the `Agent` tool to spawn them at runtime — exactly as it uses the `Task` tool today. The `agents` map makes them available; the orchestrator's natural-language prompt controls when and how to use them.

This means:
- The orchestrator still plans autonomously (Phase 1)
- The orchestrator still decides which agents to spawn and in what order (Phase 2)
- The SDK hooks fire when the `Agent` tool is invoked (SubagentStart) and when it completes (SubagentStop)
- Parallel spawning works because the orchestrator can invoke multiple `Agent` tool calls in a single response

The `Task` tool reference in `orchestrator.md` will be updated to `Agent` (the SDK's equivalent).

## Architecture

### File Structure

```
pipeline/
  run.ts              # Main entry point (replaces run.sh)
  worker.ts           # Supabase polling worker (replaces vps/worker.sh)
  lib/
    load-agents.ts    # Reads agents/*.md → AgentDefinition[]
    event-hooks.ts    # SDK hooks → POST /api/events (Dev Board)
    config.ts         # Reads project.json + CLI args
  package.json        # @anthropic-ai/claude-agent-sdk, tsx
  tsconfig.json
```

**Framework source:** `pipeline/` in the framework repo.
**Installed to:** `.pipeline/` in target projects (via `setup.sh`, same as today).

### Execution Flow

```
run.ts
  1. Read project.json (config, supabase, pipeline)
  2. Create feature branch (git checkout -b feature/{ticket-id}-{slug})
  3. Load agents/*.md as AgentDefinition objects
  4. Create event hooks (SubagentStart, PostToolUse, SubagentStop)
  5. Call query() with orchestrator prompt + agents + hooks
  6. Stream events live to Dev Board
  7. Return JSON output (status, branch, ticket_id)
```

### Invocation

```bash
# Local (same UX as before)
npx tsx .pipeline/run.ts <TICKET_ID> <TITLE> [DESCRIPTION] [LABELS]

# VPS (worker polls Supabase)
npx tsx .pipeline/worker.ts
```

A thin `run.sh` wrapper (3 lines) provides backwards-compatible invocation:
```bash
#!/bin/sh
exec npx tsx "$(dirname "$0")/run.ts" "$@"
```

## Agent Definition Loading

### Source: `agents/*.md`

Agent Markdown files remain the single source of truth. An optional YAML frontmatter block specifies model and description:

```markdown
---
model: sonnet
description: Frontend specialist for UI components and pages
---
# Frontend Agent
Du bist ein Frontend-Experte...
```

If no frontmatter is present, `load-agents.ts` falls back to a default mapping table.

### Model Assignment

Model is determined by the orchestrator prompt at spawn time (same as today). The orchestrator explicitly sets the model when invoking each agent via the Agent tool (e.g., `model: "haiku"` for data-engineer).

The current agent `.md` files have `model: inherit` or `model: opus` in their frontmatter — these values are metadata for the framework, not direct SDK config. The orchestrator's prompt (Phase 2 table) is the authoritative source for which model each agent uses:

| Agent         | Model  | Rationale                    |
|---------------|--------|------------------------------|
| orchestrator  | opus   | Autonomous planning (set in query() call) |
| frontend      | sonnet | Creative UI work (set by orchestrator) |
| backend       | sonnet | Business logic (set by orchestrator) |
| data-engineer | haiku  | Schema migrations (set by orchestrator) |
| qa            | haiku  | Checklist verification (set by orchestrator) |
| security      | haiku  | Security review (set by orchestrator) |
| devops        | haiku  | Build fixes (set by orchestrator) |

### Runtime Mapping

```typescript
// agents/frontend.md → AgentDefinition
{
  "frontend": {
    description: "Frontend specialist for UI components and pages",
    prompt: "<content of agents/frontend.md>",
    tools: ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
    // model is NOT set here — the orchestrator controls it at spawn time
  }
}
```

## Event Streaming via SDK Hooks

Replaces `send-event.sh` (44 lines) and `devboard-hook.sh` (68 lines) entirely.

### Hook Registration

```typescript
query({
  prompt: orchestratorPrompt,
  options: {
    agents: loadedAgents,
    hooks: {
      SubagentStart: [{ matcher: ".*", hooks: [onAgentStarted] }],
      SubagentStop:  [{ matcher: ".*", hooks: [onAgentCompleted] }],
      PostToolUse:   [{ matcher: "Write|Edit", hooks: [onFileChanged] }],
    }
  }
})
```

### Event Mapping

Payloads match the existing Dev Board API contract (with `metadata` wrapper):

| SDK Hook        | Dev Board Event   | Payload                                                              |
|-----------------|-------------------|----------------------------------------------------------------------|
| SubagentStart   | agent_started     | `{ ticket_number, agent_type, event_type: "agent_started" }`        |
| SubagentStop    | agent_completed   | `{ ticket_number, agent_type, event_type: "completed" }`            |
| PostToolUse     | tool_use          | `{ ticket_number, agent_type, event_type: "tool_use", metadata: { tool_name, file_path } }` |

The `metadata` object wraps tool-specific details, matching the format that `devboard-hook.sh` currently sends and that the Dev Board's `/api/events` route expects.

### Implementation Pattern

```typescript
async function postEvent(apiUrl: string, apiKey: string, payload: Event) {
  await fetch(`${apiUrl}/api/events`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Pipeline-Key": apiKey
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(3000), // 3s timeout, matches current curl --max-time 3
  });
}
```

- **Fire-and-forget**: Hooks set `async: true` — pipeline does not wait for Dev Board
- **Silent fail**: If Dev Board is unreachable, pipeline continues (same behavior as today)
- **Error event**: On unhandled pipeline errors, a `pipeline_failed` event is posted to the Dev Board (new event type, not currently supported but gracefully ignored by the API)

### Files Modified (not removed)

These files need updates to remove manual event posting, since the SDK hooks handle it automatically:

| File                     | Change                                                              |
|--------------------------|---------------------------------------------------------------------|
| `agents/orchestrator.md` | Remove `bash .pipeline/send-event.sh` lines from Phase 2. Replace `Task` tool reference with `Agent`. |
| `commands/develop.md`    | Remove `bash .pipeline/send-event.sh` calls from Steps 3a, 5. The `/develop` command will invoke `run.ts` instead of the orchestrator directly. |
| `settings.json`          | Remove the `hooks.PostToolUse` entry that calls `devboard-hook.sh`. SDK hooks replace this. |

## Worker & VPS Integration

`worker.ts` replaces `vps/worker.sh` (279 lines Shell → ~120 lines TypeScript).

### Required Environment Variables

Identical to current `worker.sh`:

| Variable               | Required | Description                          |
|------------------------|----------|--------------------------------------|
| `ANTHROPIC_API_KEY`    | Yes      | Claude API key                       |
| `GH_TOKEN`             | Yes      | GitHub Personal Access Token         |
| `SUPABASE_URL`         | Yes      | `https://{id}.supabase.co`           |
| `SUPABASE_SERVICE_KEY` | Yes      | Supabase service_role key            |
| `SUPABASE_PROJECT_ID`  | Yes      | UUID from project_id column          |
| `PROJECT_DIR`          | Yes      | Absolute path to cloned project      |
| `POLL_INTERVAL`        | No       | Seconds between polls (default: 60)  |
| `LOG_DIR`              | No       | Log directory (default: ~/pipeline-logs) |
| `MAX_FAILURES`         | No       | Max consecutive failures (default: 5) |

All required vars are validated at startup. Missing vars cause an immediate exit with a clear error message.

### Polling Loop

```typescript
while (running) {
  // 1. Connectivity check (like current worker.sh line 189)
  if (!await checkSupabaseConnectivity()) {
    log("WARN: Supabase not reachable, waiting...");
    await sleep(POLL_INTERVAL);
    continue;
  }

  // 2. Find next ticket
  const ticket = await getNextTicket();
  if (!ticket) {
    await sleep(POLL_INTERVAL);
    continue;
  }

  // 3. Atomic claim (pipeline_status IS NULL guard)
  const claimed = await claimTicket(ticket.number);
  if (!claimed) {
    log(`Ticket T--${ticket.number} claimed by another worker. Skip.`);
    await sleep(5000);
    continue;
  }

  // 4. Run pipeline
  try {
    await runPipeline(ticket);
    consecutiveFailures = 0;
  } catch (error) {
    consecutiveFailures++;
    await failTicket(ticket.number, `Pipeline error: ${error.message}`);

    if (consecutiveFailures >= MAX_FAILURES) {
      log(`CRITICAL: ${MAX_FAILURES} consecutive failures. Worker stopping.`);
      process.exit(1);
    }

    // 5-minute cooldown after failure (like current worker.sh line 273)
    await sleep(300_000);
  }
}
```

### Ticket Lifecycle (unchanged)

```
Claim:    pipeline_status = 'running', status = 'in_progress'
Success:  → run.ts creates PR via /ship → status = 'in_review'
Failure:  pipeline_status = 'failed', status = 'ready_to_develop' + summary with failure reason
```

### Error Handling (replicates all worker.sh behaviors)

- **Connectivity check**: Before each poll, verify Supabase is reachable (like line 189 of current worker.sh)
- **Atomic claiming**: Uses `pipeline_status=is.null` guard to prevent race conditions between workers
- **Consecutive failures**: Stop after MAX_FAILURES (default: 5) with clear log message
- **5-minute cooldown**: After pipeline failure, wait 300s before next attempt
- **Failure reason**: Written to ticket `summary` field for debugging
- **Last 10 lines**: On failure, log the last 10 lines of pipeline output
- **Logging**: All output to `~/pipeline-logs/T--{N}-{timestamp}.log`
- **Graceful shutdown**: SIGINT/SIGTERM caught, waits for running pipeline to finish before exit
- **Cancellation**: Uses `AbortController` to cancel the `query()` call on shutdown signal

### VPS Setup Changes

`vps/setup-vps.sh` stays mostly the same (Node.js 20 already installed). The systemd service `ExecStart` changes:

```bash
# Old:
ExecStart=/home/claude-dev/%i/.pipeline/worker.sh

# New:
ExecStart=/usr/bin/npx tsx /home/claude-dev/%i/.pipeline/worker.ts
```

**Note on VPS detection:** The current `run.sh` contains VPS detection logic (if running as root with a `claude-dev` user, switch user via `su`). This is no longer needed because the systemd service already runs as `User=claude-dev`. The `run.ts` does not include this logic.

## Setup & Installation

### `setup.sh` Changes

```bash
# Existing (stays):
copy_files agents/ commands/ skills/ settings.json

# New (after file copy):
if [ -f ".pipeline/package.json" ]; then
  echo "Installing pipeline dependencies..."
  cd .pipeline && npm install --production && cd ..
fi
```

### Prerequisites

- Node.js 20+ (already required for Dev Board / VPS)
- Claude Code CLI (SDK uses it under the hood)
- `ANTHROPIC_API_KEY` environment variable

### No Build Step

No `tsc` compilation needed. `tsx` (TypeScript Execute) runs `.ts` files directly. Both `tsx` and `@anthropic-ai/claude-agent-sdk` are listed as **production dependencies** (`dependencies`, not `devDependencies`) in `package.json`, so `npm install --production` installs them correctly.

### `--update` Flow

```bash
setup.sh --update
# 1. Copy new pipeline/*.ts files
# 2. Run npm install in .pipeline/ directory
# 3. Done
```

## Files Removed

| File                              | Lines | Replaced By          |
|-----------------------------------|-------|----------------------|
| `pipeline/send-event.sh`         | 44    | SDK hooks            |
| `.claude/scripts/devboard-hook.sh`| 68    | SDK hooks            |
| `vps/worker.sh`                   | 279   | `pipeline/worker.ts` |

**Note on `pipeline/run.sh`:** The old shell script is replaced by `pipeline/run.ts`. A thin 3-line `run.sh` wrapper stays as a shim for backwards compatibility (`exec npx tsx run.ts "$@"`). This ensures the systemd service and any external scripts referencing `run.sh` continue to work.

**Cleanup in `setup.sh --update`:** The update path must also remove `send-event.sh` from `.pipeline/` and `devboard-hook.sh` from `.claude/scripts/` in target projects, since these files were previously installed by `setup.sh`.

## Rollout Plan

### Stage 1 — Orchestrator + 1 Agent + Hooks

- `run.ts` with orchestrator query + backend agent only
- Event hooks posting to Dev Board
- **Test**: Dummy ticket, verify events appear in Dev Board

### Stage 2 — All Agents + Parallelism

- Load remaining agents (frontend, data-engineer, qa, security, devops)
- Adjust orchestrator prompt for explicit parallel spawning
- **Test**: Real ticket with frontend + backend work, verify parallel execution

### Stage 3 — Worker + VPS

- Implement `worker.ts` (Supabase polling)
- Update systemd service
- **Test**: Set ticket to `ready_to_develop`, worker claims and executes

### Test Criteria (each stage)

1. Feature branch created correctly
2. Agents spawned and working
3. Events appear in Dev Board (agent_started, tool_use, completed)
4. PR created via `/ship`
5. JSON output correct (status, branch, ticket_id)

### Rollback

Old `run.sh` remains in git history. If the PoC fails → `git revert` restores the previous state.
