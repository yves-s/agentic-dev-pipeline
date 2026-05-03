#!/bin/bash
# scripts/write-config.sh — Project-local config I/O for Just Ship
#
# Manages two project-local files:
#   .env.local    (gitignored)  Holds JSP_BOARD_API_KEY + JSP_BOARD_API_URL
#                               and any other secrets the project needs
#                               (COOLIFY_API_TOKEN, SHOPIFY_CLI_THEME_TOKEN, …)
#   project.json  (committed)   Holds pipeline.workspace_id + pipeline.project_id
#                               + pipeline.board_url — never any secrets
#
# The legacy global path ~/.just-ship/config.json is gone. All commands are
# project-scoped now.
#
# Commands:
#   set-project     Write workspace_id + project_id to project.json
#   set-key         Upsert a key=value pair into .env.local (default key:
#                   JSP_BOARD_API_KEY, but any --name can be passed)
#   parse-jsp       Decode and validate a jsp_ connection token
#   connect         End-to-end: parse token → write .env.local → write project.json
#                   → verify connection
#
# SECURITY: All node -e invocations pass values via environment variables
# to prevent shell injection. No bash variables are interpolated into JS.
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Upsert one or more KEY=VALUE pairs into .env.local. Existing keys with the
# same name are removed first so the file does not accumulate stale entries.
# All values are written as raw strings (no quoting) — callers are responsible
# for ensuring values do not contain newlines.
#
# Usage: write_env_kv <envfile> <key1> <value1> [<key2> <value2> ...]
write_env_kv() {
  local envfile="$1"
  shift

  if [ -f "$envfile" ]; then
    # Build a grep -v chain dynamically — one per key being written
    local tmpfile
    tmpfile=$(mktemp)
    cp "$envfile" "$tmpfile"
    local i=1
    while [ $i -le $# ]; do
      local key
      eval "key=\${$i}"
      local tmp2
      tmp2=$(mktemp)
      grep -v "^${key}=" "$tmpfile" > "$tmp2" || true
      mv "$tmp2" "$tmpfile"
      i=$((i + 2))
    done
    mv "$tmpfile" "$envfile"
  else
    : > "$envfile"
  fi

  # Append the new pairs
  while [ $# -ge 2 ]; do
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "$envfile"
    shift 2
  done

  chmod 600 "$envfile"
}

# Convenience wrapper for the most common case: writing the Board credentials.
# Adds a marker comment so users (and migration scripts) can identify the
# Just Ship-managed lines.
write_env_local() {
  local envfile="$1"
  local api_key="$2"
  local board_url="$3"

  # Strip the marker comment if it exists so we don't duplicate it.
  if [ -f "$envfile" ]; then
    local tmpfile
    tmpfile=$(mktemp)
    grep -v '^# Just Ship Board Credentials' "$envfile" > "$tmpfile" || true
    mv "$tmpfile" "$envfile"
  fi

  write_env_kv "$envfile" \
    JSP_BOARD_API_KEY "$api_key" \
    JSP_BOARD_API_URL "$board_url"

  # Append the marker as the last line of the credentials block.
  echo "# Just Ship Board Credentials (managed by write-config.sh)" >> "$envfile"
  chmod 600 "$envfile"
}

usage() {
  cat <<'USAGE'
Usage: write-config.sh <command> [options]

Commands:
  set-project     Write workspace_id + project_id to project.json
    --workspace-id  Workspace UUID (required)
    --project-id    Project UUID (required)
    --project-dir   Directory containing project.json (default: ".")

  set-key         Upsert a KEY=VALUE pair into .env.local
    --name          Variable name (default: JSP_BOARD_API_KEY)
    --value         Variable value (required)
    --project-dir   Directory containing .env.local (default: ".")

  parse-jsp       Decode and validate a jsp_ connection string
    --token         The jsp_ token string (required)

  connect         Connect workspace using a jsp_ token (parse + save + verify)
    --token         The jsp_ token string (required)
    --project-dir   Directory containing project.json (default: ".")
    --plugin-mode   Plugin mode: output JSON result (for /connect-board)

USAGE
  exit 1
}

# ---------------------------------------------------------------------------
# Command: set-project
# ---------------------------------------------------------------------------

cmd_set_project() {
  local workspace_id="" project_id="" project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace-id) workspace_id="$2"; shift 2 ;;
      --project-id)   project_id="$2"; shift 2 ;;
      --project-dir)  project_dir="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for set-project"; exit 1 ;;
    esac
  done

  if [ -z "$workspace_id" ] || [ -z "$project_id" ]; then
    echo "Error: set-project requires --workspace-id and --project-id"
    exit 1
  fi

  local pjson="${project_dir}/project.json"
  if [ ! -f "$pjson" ]; then
    echo "Error: project.json not found at ${pjson}"
    exit 1
  fi

  JS_PJSON="$pjson" \
  JS_WORKSPACE_ID="$workspace_id" \
  JS_PROJECT_ID="$project_id" \
  node -e "
    const fs = require('fs');
    const pjsonPath = process.env.JS_PJSON;
    const workspaceId = process.env.JS_WORKSPACE_ID;
    const projectId = process.env.JS_PROJECT_ID;

    const pj = JSON.parse(fs.readFileSync(pjsonPath, 'utf-8'));

    // Remove old fields (legacy formats)
    if (pj.pipeline) {
      delete pj.pipeline.api_key;
      delete pj.pipeline.api_url;
      delete pj.pipeline.workspace;
      delete pj.pipeline.workspace_slug;
      delete pj.pipeline.project_name;
    }

    if (!pj.pipeline) {
      pj.pipeline = {};
    }

    pj.pipeline.workspace_id = workspaceId;
    pj.pipeline.project_id = projectId;

    fs.writeFileSync(pjsonPath, JSON.stringify(pj, null, 2) + '\n');
  "

  echo "project.json updated: workspace_id='${workspace_id}', project_id='${project_id}'"
}

# ---------------------------------------------------------------------------
# Command: set-key
# ---------------------------------------------------------------------------

cmd_set_key() {
  local name="JSP_BOARD_API_KEY" value="" project_dir="."

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)        name="$2"; shift 2 ;;
      --value)       value="$2"; shift 2 ;;
      --project-dir) project_dir="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for set-key"; exit 1 ;;
    esac
  done

  if [ -z "$value" ]; then
    echo "Error: set-key requires --value"
    exit 1
  fi

  if ! [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Error: --name must be a valid env variable name (letters, digits, underscore; cannot start with digit)"
    exit 1
  fi

  local envfile="${project_dir}/.env.local"
  write_env_kv "$envfile" "$name" "$value"
  echo "${name} written to ${envfile}"
}

# ---------------------------------------------------------------------------
# Command: parse-jsp
# ---------------------------------------------------------------------------

cmd_parse_jsp() {
  local token=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      *) echo "Error: Unknown option '$1' for parse-jsp"; exit 1 ;;
    esac
  done

  if [ -z "$token" ]; then
    echo "Error: parse-jsp requires --token"
    exit 1
  fi

  JS_TOKEN="$token" JS_BOARD_URL_HINT="${JSP_BOARD_URL:-https://board.just-ship.io}" \
  node -e "
    const crypto = require('crypto');
    const https = require('https');
    const http = require('http');
    const token = process.env.JS_TOKEN;

    if (!token.startsWith('jsp_')) {
      console.error('Error: Token must start with jsp_');
      process.exit(1);
    }
    const b64 = token.slice(4);

    function validate(json) {
      if (!json.v || typeof json.v !== 'number') throw new Error('Missing or invalid version field (v)');
      const required = { b: 'Board URL', w: 'Workspace Slug', i: 'Workspace ID', k: 'API Key' };
      for (const [key, label] of Object.entries(required)) {
        if (!json[key] || typeof json[key] !== 'string') throw new Error('Missing or invalid field: ' + label + ' (' + key + ')');
      }
      if (!json.k.startsWith('adp_')) throw new Error('API Key must start with adp_');
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$/i;
      if (!uuidRegex.test(json.i)) throw new Error('Workspace ID is not a valid UUID');
      return json;
    }

    function output(json) {
      try { validate(json); } catch (e) { console.error('Error: ' + e.message); process.exit(1); }
      const out = { board_url: json.b, workspace: json.w, workspace_id: json.i, api_key: json.k, version: json.v };
      if (json.p && typeof json.p === 'string') out.project_id = json.p;
      console.log(JSON.stringify(out, null, 2));
    }

    // Path 1: try plain JSON (legacy unencrypted tokens)
    try { output(JSON.parse(Buffer.from(b64, 'base64').toString('utf-8'))); process.exit(0); } catch (_) {}

    // Path 2: try local decryption if key available
    const encKey = process.env.JSP_ENCRYPTION_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (encKey) {
      try {
        const buf = Buffer.from(b64, 'base64url');
        const iv = buf.subarray(0, 12);
        const authTag = buf.subarray(12, 28);
        const ciphertext = buf.subarray(28);
        const derivedKey = crypto.createHash('sha256').update(encKey).digest();
        const decipher = crypto.createDecipheriv('aes-256-gcm', derivedKey, iv);
        decipher.setAuthTag(authTag);
        const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf-8');
        output(JSON.parse(decrypted));
        process.exit(0);
      } catch (_) {}
    }

    // Path 3: server-side token redemption via Board API
    const boardUrl = process.env.JS_BOARD_URL_HINT;
    const url = new URL(boardUrl + '/api/connect/redeem');
    const mod = url.protocol === 'https:' ? https : http;
    const postData = JSON.stringify({ token: token });
    const req = mod.request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) },
      timeout: 15000,
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        if (res.statusCode !== 200) {
          console.error('Error: Board returned HTTP ' + res.statusCode + ' — ' + body.slice(0, 200));
          process.exit(1);
        }
        try {
          const data = JSON.parse(body);
          if (data.error) { console.error('Error: ' + (data.message || data.error)); process.exit(1); }
          output(data);
        } catch (e) { console.error('Error: Invalid response from Board API'); process.exit(1); }
      });
    });
    req.on('error', (e) => {
      console.error('Error: Could not reach Board at ' + boardUrl + ' — ' + e.message);
      console.error('Check your internet connection or set JSP_ENCRYPTION_KEY to decrypt locally.');
      process.exit(1);
    });
    req.on('timeout', () => { req.destroy(); console.error('Error: Board API timed out'); process.exit(1); });
    req.write(postData);
    req.end();
  "
}

# ---------------------------------------------------------------------------
# Command: connect
# ---------------------------------------------------------------------------

cmd_connect() {
  local token="" project_dir="." plugin_mode="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      --project-dir) project_dir="$2"; shift 2 ;;
      --plugin-mode) plugin_mode="true"; shift ;;
      *) echo "Error: Unknown option '$1' for connect"; exit 1 ;;
    esac
  done

  if [ -z "$token" ]; then
    echo "Error: connect requires --token"
    echo ""
    echo "Usage: write-config.sh connect --token \"jsp_...\""
    echo ""
    echo "Get your connection code from the Board: Settings → Connect"
    exit 1
  fi

  # Step 1: Parse the jsp_ token (v2 and v3)
  # Strategy: try plain base64 → try local decryption → try server-side redemption
  local parsed
  parsed=$(JS_TOKEN="$token" JS_BOARD_URL_HINT="${JSP_BOARD_URL:-https://board.just-ship.io}" node -e "
    const crypto = require('crypto');
    const https = require('https');
    const http = require('http');
    const token = process.env.JS_TOKEN;
    if (!token.startsWith('jsp_')) {
      console.error('Error: Token must start with jsp_');
      process.exit(1);
    }
    const b64 = token.slice(4);

    function validate(json) {
      const required = { v: 'number', b: 'string', w: 'string', i: 'string', k: 'string' };
      for (const [key, type] of Object.entries(required)) {
        if (typeof json[key] !== type) {
          throw new Error('Invalid token — missing or wrong type for field: ' + key);
        }
      }
      if (!json.k.startsWith('adp_')) {
        throw new Error('Invalid API Key in token (must start with adp_)');
      }
      const out = { b: json.b.trim(), w: json.w.trim(), i: json.i.trim(), k: json.k.trim(), v: json.v };
      if (json.p && typeof json.p === 'string') out.p = json.p.trim();
      return out;
    }

    function output(json) {
      try {
        console.log(JSON.stringify(validate(json)));
      } catch (e) {
        console.error('Error: ' + e.message);
        process.exit(1);
      }
    }

    // Path 1: try plain JSON (legacy unencrypted tokens)
    try {
      const plain = Buffer.from(b64, 'base64').toString('utf-8');
      const json = JSON.parse(plain);
      output(json);
      process.exit(0);
    } catch (_) {}

    // Path 2: try local decryption if key available
    const encKey = process.env.JSP_ENCRYPTION_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (encKey) {
      try {
        const buf = Buffer.from(b64, 'base64url');
        const iv = buf.subarray(0, 12);
        const authTag = buf.subarray(12, 28);
        const ciphertext = buf.subarray(28);
        const derivedKey = crypto.createHash('sha256').update(encKey).digest();
        const decipher = crypto.createDecipheriv('aes-256-gcm', derivedKey, iv);
        decipher.setAuthTag(authTag);
        const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf-8');
        output(JSON.parse(decrypted));
        process.exit(0);
      } catch (_) {}
    }

    // Path 3: server-side token redemption via Board API
    const boardUrl = process.env.JS_BOARD_URL_HINT;
    const url = new URL(boardUrl + '/api/connect/redeem');
    const mod = url.protocol === 'https:' ? https : http;
    const postData = JSON.stringify({ token: token });
    const req = mod.request(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(postData) },
      timeout: 15000,
    }, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        if (res.statusCode !== 200) {
          console.error('Error: Board returned HTTP ' + res.statusCode + ' — ' + body.slice(0, 200));
          process.exit(1);
        }
        try {
          const data = JSON.parse(body);
          if (data.error) {
            console.error('Error: ' + (data.message || data.error));
            process.exit(1);
          }
          output(data);
        } catch (e) {
          console.error('Error: Invalid response from Board API');
          process.exit(1);
        }
      });
    });
    req.on('error', (e) => {
      console.error('Error: Could not reach Board at ' + boardUrl + ' — ' + e.message);
      console.error('Check your internet connection or set JSP_ENCRYPTION_KEY to decrypt locally.');
      process.exit(1);
    });
    req.on('timeout', () => {
      req.destroy();
      console.error('Error: Board API timed out at ' + boardUrl);
      process.exit(1);
    });
    req.write(postData);
    req.end();
  ") || exit 1

  local board workspace workspace_id key token_version project_id_from_token
  board=$(JS_PARSED="$parsed" node -e "process.stdout.write(JSON.parse(process.env.JS_PARSED).b)")
  workspace=$(JS_PARSED="$parsed" node -e "process.stdout.write(JSON.parse(process.env.JS_PARSED).w)")
  workspace_id=$(JS_PARSED="$parsed" node -e "process.stdout.write(JSON.parse(process.env.JS_PARSED).i)")
  key=$(JS_PARSED="$parsed" node -e "process.stdout.write(JSON.parse(process.env.JS_PARSED).k)")
  token_version=$(JS_PARSED="$parsed" node -e "process.stdout.write(String(JSON.parse(process.env.JS_PARSED).v))")
  project_id_from_token=$(JS_PARSED="$parsed" node -e "
    const d = JSON.parse(process.env.JS_PARSED);
    process.stdout.write(d.p || '');
  ")

  # Step 2: Write credentials to .env.local (project-local, gitignored)
  local envfile="${project_dir}/.env.local"
  write_env_local "$envfile" "$key" "$board"

  # Step 3: Update project.json with workspace_id + board_url + (project_id if v3)
  local pjson="${project_dir}/project.json"
  if [ -f "$pjson" ]; then
    JS_PJSON="$pjson" \
    JS_WORKSPACE_ID="$workspace_id" \
    JS_PROJECT_ID="${project_id_from_token:-}" \
    JS_BOARD_URL="$board" \
    node -e "
      const fs = require('fs');
      const pj = JSON.parse(fs.readFileSync(process.env.JS_PJSON, 'utf-8'));
      if (!pj.pipeline) pj.pipeline = {};
      pj.pipeline.workspace_id = process.env.JS_WORKSPACE_ID;
      if (process.env.JS_PROJECT_ID) {
        pj.pipeline.project_id = process.env.JS_PROJECT_ID;
      }
      if (process.env.JS_BOARD_URL) {
        pj.pipeline.board_url = process.env.JS_BOARD_URL;
      }
      // Strip legacy format fields if they happen to be present
      delete pj.pipeline.api_key;
      delete pj.pipeline.api_url;
      delete pj.pipeline.workspace;
      delete pj.pipeline.workspace_slug;
      delete pj.pipeline.project_name;
      fs.writeFileSync(process.env.JS_PJSON, JSON.stringify(pj, null, 2) + '\n');
    "
  fi

  # -------------------------------------------------------------------------
  # Plugin mode: emit JSON result and exit (consumed by /connect-board)
  # -------------------------------------------------------------------------
  if [ "$plugin_mode" = "true" ]; then
    local http_code response_body verified="false" verify_error=""
    response_body=$(mktemp)
    trap "rm -f '$response_body'" EXIT
    http_code=$(curl -s -o "$response_body" -w "%{http_code}" \
      -H "X-Pipeline-Key: ${key}" "${board}/api/projects" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
      verified="true"
    elif [ "$http_code" = "401" ]; then
      verify_error="invalid_api_key"
    else
      verify_error="board_unreachable"
    fi

    rm -f "$response_body"

    JS_WORKSPACE_ID="$workspace_id" \
    JS_WORKSPACE_SLUG="$workspace" \
    JS_PROJECT_ID="${project_id_from_token:-}" \
    JS_BOARD_URL="$board" \
    JS_API_KEY="$key" \
    JS_VERSION="$token_version" \
    JS_VERIFIED="$verified" \
    JS_VERIFY_ERROR="${verify_error:-}" \
    node -e "
      const result = {
        success: true,
        workspace_id: process.env.JS_WORKSPACE_ID,
        workspace_slug: process.env.JS_WORKSPACE_SLUG,
        board_url: process.env.JS_BOARD_URL,
        api_key: process.env.JS_API_KEY,
        version: parseInt(process.env.JS_VERSION, 10),
        verified: process.env.JS_VERIFIED === 'true',
      };
      if (process.env.JS_PROJECT_ID) {
        result.project_id = process.env.JS_PROJECT_ID;
      }
      if (process.env.JS_VERIFY_ERROR) {
        result.verify_error = process.env.JS_VERIFY_ERROR;
      }
      console.log(JSON.stringify(result, null, 2));
    "

    return 0
  fi

  # -------------------------------------------------------------------------
  # Standard mode: interactive feedback + project linking
  # -------------------------------------------------------------------------

  # v3 token: project_id already in token — link directly, skip project picker
  if [ -n "$project_id_from_token" ] && [ -f "$pjson" ]; then
    cmd_set_project --workspace-id "$workspace_id" --project-id "$project_id_from_token" --project-dir "$project_dir" > /dev/null
    echo ""
    echo "✓ Credentials in .env.local gespeichert"
    echo "✓ Workspace '${workspace}' verbunden"
    echo "✓ Projekt verknüpft (via Token)"
    local http_code response_body
    response_body=$(mktemp)
    trap "rm -f '$response_body'" EXIT
    http_code=$(curl -s -o "$response_body" -w "%{http_code}" \
      -H "X-Pipeline-Key: ${key}" "${board}/api/projects" 2>/dev/null || echo "000")
    rm -f "$response_body"
    if [ "$http_code" = "200" ]; then
      echo "✓ Board-Verbindung verifiziert"
    elif [ "$http_code" = "401" ]; then
      echo "⚠ API-Key wurde abgelehnt (HTTP 401) — prüfe Board → Settings → API Keys"
    fi
    echo ""
    echo "Erstelle dein erstes Ticket mit /ticket in Claude Code."
    return 0
  fi

  # v2 token path: validate connection, list projects, pick one
  local http_code response_body
  response_body=$(mktemp)
  trap "rm -f '$response_body'" EXIT
  http_code=$(curl -s -o "$response_body" -w "%{http_code}" \
    -H "X-Pipeline-Key: ${key}" "${board}/api/projects" 2>/dev/null || echo "000")

  if [ "$http_code" = "200" ]; then
    if [ ! -f "$pjson" ]; then
      echo ""
      echo "✓ Credentials in .env.local gespeichert"
      echo "✓ Workspace '${workspace}' verbunden"
      echo ""
      echo "Workspace verbunden. Führe 'just-ship connect' in deinem"
      echo "Projektverzeichnis erneut aus um ein Projekt zu verknüpfen."
      rm -f "$response_body"
      return 0
    fi

    local project_count selected_id selected_name
    project_count=$(JS_BODY="$(cat "$response_body")" node -e "
      try {
        const data = JSON.parse(process.env.JS_BODY);
        const projects = data.data && data.data.projects ? data.data.projects : [];
        process.stdout.write(String(projects.length));
      } catch (e) {
        process.stdout.write('0');
      }
    ") || project_count="0"

    if [ "$project_count" = "0" ]; then
      echo ""
      echo "✓ Credentials in .env.local gespeichert"
      echo "✓ Workspace '${workspace}' verbunden"
      echo ""
      echo "⚠ Kein Projekt im Board gefunden."
      echo "  Erstelle ein Projekt im Board unter Settings → Projects,"
      echo "  dann führe 'just-ship connect' erneut aus."
    elif [ "$project_count" = "1" ]; then
      selected_id=$(JS_BODY="$(cat "$response_body")" node -e "
        const data = JSON.parse(process.env.JS_BODY);
        process.stdout.write(data.data.projects[0].id);
      ")
      selected_name=$(JS_BODY="$(cat "$response_body")" node -e "
        const data = JSON.parse(process.env.JS_BODY);
        process.stdout.write(data.data.projects[0].name);
      ")
      cmd_set_project --workspace-id "$workspace_id" --project-id "$selected_id" --project-dir "$project_dir" > /dev/null
      echo ""
      echo "✓ Credentials in .env.local gespeichert"
      echo "✓ Workspace '${workspace}' verbunden"
      echo "✓ Projekt '${selected_name}' verknüpft"
      echo "✓ Board-Verbindung verifiziert"
      echo ""
      echo "Erstelle dein erstes Ticket mit /ticket in Claude Code."
    else
      echo ""
      echo "✓ Credentials in .env.local gespeichert"
      echo "✓ Workspace '${workspace}' verbunden"
      echo ""
      echo "Mehrere Projekte gefunden:"
      echo ""
      JS_BODY="$(cat "$response_body")" node -e "
        const data = JSON.parse(process.env.JS_BODY);
        data.data.projects.forEach((p, i) => {
          console.log('  ' + (i + 1) + ') ' + p.name);
        });
      "
      echo ""
      local choice
      read -p "Projekt auswählen (Nummer): " choice

      local valid_choice
      valid_choice=$(JS_BODY="$(cat "$response_body")" JS_CHOICE="$choice" node -e "
        const data = JSON.parse(process.env.JS_BODY);
        const idx = parseInt(process.env.JS_CHOICE, 10) - 1;
        if (isNaN(idx) || idx < 0 || idx >= data.data.projects.length) {
          process.stdout.write('invalid');
        } else {
          process.stdout.write('valid');
        }
      ")

      if [ "$valid_choice" != "valid" ]; then
        echo ""
        echo "⚠ Ungültige Auswahl. Führe 'just-ship connect' erneut aus."
        rm -f "$response_body"
        return 1
      fi

      selected_id=$(JS_BODY="$(cat "$response_body")" JS_CHOICE="$choice" node -e "
        const data = JSON.parse(process.env.JS_BODY);
        const idx = parseInt(process.env.JS_CHOICE, 10) - 1;
        process.stdout.write(data.data.projects[idx].id);
      ")
      selected_name=$(JS_BODY="$(cat "$response_body")" JS_CHOICE="$choice" node -e "
        const data = JSON.parse(process.env.JS_BODY);
        const idx = parseInt(process.env.JS_CHOICE, 10) - 1;
        process.stdout.write(data.data.projects[idx].name);
      ")
      cmd_set_project --workspace-id "$workspace_id" --project-id "$selected_id" --project-dir "$project_dir" > /dev/null
      echo ""
      echo "✓ Credentials in .env.local gespeichert"
      echo "✓ Workspace '${workspace}' verbunden"
      echo "✓ Projekt '${selected_name}' verknüpft"
      echo "✓ Board-Verbindung verifiziert"
      echo ""
      echo "Erstelle dein erstes Ticket mit /ticket in Claude Code."
    fi

    rm -f "$response_body"
  elif [ "$http_code" = "401" ]; then
    rm -f "$response_body"
    echo ""
    echo "✓ Credentials in .env.local gespeichert"
    echo "⚠ API-Key wurde abgelehnt (HTTP 401) — prüfe Board → Settings → API Keys"
  else
    rm -f "$response_body"
    echo ""
    echo "✓ Credentials in .env.local gespeichert"
    echo "✓ Workspace '${workspace}' verbunden (offline — Verbindung konnte nicht verifiziert werden)"
  fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

if [ $# -lt 1 ]; then
  usage
fi

COMMAND="$1"
shift

case "$COMMAND" in
  set-project)    cmd_set_project "$@" ;;
  set-key)        cmd_set_key "$@" ;;
  parse-jsp)      cmd_parse_jsp "$@" ;;
  connect)        cmd_connect "$@" ;;
  --help|-h)      usage ;;
  add-workspace|read-workspace|remove-board|migrate)
    echo "Error: '${COMMAND}' was removed in T-1043. Configuration is now project-local."
    echo ""
    echo "Migration paths:"
    echo "  add-workspace  → use 'connect' with a jsp_ token"
    echo "  read-workspace → read JSP_BOARD_API_KEY/JSP_BOARD_API_URL from .env.local"
    echo "  remove-board   → delete the JSP_ lines from .env.local"
    echo "  migrate        → handled by setup.sh on first run after upgrade"
    exit 1
    ;;
  *)
    echo "Error: Unknown command '${COMMAND}'"
    echo ""
    usage
    ;;
esac
