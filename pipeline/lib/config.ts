import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { logger } from "./logger.ts";
import type { ModelRoutingConfig } from "./model-router.ts";

export interface PipelineConfig {
  projectId: string;
  workspaceId: string;
  apiUrl: string;
  apiKey: string;
}

export interface QaConfig {
  maxFixIterations: number;
  playwrightTimeoutMs: number;
  previewProvider: "vercel" | "coolify" | "none";
  vercelProjectId: string;
  vercelTeamId: string;
  vercelPreviewPollIntervalMs: number;
  vercelPreviewMaxWaitMs: number;
  coolifyUrl: string;
  coolifyAppUuid: string;
  coolifyPollIntervalMs: number;
  coolifyMaxWaitMs: number;
  shopifyEnabled?: boolean;
}

export interface ProjectConfig {
  name: string;
  description: string;
  conventions: { branch_prefix: string };
  pipeline: PipelineConfig & {
    skipAgents?: string[];
    maxAutonomousComplexity?: string;
    timeouts?: {
      haiku?: number;
      sonnet?: number;
      opus?: number;
    };
    modelRouting?: ModelRoutingConfig;
  };
  maxWorkers: number;
  qa: QaConfig;
  stack: {
    packageManager: string;
    buildCommand?: string;
    testCommand?: string;
    verifyCommand?: string;
    platform?: string;
    variant?: string;
  };
  skills?: {
    domain?: string[];
    custom?: string[];
  };
}

export interface TicketArgs {
  ticketId: string;
  title: string;
  description: string;
  labels: string;
}

/**
 * Read .env.local from the project directory and parse it for credentials.
 * Returns an empty object if the file doesn't exist or can't be parsed.
 *
 * Format: KEY=VALUE per line. Comments (#…) and blank lines are skipped.
 * Values are taken verbatim — no shell expansion, no quote stripping
 * beyond a single matching pair of double or single quotes.
 */
function loadEnvLocal(projectDir: string): Record<string, string> {
  const envPath = resolve(projectDir, ".env.local");
  if (!existsSync(envPath)) return {};
  try {
    const raw = readFileSync(envPath, "utf-8");
    const out: Record<string, string> = {};
    for (const rawLine of raw.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line || line.startsWith("#")) continue;
      const eq = line.indexOf("=");
      if (eq < 1) continue;
      const key = line.slice(0, eq).trim();
      let value = line.slice(eq + 1).trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      out[key] = value;
    }
    return out;
  } catch {
    logger.warn({ envPath }, "Could not parse .env.local — continuing without it");
    return {};
  }
}

function buildPipelineConfig(
  rawPipeline: Record<string, unknown>,
  apiUrl: string,
  apiKey: string,
): PipelineConfig {
  return {
    projectId:   (rawPipeline.project_id as string) ?? "",
    workspaceId: (rawPipeline.workspace_id as string) ?? "",
    apiUrl,
    apiKey,
  };
}

export function loadProjectConfig(projectDir: string): ProjectConfig {
  const configPath = resolve(projectDir, "project.json");
  if (!existsSync(configPath)) {
    logger.error({ configPath }, "project.json NOT FOUND — using defaults. Pipeline will not work correctly!");
    return {
      name: "project",
      description: "",
      conventions: { branch_prefix: "feature/" },
      pipeline: { ...buildPipelineConfig({}, "", ""), skipAgents: [], timeouts: undefined },
      maxWorkers: 1,
      qa: {
        maxFixIterations: 3,
        playwrightTimeoutMs: 60000,
        previewProvider: "none",
        vercelProjectId: "",
        vercelTeamId: "",
        vercelPreviewPollIntervalMs: 10000,
        vercelPreviewMaxWaitMs: 300000,
        coolifyUrl: "",
        coolifyAppUuid: "",
        coolifyPollIntervalMs: 10000,
        coolifyMaxWaitMs: 300000,
      },
      stack: { packageManager: "npm" },
      skills: undefined,
    };
  }
  const raw = JSON.parse(readFileSync(configPath, "utf-8"));

  // --- Pipeline config resolution (project-local only) ---
  //
  // Sources, in priority order:
  //   1. Process env (JSP_BOARD_API_KEY / JSP_BOARD_API_URL — set by VPS,
  //      CI, or by the developer's shell)
  //   2. Plugin userConfig env (CLAUDE_USER_CONFIG_BOARD_API_KEY / _URL)
  //   3. .env.local in the project directory (gitignored, written by
  //      `connect-board` / `write-config.sh connect`)
  //   4. project.json → pipeline.board_url (URL only — NOT a key source)
  //   5. SERVER_CONFIG_PATH → multi-project VPS deployments (legitimate
  //      shared-credential location, owned by ops, not the user's $HOME)
  //
  // The legacy ~/.just-ship/config.json path is fully removed. If the API
  // key is missing here, the pipeline cannot make Board API calls — but
  // that's a setup problem the user has to fix via `connect-board`, not
  // something this loader can paper over.
  const rawPipeline = raw.pipeline ?? {};
  const env = loadEnvLocal(projectDir);

  let apiKey =
    process.env.JSP_BOARD_API_KEY ||
    process.env.PIPELINE_KEY ||
    process.env.CLAUDE_USER_CONFIG_BOARD_API_KEY ||
    env.JSP_BOARD_API_KEY ||
    "";

  let apiUrl =
    process.env.JSP_BOARD_API_URL ||
    process.env.BOARD_API_URL ||
    process.env.CLAUDE_USER_CONFIG_BOARD_API_URL ||
    env.JSP_BOARD_API_URL ||
    (rawPipeline.board_url as string | undefined) ||
    "";

  // VPS multi-project mode — server-config.json holds shared credentials
  // (owned by ops, not the developer). This is independent of the
  // project-local credential split documented above.
  if ((!apiKey || !apiUrl) && process.env.SERVER_CONFIG_PATH) {
    try {
      const serverConfigPath = process.env.SERVER_CONFIG_PATH;
      const serverConfig = JSON.parse(readFileSync(serverConfigPath, "utf-8"));
      apiUrl = apiUrl || (serverConfig?.workspace?.board_url ?? "");
      apiKey = apiKey || (serverConfig?.workspace?.api_key ?? "");
    } catch {
      logger.warn(
        { serverConfigPath: process.env.SERVER_CONFIG_PATH },
        "Could not read SERVER_CONFIG_PATH",
      );
    }
  }

  if (rawPipeline.workspace_id && !apiKey) {
    logger.warn(
      { workspaceId: rawPipeline.workspace_id },
      "workspace_id is set but no JSP_BOARD_API_KEY found. " +
      "Set it in .env.local — run /connect-board to provision.",
    );
  }

  const pipeline: PipelineConfig = buildPipelineConfig(rawPipeline, apiUrl, apiKey);

  const rawQa = rawPipeline.qa ?? {};

  // Read hosting config from root of project.json (new format)
  // Supports both object format {provider, project_id, team_id} and legacy string format
  const rawHosting = raw.hosting;
  let hostingProvider: "vercel" | "coolify" | "none" = "none";
  let vercelProjectId = "";
  let vercelTeamId = "";
  let coolifyUrl = "";
  let coolifyAppUuid = "";

  if (typeof rawHosting === "object" && rawHosting !== null) {
    const h = rawHosting as { provider?: string; project_id?: string; team_id?: string; coolify_url?: string; coolify_app_uuid?: string };
    if (h.provider === "vercel") {
      hostingProvider = "vercel";
      vercelProjectId = h.project_id ?? "";
      vercelTeamId = h.team_id ?? "";
    } else if (h.provider === "coolify") {
      hostingProvider = "coolify";
      coolifyUrl = h.coolify_url ?? "";
      coolifyAppUuid = h.coolify_app_uuid ?? "";
    }
  } else if (typeof rawHosting === "string" && rawHosting === "vercel") {
    // Legacy string format: "vercel" (backwards compatibility)
    hostingProvider = "vercel";
    vercelProjectId = (rawQa.vercel_project_id as string) ?? "";
    vercelTeamId = (rawQa.vercel_team_id as string) ?? "";
  }

  const qa: QaConfig = {
    maxFixIterations: Number(rawQa.max_fix_iterations ?? 3),
    playwrightTimeoutMs: Number(rawQa.playwright_timeout_ms ?? 60000),
    previewProvider: (rawQa.preview_provider as "vercel" | "coolify" | "none") ?? hostingProvider,
    vercelProjectId: vercelProjectId || ((rawQa.vercel_project_id as string) ?? ""),
    vercelTeamId: vercelTeamId || ((rawQa.vercel_team_id as string) ?? ""),
    vercelPreviewPollIntervalMs: Number(rawQa.vercel_preview_poll_interval_ms ?? 10000),
    vercelPreviewMaxWaitMs: Number(rawQa.vercel_preview_max_wait_ms ?? 300000),
    coolifyUrl: coolifyUrl || ((rawQa.coolify_url as string) ?? ""),
    coolifyAppUuid: coolifyAppUuid || ((rawQa.coolify_app_uuid as string) ?? ""),
    coolifyPollIntervalMs: Number(rawQa.coolify_poll_interval_ms ?? 10000),
    coolifyMaxWaitMs: Number(rawQa.coolify_max_wait_ms ?? 300000),
    shopifyEnabled: raw.stack?.platform === "shopify",
  };

  return {
    name: raw.name ?? "project",
    description: raw.description ?? "",
    conventions: { branch_prefix: raw.conventions?.branch_prefix ?? "feature/" },
    pipeline: {
      ...pipeline,
      skipAgents: (rawPipeline.skip_agents as string[]) ?? [],
      maxAutonomousComplexity: (rawPipeline.max_autonomous_complexity as string) ?? "medium",
      timeouts: rawPipeline.timeouts as { haiku?: number; sonnet?: number; opus?: number } | undefined,
      modelRouting: rawPipeline.model_routing as ModelRoutingConfig | undefined,
    },
    maxWorkers: Number(rawPipeline.max_workers ?? 1),
    qa,
    stack: {
      packageManager: raw.stack?.package_manager ?? "npm",
      buildCommand: raw.build?.web as string | undefined,
      testCommand: raw.build?.test as string | undefined,
      verifyCommand: raw.build?.verify as string | undefined,
      platform: raw.stack?.platform as string | undefined,
      variant: raw.stack?.variant as string | undefined,
    },
    skills: raw.skills as { domain?: string[]; custom?: string[] } | undefined,
  };
}

export function parseCliArgs(args: string[]): TicketArgs {
  const [ticketId, title, description, labels] = args;
  if (!ticketId || !title) {
    throw new Error("Usage: run.ts <TICKET_ID> <TITLE> [DESCRIPTION] [LABELS]");
  }
  return {
    ticketId,
    title,
    description: description ?? "No description provided",
    labels: labels ?? "",
  };
}
