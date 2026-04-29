#!/bin/sh
# Wrapper for the Just Ship pipeline runner.
# Includes a drift-check that detects stale .pipeline/ installs.
#
# Engine repo (pipeline/ source exists): drift → auto-runs setup.sh --update.
# Consumer repos (no pipeline/ source):  drift → error with version diff, exit 1.
#
# Bypass: JUSTSHIP_SKIP_DRIFT_CHECK=1
# Documented: .claude/rules/self-install-topology.md

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Drift check ---
if [ "${JUSTSHIP_SKIP_DRIFT_CHECK:-0}" != "1" ]; then
  _version_file="$PROJECT_DIR/.claude/.pipeline-version"
  _source_dir="$PROJECT_DIR/pipeline"

  if [ -f "$_version_file" ]; then
    _installed_version=$(cat "$_version_file")
    _installed_hash=$(echo "$_installed_version" | cut -d' ' -f1)

    if [ "$_installed_hash" != "local" ]; then
      if [ -d "$_source_dir" ] && git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        # Engine repo: source directory exists + git available
        # Verify the installed hash is a known commit before diffing
        if git -C "$PROJECT_DIR" cat-file -e "${_installed_hash}^{commit}" 2>/dev/null; then
          # Check if pipeline/ source changed since the installed version
          if ! git -C "$PROJECT_DIR" diff --quiet "$_installed_hash" HEAD -- pipeline/ 2>/dev/null; then
            _source_hash=$(git -C "$PROJECT_DIR" log -1 --format=%h -- pipeline/ 2>/dev/null || echo "unknown")
            echo "▶ pipeline · drift detected (installed: $_installed_hash, source: $_source_hash)" >&2
            echo "▶ pipeline · auto-updating .pipeline/ from source" >&2
            JUSTSHIP_BYPASS_SELF_INSTALL_GUARD=1 bash "$PROJECT_DIR/setup.sh" --update >&2
            echo "▶ pipeline · update complete, continuing" >&2
          fi
        fi
        # If hash is unknown (e.g. after history rewrite), skip silently
      else
        # Consumer repo or no git: check version stamp
        _stamp_file="$SCRIPT_DIR/.version-stamp"
        if [ -f "$_stamp_file" ]; then
          _stamp_version=$(cat "$_stamp_file")
          _stamp_hash=$(echo "$_stamp_version" | cut -d' ' -f1)
          if [ "$_installed_hash" != "$_stamp_hash" ]; then
            echo "" >&2
            echo "ERROR: pipeline drift detected — installed version does not match pipeline stamp." >&2
            echo "  installed (.claude/.pipeline-version): $_installed_version" >&2
            echo "  expected  (.pipeline/.version-stamp):  $_stamp_version" >&2
            echo "" >&2
            echo "Run: setup.sh --update" >&2
            echo "" >&2
            exit 1
          fi
        fi
      fi
    fi
  fi
fi

# --- Test mode: exit after drift check without running pipeline ---
if [ "${_DRIFT_CHECK_TEST:-0}" = "1" ]; then
  echo "DRIFT_CHECK_PASS"
  exit 0
fi

exec npx tsx "$SCRIPT_DIR/run.ts" "$@"
