#!/bin/bash
# =============================================================================
# worker.sh — Agentic Dev Pipeline Queue Worker
#
# Läuft als claude-dev User (24/7 via systemd).
# Pollt Supabase nach ready_to_develop Tickets und startet die Pipeline.
#
# Required env vars (in /home/claude-dev/.env.{project-slug}):
#   ANTHROPIC_API_KEY      Claude API Key
#   GH_TOKEN               GitHub Personal Access Token
#   SUPABASE_URL           https://{id}.supabase.co
#   SUPABASE_SERVICE_KEY   Supabase service_role key
#   SUPABASE_PROJECT_ID    UUID aus project_id Spalte in tickets
#   PROJECT_DIR            Absoluter Pfad zum geklonten Projekt
#
# Optional env vars:
#   POLL_INTERVAL          Sekunden zwischen Polls (default: 60)
#   LOG_DIR                Log-Verzeichnis (default: ~/pipeline-logs)
#   MAX_FAILURES           Max. Fehler in Folge bevor Worker stoppt (default: 5)
# =============================================================================

set -euo pipefail

# ── Konfiguration ─────────────────────────────────────────────────────────────

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY muss gesetzt sein}"
: "${GH_TOKEN:?GH_TOKEN muss gesetzt sein}"
: "${SUPABASE_URL:?SUPABASE_URL muss gesetzt sein}"
: "${SUPABASE_SERVICE_KEY:?SUPABASE_SERVICE_KEY muss gesetzt sein}"
: "${SUPABASE_PROJECT_ID:?SUPABASE_PROJECT_ID muss gesetzt sein}"
: "${PROJECT_DIR:?PROJECT_DIR muss gesetzt sein}"

POLL_INTERVAL="${POLL_INTERVAL:-60}"
LOG_DIR="${LOG_DIR:-${HOME}/pipeline-logs}"
MAX_FAILURES="${MAX_FAILURES:-5}"

mkdir -p "$LOG_DIR"

# ── Logging ───────────────────────────────────────────────────────────────────

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_file() {
  local ticket_number="$1"
  echo "${LOG_DIR}/T--${ticket_number}-$(date +%Y%m%d-%H%M%S).log"
}

# ── Supabase REST Helpers ─────────────────────────────────────────────────────

# Führt eine GROQ-Query via Supabase REST API aus
# $1 = Endpoint-Pfad (z.B. /rest/v1/tickets)
# $2 = Query-String (z.B. ?status=eq.ready_to_develop&...)
supabase_get() {
  local path="$1"
  local query="${2:-}"
  curl -sf \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "Accept: application/json" \
    "${SUPABASE_URL}${path}${query}"
}

# PATCH-Request an Supabase
# $1 = Pfad + Query (z.B. /rest/v1/tickets?number=eq.42)
# $2 = JSON-Body (z.B. {"pipeline_status":"running"})
supabase_patch() {
  local path_query="$1"
  local body="$2"
  curl -sf \
    -X PATCH \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    -d "$body" \
    "${SUPABASE_URL}${path_query}"
}

# ── Ticket-Funktionen ─────────────────────────────────────────────────────────

# Holt das nächste ready_to_develop Ticket (höchste Prio, ältestes zuerst)
get_next_ticket() {
  supabase_get "/rest/v1/tickets" \
    "?status=eq.ready_to_develop&project_id=eq.${SUPABASE_PROJECT_ID}&pipeline_status=is.null&order=priority.asc,created_at.asc&limit=1&select=number,title,body,priority,tags"
}

# Markiert Ticket als "wird gerade verarbeitet"
claim_ticket() {
  local number="$1"
  supabase_patch \
    "/rest/v1/tickets?number=eq.${number}&pipeline_status=is.null" \
    '{"pipeline_status":"running","status":"in_progress"}'
}

# Setzt pipeline_status auf 'failed' und status zurück auf 'ready_to_develop'
fail_ticket() {
  local number="$1"
  local reason="$2"
  supabase_patch \
    "/rest/v1/tickets?number=eq.${number}" \
    "{\"pipeline_status\":\"failed\",\"status\":\"ready_to_develop\",\"summary\":$(echo "$reason" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}"
}

# ── Pipeline ausführen ────────────────────────────────────────────────────────

run_pipeline() {
  local number="$1"
  local title="$2"
  local body="$3"
  local tags="$4"
  local logfile
  logfile=$(log_file "$number")

  log "Starte Pipeline: T--${number} — ${title}"
  log "Log: $logfile"

  # Tags als kommaseparierter String
  local labels
  labels=$(echo "$tags" | python3 -c "
import json, sys
tags = json.loads(sys.stdin.read() or '[]')
print(','.join(tags) if isinstance(tags, list) else '')
" 2>/dev/null || echo "")

  # Sicherstellen, dass das Projekt aktuell ist
  if ! cd "$PROJECT_DIR" 2>/dev/null; then
    log "ERROR: PROJECT_DIR nicht erreichbar: $PROJECT_DIR"
    return 1
  fi

  # Pipeline runner ermitteln
  local runner="${PROJECT_DIR}/.pipeline/run.sh"
  if [ ! -x "$runner" ]; then
    log "ERROR: Pipeline runner nicht gefunden: $runner"
    log "Tipp: setup.sh im Projekt-Dir ausführen"
    return 1
  fi

  # Env für Claude Code
  export ANTHROPIC_API_KEY
  export GH_TOKEN
  export GITHUB_TOKEN="$GH_TOKEN"

  # Pipeline starten (blockierend, Output in Logfile)
  local exit_code=0
  "$runner" \
    "$number" \
    "$title" \
    "$body" \
    "$labels" \
    >> "$logfile" 2>&1 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    log "Pipeline abgeschlossen: T--${number}"
    # JSON-Output der letzten Pipeline-Zeile loggen
    tail -1 "$logfile" | python3 -c "
import json, sys
line = sys.stdin.read().strip()
try:
    data = json.loads(line)
    print(f'  Status: {data.get(\"status\")}, Branch: {data.get(\"branch\", \"?\")}')
except:
    pass
" 2>/dev/null || true
    return 0
  else
    log "Pipeline fehlgeschlagen: T--${number} (exit $exit_code)"
    log "Letzten 10 Zeilen des Logs:"
    tail -10 "$logfile" | while IFS= read -r line; do log "  $line"; done
    return "$exit_code"
  fi
}

# ── Haupt-Loop ────────────────────────────────────────────────────────────────

log "=========================================="
log "  Agentic Dev Pipeline Worker gestartet"
log "  Projekt: $(basename "$PROJECT_DIR")"
log "  Supabase-Project: $SUPABASE_PROJECT_ID"
log "  Poll-Interval: ${POLL_INTERVAL}s"
log "=========================================="

consecutive_failures=0

while true; do
  # Connectivity-Check
  if ! curl -sf "${SUPABASE_URL}/rest/v1/" \
    -H "apikey: ${SUPABASE_SERVICE_KEY}" > /dev/null 2>&1; then
    log "WARN: Supabase nicht erreichbar, warte ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Nächstes Ticket holen
  raw_tickets=$(get_next_ticket 2>/dev/null || echo "[]")

  # Prüfen ob Tickets vorhanden
  ticket_count=$(echo "$raw_tickets" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read() or '[]')
print(len(data) if isinstance(data, list) else 0)
" 2>/dev/null || echo "0")

  if [ "$ticket_count" -eq 0 ]; then
    log "Keine Tickets in der Queue. Warte ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  # Ticket-Daten extrahieren
  ticket_number=$(echo "$raw_tickets" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data[0]['number'])
" 2>/dev/null)

  ticket_title=$(echo "$raw_tickets" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data[0]['title'])
" 2>/dev/null)

  ticket_body=$(echo "$raw_tickets" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data[0].get('body') or '')
" 2>/dev/null)

  ticket_tags=$(echo "$raw_tickets" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(json.dumps(data[0].get('tags') or []))
" 2>/dev/null || echo "[]")

  log "Ticket gefunden: T--${ticket_number} — ${ticket_title}"

  # Ticket atomar claimen (nur wenn pipeline_status IS NULL)
  claimed=$(claim_ticket "$ticket_number" 2>/dev/null || echo "[]")
  claimed_count=$(echo "$claimed" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read() or '[]')
print(len(data) if isinstance(data, list) else 0)
" 2>/dev/null || echo "0")

  if [ "$claimed_count" -eq 0 ]; then
    log "Ticket T--${ticket_number} wurde von anderem Worker geclaimt. Skip."
    sleep 5
    continue
  fi

  log "Ticket T--${ticket_number} geclaimt."

  # Pipeline starten
  if run_pipeline "$ticket_number" "$ticket_title" "$ticket_body" "$ticket_tags"; then
    consecutive_failures=0
  else
    consecutive_failures=$((consecutive_failures + 1))
    log "Pipeline fehlgeschlagen ($consecutive_failures/$MAX_FAILURES consecutive failures)"

    # Ticket zurücksetzen
    fail_ticket "$ticket_number" "Pipeline-Fehler (exit code != 0). Bitte manuell prüfen." || true

    if [ "$consecutive_failures" -ge "$MAX_FAILURES" ]; then
      log "KRITISCH: ${MAX_FAILURES} aufeinanderfolgende Fehler. Worker stoppt."
      log "Bitte Logs prüfen: $LOG_DIR"
      exit 1
    fi

    # Längere Pause nach Fehler
    log "Warte 5 Minuten nach Fehler..."
    sleep 300
    continue
  fi

  # Kurze Pause zwischen Tickets
  sleep 5
done
