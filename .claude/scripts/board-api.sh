#!/bin/bash
# board-api.sh — Secure wrapper for Board API calls
#
# SECURITY: This script hides API credentials from Claude Code terminal output.
# Credentials are resolved internally and never printed to stdout/stderr.
# Only the API response body is returned.
#
# Usage:
#   board-api.sh get tickets/{N}
#   board-api.sh get "tickets?status=ready_to_develop&project={UUID}"
#   board-api.sh patch tickets/{N} '{"status": "in_progress"}'
#   board-api.sh post tickets '{"title": "...", "body": "..."}'
#
# Default project_id (POST tickets only):
#   When the body has no `project_id`, the script auto-injects
#   project.json → pipeline.project_id so workspace-scoped keys still target
#   the correct project. Pass an explicit `project_id` in the body to override
#   the default; pass `"project_id": null` for cross-project epics.
#
# Credential resolution (project-local, in order):
#   Tier 1: JSP_BOARD_API_KEY / JSP_BOARD_API_URL from process env
#   Tier 2: PIPELINE_KEY / BOARD_API_URL from process env (legacy aliases)
#   Tier 3: CLAUDE_USER_CONFIG_BOARD_API_* (plugin userConfig)
#   Tier 4: .env.local in the current directory
#   Tier 5: project.json → pipeline.board_url (URL only — never the key)
#
# The legacy ~/.just-ship/config.json fallback was removed in T-1043.
# Configuration is 100% project-local — secrets in .env.local (gitignored),
# IDs in project.json (committed). If credentials are missing here, run
# /connect-board to set them up.
#
# Exit codes:
#   0 — Success (response body on stdout)
#   1 — Configuration error (missing credentials)
#   2 — API error (curl failed, non-2xx response)

set -euo pipefail

# Suppress all debug output — only API response goes to stdout
exec 3>&2  # Save original stderr
exec 2>/dev/null  # Suppress stderr during credential resolution

METHOD="${1:-}"
ENDPOINT="${2:-}"
BODY="${3:-}"

if [ -z "$METHOD" ] || [ -z "$ENDPOINT" ]; then
  exec 2>&3  # Restore stderr for error message
  echo "Usage: board-api.sh <get|post|patch|delete> <endpoint> [body]" >&2
  exit 1
fi

# Uppercase method
METHOD=$(echo "$METHOD" | tr '[:lower:]' '[:upper:]')

# --- Resolve credentials (silently) ---

# Tier 1+2: Process env. Accept JSP_BOARD_API_KEY / _URL (canonical) or
# PIPELINE_KEY / BOARD_API_URL (legacy aliases used by older scripts).
: "${PIPELINE_KEY:=${JSP_BOARD_API_KEY:-}}"
: "${BOARD_API_URL:=${JSP_BOARD_API_URL:-}}"

# Tier 3: Plugin userConfig env vars
: "${PIPELINE_KEY:=${CLAUDE_USER_CONFIG_BOARD_API_KEY:-}}"
: "${BOARD_API_URL:=${CLAUDE_USER_CONFIG_BOARD_API_URL:-}}"

# Tier 4: .env.local in the current project directory
if [ -z "${PIPELINE_KEY:-}" ] || [ -z "${BOARD_API_URL:-}" ]; then
  if [ -f ".env.local" ]; then
    local_key=$(grep '^JSP_BOARD_API_KEY=' .env.local 2>/dev/null | cut -d= -f2- || true)
    local_url=$(grep '^JSP_BOARD_API_URL=' .env.local 2>/dev/null | cut -d= -f2- || true)
    : "${PIPELINE_KEY:=${local_key:-}}"
    : "${BOARD_API_URL:=${local_url:-}}"
  fi
fi

# Tier 5: project.json → pipeline.board_url (URL only; never a key source)
if [ -z "${BOARD_API_URL:-}" ] && [ -f "project.json" ]; then
  BOARD_API_URL=$(node -e "
    try { const p = require('./project.json'); process.stdout.write(p.pipeline?.board_url || ''); }
    catch(e) { process.stdout.write(''); }
  " 2>/dev/null) || BOARD_API_URL=""
fi

if [ -z "${PIPELINE_KEY:-}" ]; then
  exec 2>&3
  echo '{"error": "missing_api_key", "message": "Missing JSP_BOARD_API_KEY in .env.local — run /connect-board to set up."}' >&2
  exit 1
fi

if [ -z "${BOARD_API_URL:-}" ]; then
  exec 2>&3
  echo '{"error": "missing_board_url", "message": "Missing JSP_BOARD_API_URL — set it in .env.local or pipeline.board_url in project.json."}' >&2
  exit 1
fi

exec 2>&3  # Restore stderr for curl errors

# --- Default project_id injection (POST tickets only) ---
# When the body for `POST tickets` does not carry an explicit `project_id`,
# fall back to project.json → pipeline.project_id so workspace-scoped keys
# still land tickets in the correct project. An explicit `project_id` in the
# body — including `null` (cross-project epics) — is always passed through.
if [ "$METHOD" = "POST" ] && [ "$ENDPOINT" = "tickets" ] && [ -n "$BODY" ]; then
  BODY=$(node -e "
    let body;
    try { body = JSON.parse(process.argv[1]); } catch(e) { process.stdout.write(process.argv[1]); process.exit(0); }
    if (body && typeof body === 'object' && !Array.isArray(body) && !Object.prototype.hasOwnProperty.call(body, 'project_id')) {
      let defaultPid = '';
      try { defaultPid = require('./project.json').pipeline?.project_id || ''; } catch(e) {}
      if (defaultPid) body.project_id = defaultPid;
    }
    process.stdout.write(JSON.stringify(body));
  " "$BODY" 2>/dev/null) || true
fi

# --- Make API call ---
# Build curl command (key is in variable, not visible in ps output when using --header)
CURL_ARGS=(
  -s
  --max-time 30
  -X "$METHOD"
  -H "X-Pipeline-Key: $PIPELINE_KEY"
  -H "Content-Type: application/json"
)

if [ -n "$BODY" ]; then
  CURL_ARGS+=(-d "$BODY")
fi

# Execute curl and capture both response and HTTP code
RESPONSE_FILE=$(mktemp)
HTTP_CODE=$(curl "${CURL_ARGS[@]}" -o "$RESPONSE_FILE" -w "%{http_code}" "${BOARD_API_URL}/api/${ENDPOINT}" 2>/dev/null) || HTTP_CODE="000"

RESPONSE=$(cat "$RESPONSE_FILE")
rm -f "$RESPONSE_FILE"

# Check HTTP status
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  # Success — output response body only
  echo "$RESPONSE"
  exit 0
elif [ "$HTTP_CODE" = "000" ]; then
  echo '{"error": "connection_failed", "message": "Could not connect to Board API"}' >&2
  exit 2
else
  # API error — output error response to stderr, return non-zero
  echo "$RESPONSE" >&2
  exit 2
fi
