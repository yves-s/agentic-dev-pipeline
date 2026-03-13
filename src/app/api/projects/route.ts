import { validatePipelineKey } from "@/lib/api/pipeline-key-auth";
import { success, error, unauthorized, validationError } from "@/lib/api/error-response";
import { createServiceClient } from "@/lib/supabase/service";
import { createProjectSchema } from "@/lib/validations/project";

export async function GET(request: Request) {
  try {
    const auth = await validatePipelineKey(request);
    if (auth.error) return unauthorized(auth.error);

    const workspaceId = auth.workspace_id!;
    const supabase = createServiceClient();

    const { data: workspace } = await supabase
      .from("workspaces")
      .select("id, name")
      .eq("id", workspaceId)
      .single();

    const { data: projects } = await supabase
      .from("projects")
      .select("id, name, description")
      .eq("workspace_id", workspaceId)
      .order("name");

    return success({
      workspace_id: workspace?.id,
      workspace_name: workspace?.name,
      projects: projects ?? [],
    });
  } catch (err) {
    return error("INTERNAL_ERROR", "An unexpected error occurred", 500);
  }
}

export async function POST(request: Request) {
  try {
    const auth = await validatePipelineKey(request);
    if (auth.error) return unauthorized(auth.error);

    const workspaceId = auth.workspace_id!;
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return error("INVALID_JSON", "Request body must be valid JSON", 400);
    }

    const parsed = createProjectSchema.safeParse(body);
    if (!parsed.success) return validationError(parsed.error);

    const supabase = createServiceClient();

    // Quota: max 50 projects per workspace
    const { count } = await supabase
      .from("projects")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", workspaceId);

    if (count !== null && count >= 50) {
      return error("QUOTA_EXCEEDED", "Maximum 50 projects per workspace", 422);
    }

    const { data: project, error: dbError } = await supabase
      .from("projects")
      .insert({
        workspace_id: workspaceId,
        name: parsed.data.name,
        description: parsed.data.description ?? null,
      })
      .select("id, name, workspace_id, description")
      .single();

    if (dbError) {
      if (dbError.code === "23505") {
        return error("CONFLICT", "Project name already exists", 409);
      }
      return error("DB_ERROR", dbError.message, 500);
    }

    return success(project, 201);
  } catch (err) {
    return error("INTERNAL_ERROR", "An unexpected error occurred", 500);
  }
}
