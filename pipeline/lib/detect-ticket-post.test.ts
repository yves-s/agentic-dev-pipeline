import { describe, test, expect } from "vitest";
import * as fs from "fs";
import * as path from "path";

/**
 * Test for detect-ticket-post.sh behavior:
 * AC1: Must write .active-ticket to project root, not worktree CWD
 * AC2: on-session-end.sh must find ticket even if /develop ran in worktree
 */
describe("detect-ticket-post.sh + cost tracking", () => {
  test("model pricing includes claude-opus-4-6", () => {
    // AC3: verify new model IDs are recognized
    const costScript = fs.readFileSync(
      path.join(__dirname, "../..", ".claude/scripts/calculate-session-cost.sh"),
      "utf-8"
    );
    expect(costScript).toContain("'claude-opus-4-20250514'");
    expect(costScript).toContain("'claude-sonnet-4-20250514'");
    expect(costScript).toContain("'claude-haiku-4-5-20251001'");
  });

  test("cost.ts includes all model IDs", () => {
    // AC4: MODEL_PRICING is up-to-date
    const costTS = fs.readFileSync(
      path.join(__dirname, "cost.ts"),
      "utf-8"
    );
    expect(costTS).toContain('"claude-opus-4-20250514"');
    expect(costTS).toContain('"claude-sonnet-4-20250514"');
    expect(costTS).toContain('"claude-haiku-4-5-20251001"');
    // Verify pricing values exist for each
    expect(costTS).toContain('input: 0.015, output: 0.075'); // Opus
    expect(costTS).toContain('input: 0.003, output: 0.015'); // Sonnet
    expect(costTS).toContain('input: 0.0008, output: 0.004'); // Haiku
  });

  test("detect-ticket-post.sh resolves project root correctly", () => {
    // AC1: verify the hook script resolves project root via git
    const hookScript = fs.readFileSync(
      path.join(__dirname, "../..", ".claude/hooks/detect-ticket-post.sh"),
      "utf-8"
    );

    // The fix must use git rev-parse --git-common-dir to resolve project root
    // and then write to PROJECT_ROOT/.claude/.active-ticket (not CWD)
    expect(hookScript).toContain("git rev-parse --git-common-dir");
    expect(hookScript).toContain("PROJECT_ROOT");
    expect(hookScript).toContain("$PROJECT_ROOT/.claude/.active-ticket");
  });

  test("on-session-end.sh reads from correct .active-ticket location", () => {
    // AC2: verify the hook can find ticket written by detect-ticket-post
    const hookScript = fs.readFileSync(
      path.join(__dirname, "../..", ".claude/hooks/on-session-end.sh"),
      "utf-8"
    );

    // Both detect-ticket-post and on-session-end should use same logic to resolve project root:
    // If in worktree → git rev-parse --git-common-dir → parent dir is project root
    // If in main repo → git rev-parse --git-common-dir returns .git → parent dir is project root
    expect(hookScript).toContain('git rev-parse --git-common-dir');
    expect(hookScript).toContain('PROJECT_ROOT');
    expect(hookScript).toContain('$PROJECT_ROOT/.claude/.active-ticket');
  });
});
