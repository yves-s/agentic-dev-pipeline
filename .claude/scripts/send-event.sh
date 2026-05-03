#!/bin/bash
# send-event.sh — Send pipeline event to Dev Board
# Usage: bash .claude/scripts/send-event.sh <ticket_number> <agent_type> <event_type> [metadata_json]
#
# Credential resolution (project-local only):
#   1. JSP_BOARD_API_KEY / JSP_BOARD_API_URL from process env
#   2. PIPELINE_KEY / BOARD_API_URL aliases (legacy)
#   3. CLAUDE_USER_CONFIG_BOARD_API_KEY / _URL (plugin)
#   4. .env.local in the project directory
#   5. project.json → pipeline.board_url (URL only)
#
# Silent fail — never blocks the pipeline.

TICKET_NUMBER="$1"
AGENT_TYPE="$2"
EVENT_TYPE="$3"
METADATA="${4:-{}}"

[ -z "$TICKET_NUMBER" ] || [ -z "$AGENT_TYPE" ] || [ -z "$EVENT_TYPE" ] && exit 0

# --- Resolve credentials ---
: "${PIPELINE_KEY:=${JSP_BOARD_API_KEY:-}}"
: "${BOARD_API_URL:=${JSP_BOARD_API_URL:-}}"
: "${PIPELINE_KEY:=${CLAUDE_USER_CONFIG_BOARD_API_KEY:-}}"
: "${BOARD_API_URL:=${CLAUDE_USER_CONFIG_BOARD_API_URL:-}}"

API_KEY="${PIPELINE_KEY:-}"
API_URL="${BOARD_API_URL:-}"

if [ -z "$API_KEY" ] || [ -z "$API_URL" ]; then
  if [ -f ".env.local" ]; then
    local_key=$(grep '^JSP_BOARD_API_KEY=' .env.local 2>/dev/null | cut -d= -f2- || true)
    local_url=$(grep '^JSP_BOARD_API_URL=' .env.local 2>/dev/null | cut -d= -f2- || true)
    : "${API_KEY:=${local_key:-}}"
    : "${API_URL:=${local_url:-}}"
  fi
fi

if [ -z "$API_URL" ] && [ -f "project.json" ]; then
  API_URL=$(node -e "
    try { const p = require('./project.json'); process.stdout.write(p.pipeline?.board_url || ''); }
    catch(e) { process.stdout.write(''); }
  " 2>/dev/null) || API_URL=""
fi

[ -z "$API_URL" ] || [ -z "$API_KEY" ] && exit 0

# Build JSON payload safely via env vars (prevents shell injection)
PAYLOAD=$(JS_TN="$TICKET_NUMBER" JS_AT="$AGENT_TYPE" JS_ET="$EVENT_TYPE" JS_MD="$METADATA" node -e "
  const obj = { ticket_number: Number(process.env.JS_TN), agent_type: process.env.JS_AT, event_type: process.env.JS_ET };
  try { obj.metadata = JSON.parse(process.env.JS_MD); } catch { obj.metadata = {}; }
  process.stdout.write(JSON.stringify(obj));
" 2>/dev/null || true)

[ -z "$PAYLOAD" ] && exit 0

curl -s --max-time 3 -X POST "${API_URL}/api/events" \
  -H "Content-Type: application/json" \
  -H "X-Pipeline-Key: ${API_KEY}" \
  -d "$PAYLOAD" \
  >/dev/null 2>&1
