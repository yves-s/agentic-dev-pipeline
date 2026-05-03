#!/bin/bash
# post-comment.sh — Post a comment to a Board ticket
# Usage: bash .claude/scripts/post-comment.sh <ticket_number> "body" [type]
# Types: triage, preview, qa (enables dedup on re-runs)
#
# Credential resolution (project-local only):
#   1. JSP_BOARD_API_KEY / JSP_BOARD_API_URL from process env
#   2. PIPELINE_KEY / BOARD_API_URL aliases (legacy)
#   3. CLAUDE_USER_CONFIG_BOARD_API_KEY / _URL (plugin)
#   4. .env.local in the project directory
#   5. project.json → pipeline.board_url (URL only)
#
# Silent fail — never blocks the pipeline. Always exits 0.

set -euo pipefail
trap 'exit 0' ERR

TICKET_NUMBER="${1:-}"
BODY="${2:-${COMMENT_BODY:-}}"
TYPE="${3:-}"

[ -z "$TICKET_NUMBER" ] || [ -z "$BODY" ] && exit 0

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

# Build JSON payload using env vars (no shell interpolation into JS to avoid injection)
PAYLOAD=$(COMMENT_BODY="$BODY" COMMENT_TYPE="$TYPE" node -e "
  const obj = { body: process.env.COMMENT_BODY, author: 'pipeline' };
  if (process.env.COMMENT_TYPE) obj.type = process.env.COMMENT_TYPE;
  process.stdout.write(JSON.stringify(obj));
" 2>/dev/null || true)

[ -z "$PAYLOAD" ] && exit 0

curl -s --max-time 3 -X POST "${API_URL}/api/tickets/${TICKET_NUMBER}/comments" \
  -H "Content-Type: application/json" \
  -H "X-Pipeline-Key: ${API_KEY}" \
  -d "$PAYLOAD" \
  >/dev/null 2>&1 || true

exit 0
