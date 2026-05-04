#!/usr/bin/env bash
# Smoke tests for .githooks/pre-commit — applies_to: frontmatter validation.
#
# The legacy installed-copy edit blocker (Gate 1) is gone since T-1064 — the
# engine repo no longer maintains a `.pipeline/` install copy, so the
# Source/Install duplication that gate protected against cannot occur.
#
# These scenarios exercise the remaining `applies_to:` frontmatter check:
#   1. Artifact with applies_to: frontmatter         → commit accepted
#   2. Artifact missing applies_to: frontmatter      → commit rejected
#   3. Override env var bypasses the check           → commit accepted
#   4. Non-artifact file (no applies_to: required)   → commit accepted
#
# Run: bash .claude/scripts/githook-pre-commit.test.sh
# Exits 0 on all-green, non-zero on first failure.

set -u

# Locate the framework repo root (two levels up from this script).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
FRAMEWORK_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
HOOK_SRC="$FRAMEWORK_ROOT/.githooks/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "FAIL: hook source not found at $HOOK_SRC"
  exit 1
fi

PASSED=0
FAILED=0
TESTS_RUN=0

pass() {
  PASSED=$((PASSED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  ✓ $1"
}

fail() {
  FAILED=$((FAILED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "  ✗ $1"
}

# Create a minimal git repo with a baseline artifact tree. The hook will
# validate any addition or modification under `.claude/{rules,skills,agents}/`,
# `skills/<name>/SKILL.md`, `agents/`, or `rules/`.
setup_repo() {
  local dir=$1

  mkdir -p "$dir"
  (cd "$dir" && git init -q && git config user.email "test@test" && git config user.name "test")

  # Install the hook in the same way setup.sh would.
  mkdir -p "$dir/.githooks"
  cp "$HOOK_SRC" "$dir/.githooks/pre-commit"
  chmod +x "$dir/.githooks/pre-commit"
  (cd "$dir" && git config core.hooksPath .githooks)

  # Seed an initial commit with one valid artifact and one normal file.
  mkdir -p "$dir/.claude/rules" "$dir/src"
  cat > "$dir/.claude/rules/seed.md" <<'EOF'
---
applies_to: top-level-only
---

Seed rule for test setup.
EOF
  echo 'export const x = 1;' > "$dir/src/index.ts"
  (cd "$dir" && git add -A && GIT_ALLOW_INSTALLED_EDIT=1 git commit -q -m "initial" 2>/dev/null)
}

# Run a commit test against a freshly-staged file.
#   $1 = human label
#   $2 = repo dir
#   $3 = relative file path to create/modify
#   $4 = file content
#   $5 = "block" | "allow"  — expected outcome
#   $6 = (optional) env var prefix
run_commit_test() {
  local label=$1
  local dir=$2
  local file=$3
  local content=$4
  local expected=$5
  local env_prefix=${6:-}

  mkdir -p "$(dirname "$dir/$file")"
  printf '%s' "$content" > "$dir/$file"
  (cd "$dir" && git add -- "$file")

  local rc
  if [ -n "$env_prefix" ]; then
    # shellcheck disable=SC2086
    (cd "$dir" && env $env_prefix git commit -q -m "test commit" >/dev/null 2>&1)
    rc=$?
  else
    (cd "$dir" && git commit -q -m "test commit" >/dev/null 2>&1)
    rc=$?
  fi

  case "$expected" in
    block)
      if [ $rc -ne 0 ]; then pass "$label"; else fail "$label (expected block, got pass)"; fi
      # Clean up the staged change so subsequent tests start clean.
      (cd "$dir" && git reset -q HEAD -- "$file" 2>/dev/null || true)
      rm -f "$dir/$file"
      ;;
    allow)
      if [ $rc -eq 0 ]; then pass "$label"; else fail "$label (expected pass, got block)"; fi
      ;;
  esac
}

# ---------- Execute scenarios ----------

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo ""
echo "Scenario 1: artifact with applies_to: frontmatter"
setup_repo "$TMP/valid"
run_commit_test \
  "rule with applies_to: is allowed" \
  "$TMP/valid" \
  ".claude/rules/new-rule.md" \
  "$(printf -- '---\napplies_to: top-level-only\n---\n\nNew rule body.\n')" \
  allow

echo ""
echo "Scenario 2: artifact missing applies_to: frontmatter"
setup_repo "$TMP/missing-rule"
run_commit_test \
  "rule without applies_to: is blocked" \
  "$TMP/missing-rule" \
  ".claude/rules/bad-rule.md" \
  "Rule body without frontmatter." \
  block

setup_repo "$TMP/missing-skill"
run_commit_test \
  "skill without applies_to: is blocked" \
  "$TMP/missing-skill" \
  ".claude/skills/bad-skill.md" \
  "Skill body without frontmatter." \
  block

setup_repo "$TMP/missing-agent"
run_commit_test \
  "agent without applies_to: is blocked" \
  "$TMP/missing-agent" \
  ".claude/agents/bad-agent.md" \
  "Agent body without frontmatter." \
  block

echo ""
echo "Scenario 3: override env var bypasses the check"
setup_repo "$TMP/override"
run_commit_test \
  "GIT_ALLOW_INSTALLED_EDIT=1 bypasses missing applies_to: check" \
  "$TMP/override" \
  ".claude/rules/forced-rule.md" \
  "No frontmatter here." \
  allow \
  "GIT_ALLOW_INSTALLED_EDIT=1"

echo ""
echo "Scenario 4: non-artifact file (no applies_to: required)"
setup_repo "$TMP/nonart"
run_commit_test \
  "src/foo.ts edit is allowed" \
  "$TMP/nonart" \
  "src/foo.ts" \
  "export const y = 2;" \
  allow

echo ""
echo "Summary: $PASSED/$TESTS_RUN passed"
if [ $FAILED -ne 0 ]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
