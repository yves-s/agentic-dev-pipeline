import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { execSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const REPO_ROOT = resolve(__dirname, "..", "..");
const RUN_SH = join(REPO_ROOT, "pipeline", "run.sh");

/**
 * Run the drift check in test mode (_DRIFT_CHECK_TEST=1).
 * This exits after the drift check without calling `exec npx tsx ...`.
 */
function runDriftCheck(
  projectDir: string,
  opts: { env?: Record<string, string> } = {}
): { exitCode: number; stderr: string; stdout: string } {
  // Copy run.sh into the project's .pipeline/ directory so SCRIPT_DIR resolves correctly
  const pipelineDir = join(projectDir, ".pipeline");
  mkdirSync(pipelineDir, { recursive: true });
  const runShContent = readFileSync(RUN_SH, "utf8");
  const targetRunSh = join(pipelineDir, "run.sh");
  writeFileSync(targetRunSh, runShContent, { mode: 0o755 });

  const env: Record<string, string> = {
    ...process.env as Record<string, string>,
    _DRIFT_CHECK_TEST: "1",
    ...(opts.env ?? {}),
  };

  const r = spawnSync("bash", [targetRunSh], {
    cwd: projectDir,
    env,
    encoding: "utf8",
    timeout: 10_000,
  });

  return {
    exitCode: r.status ?? -1,
    stderr: r.stderr ?? "",
    stdout: r.stdout ?? "",
  };
}

/** Initialize a git repo in the given directory with an initial commit. */
function initGitRepo(dir: string): void {
  execSync("git init", { cwd: dir, stdio: "pipe" });
  execSync("git config user.email 'test@test.com'", { cwd: dir, stdio: "pipe" });
  execSync("git config user.name 'Test'", { cwd: dir, stdio: "pipe" });
  // Create a dummy file so we can make an initial commit
  writeFileSync(join(dir, ".gitkeep"), "");
  execSync("git add .gitkeep", { cwd: dir, stdio: "pipe" });
  execSync("git commit -m 'init'", { cwd: dir, stdio: "pipe" });
}

describe("pipeline drift check", () => {
  let tmp: string;

  beforeEach(() => {
    tmp = mkdtempSync(join(tmpdir(), "drift-check-"));
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  // ───────── Scenario 1: No drift ─────────

  describe("no drift", () => {
    it("passes through when installed version matches source", () => {
      initGitRepo(tmp);

      // Create pipeline/ source directory with a file
      mkdirSync(join(tmp, "pipeline", "lib"), { recursive: true });
      writeFileSync(join(tmp, "pipeline", "run.ts"), "// pipeline runner");
      execSync("git add pipeline/", { cwd: tmp, stdio: "pipe" });
      execSync("git commit -m 'add pipeline'", { cwd: tmp, stdio: "pipe" });

      // Get the commit hash (short)
      const hash = execSync("git rev-parse --short HEAD", { cwd: tmp, encoding: "utf8" }).trim();

      // Write .claude/.pipeline-version with the current hash
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      writeFileSync(join(tmp, ".claude", ".pipeline-version"), `${hash} (2026-04-29)`);

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
      expect(r.stderr).not.toContain("drift");
    });

    it("passes through when version is 'local'", () => {
      initGitRepo(tmp);
      mkdirSync(join(tmp, "pipeline"), { recursive: true });
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      writeFileSync(join(tmp, ".claude", ".pipeline-version"), "local (2026-04-29)");

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
    });

    it("passes through when no version file exists", () => {
      initGitRepo(tmp);
      // No .claude/.pipeline-version file

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
    });

    it("passes through when JUSTSHIP_SKIP_DRIFT_CHECK=1", () => {
      initGitRepo(tmp);
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      writeFileSync(join(tmp, ".claude", ".pipeline-version"), "aaaaaaa (2026-04-29)");

      const r = runDriftCheck(tmp, { env: { JUSTSHIP_SKIP_DRIFT_CHECK: "1" } });
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
    });
  });

  // ───────── Scenario 2: Drift with source (engine repo) ─────────

  describe("drift with source (engine repo)", () => {
    it("detects drift when pipeline/ changed since installed version", () => {
      initGitRepo(tmp);

      // Create pipeline/ with initial content
      mkdirSync(join(tmp, "pipeline", "lib"), { recursive: true });
      writeFileSync(join(tmp, "pipeline", "run.ts"), "// v1");
      execSync("git add pipeline/", { cwd: tmp, stdio: "pipe" });
      execSync("git commit -m 'add pipeline v1'", { cwd: tmp, stdio: "pipe" });

      // Record the install hash
      const installHash = execSync("git rev-parse --short HEAD", { cwd: tmp, encoding: "utf8" }).trim();
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      writeFileSync(join(tmp, ".claude", ".pipeline-version"), `${installHash} (2026-04-27)`);

      // Create a mock setup.sh that just updates the version file
      writeFileSync(join(tmp, "setup.sh"), `#!/bin/bash
echo "MOCK_SETUP_UPDATE" >&2
NEW_HASH=$(git rev-parse --short HEAD)
echo "$NEW_HASH (2026-04-29)" > "$PWD/.claude/.pipeline-version"
echo "$NEW_HASH (2026-04-29)" > "$PWD/.pipeline/.version-stamp"
`, { mode: 0o755 });

      // Modify pipeline/ source (create drift)
      writeFileSync(join(tmp, "pipeline", "run.ts"), "// v2 — changed!");
      execSync("git add pipeline/", { cwd: tmp, stdio: "pipe" });
      execSync("git commit -m 'update pipeline v2'", { cwd: tmp, stdio: "pipe" });

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
      expect(r.stderr).toContain("drift detected");
      expect(r.stderr).toContain("auto-updating");
      expect(r.stderr).toContain("MOCK_SETUP_UPDATE");
    });

    it("skips drift check when installed hash is unknown (history rewrite)", () => {
      initGitRepo(tmp);
      mkdirSync(join(tmp, "pipeline"), { recursive: true });
      writeFileSync(join(tmp, "pipeline", "run.ts"), "// content");
      execSync("git add pipeline/", { cwd: tmp, stdio: "pipe" });
      execSync("git commit -m 'add pipeline'", { cwd: tmp, stdio: "pipe" });

      // Use a hash that doesn't exist in git
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      writeFileSync(join(tmp, ".claude", ".pipeline-version"), "deadbee (2026-01-01)");

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
      expect(r.stderr).not.toContain("drift");
    });
  });

  // ───────── Scenario 3: Drift without source (consumer repo) ─────────

  describe("drift without source (consumer repo)", () => {
    it("fails with clear error when stamps differ", () => {
      // Consumer repo: NO pipeline/ source dir, NO git (or no pipeline/ in git)
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      mkdirSync(join(tmp, ".pipeline"), { recursive: true });

      // Installed version says one hash
      writeFileSync(join(tmp, ".claude", ".pipeline-version"), "oldaaaa (2026-04-25)");
      // Version stamp says another hash (the correct one from last setup.sh)
      writeFileSync(join(tmp, ".pipeline", ".version-stamp"), "newbbbb (2026-04-29)");

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(1);
      expect(r.stderr).toContain("pipeline drift detected");
      expect(r.stderr).toContain("oldaaaa");
      expect(r.stderr).toContain("newbbbb");
      expect(r.stderr).toContain("setup.sh --update");
    });

    it("passes when stamps match", () => {
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      mkdirSync(join(tmp, ".pipeline"), { recursive: true });

      writeFileSync(join(tmp, ".claude", ".pipeline-version"), "abc1234 (2026-04-29)");
      writeFileSync(join(tmp, ".pipeline", ".version-stamp"), "abc1234 (2026-04-29)");

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
    });

    it("passes when no stamp file exists (backward compat)", () => {
      mkdirSync(join(tmp, ".claude"), { recursive: true });
      mkdirSync(join(tmp, ".pipeline"), { recursive: true });

      writeFileSync(join(tmp, ".claude", ".pipeline-version"), "abc1234 (2026-04-29)");
      // No .pipeline/.version-stamp file

      const r = runDriftCheck(tmp);
      expect(r.exitCode).toBe(0);
      expect(r.stdout).toContain("DRIFT_CHECK_PASS");
    });
  });
});
