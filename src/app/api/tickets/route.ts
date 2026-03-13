import { validatePipelineKey } from "@/lib/api/pipeline-key-auth";
import { createServiceClient } from "@/lib/supabase/service";
import { success, error, unauthorized, validationError } from "@/lib/api/error-response";
import { createTicketSchema } from "@/lib/validations/ticket";

export async function GET(request: Request) {
  const auth = await validatePipelineKey(request);
  if (auth.error) return unauthorized(auth.error);

  const { searchParams } = new URL(request.url);
  const status = searchParams.get("status");
  const project = searchParams.get("project");
  const limit = Math.min(
    parseInt(searchParams.get("limit") ?? "10"),
    500
  );

  const supabase = createServiceClient();

  let query = supabase
    .from("tickets")
    .select("*, project:projects(*)")
    .eq("workspace_id", auth.workspace_id!)
    .order("number", { ascending: false })
    .limit(limit);

  if (status) {
    query = query.eq("status", status);
  }

  if (project) {
    // Filter by project name via subquery
    const { data: proj } = await supabase
      .from("projects")
      .select("id")
      .eq("workspace_id", auth.workspace_id!)
      .eq("name", project)
      .single();

    if (proj) {
      query = query.eq("project_id", proj.id);
    } else {
      return success({ tickets: [] });
    }
  }

  const { data: tickets, error: dbError } = await query;
  if (dbError) return error("DB_ERROR", dbError.message, 500);

  return success({ tickets });
}

export async function POST(request: Request) {
  const auth = await validatePipelineKey(request);
  if (auth.error) return unauthorized(auth.error);

  const body = await request.json();
  const parsed = createTicketSchema.safeParse(body);
  if (!parsed.success) return validationError(parsed.error);

  const supabase = createServiceClient();
  const { data: ticket, error: dbError } = await supabase
    .from("tickets")
    .insert({ ...parsed.data, workspace_id: auth.workspace_id })
    .select("*, project:projects(*)")
    .single();

  if (dbError) return error("DB_ERROR", dbError.message, 500);

  return success(ticket, 201);
}
