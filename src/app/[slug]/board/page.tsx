import { createClient } from "@/lib/supabase/server";
import { BoardHeader } from "@/components/board/board-header";
import { BoardClient } from "@/components/board/board-client";
import { BOARD_COLUMNS, TICKETS_PER_COLUMN_PAGE } from "@/lib/constants";
import type { Ticket, Project, WorkspaceMember } from "@/lib/types";

export default async function BoardPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const supabase = await createClient();

  const { data: workspace } = await supabase
    .from("workspaces")
    .select("id")
    .eq("slug", slug)
    .single();

  const tickets: Ticket[] = [];
  const projects: Project[] = [];
  const members: WorkspaceMember[] = [];
  const initialColumnCounts: Record<string, number> = {};

  if (workspace) {
    const ticketQueries = BOARD_COLUMNS.map((col) =>
      supabase
        .from("tickets")
        .select(
          "*, project:projects(id, name, description, workspace_id, created_at, updated_at)",
          { count: "exact" }
        )
        .eq("workspace_id", workspace.id)
        .eq("status", col.status)
        .order("updated_at", { ascending: false })
        .limit(TICKETS_PER_COLUMN_PAGE)
    );

    const [ticketResults, projectsResult, membersResult] = await Promise.all([
      Promise.all(ticketQueries),
      supabase
        .from("projects")
        .select("*")
        .eq("workspace_id", workspace.id)
        .order("name"),
      supabase
        .from("workspace_members")
        .select("id, workspace_id, user_id, role, joined_at, user_email")
        .eq("workspace_id", workspace.id),
    ]);

    for (let i = 0; i < BOARD_COLUMNS.length; i++) {
      const result = ticketResults[i];
      if (result.data) tickets.push(...(result.data as Ticket[]));
      initialColumnCounts[BOARD_COLUMNS[i].status] = result.count ?? 0;
    }

    if (projectsResult.data) projects.push(...(projectsResult.data as Project[]));
    if (membersResult.data) members.push(...(membersResult.data as WorkspaceMember[]));
  }

  return (
    <>
      <BoardHeader workspaceId={workspace?.id ?? ""} />
      <BoardClient
        initialTickets={tickets}
        initialColumnCounts={initialColumnCounts}
        workspaceId={workspace?.id ?? ""}
        workspaceSlug={slug}
        projects={projects}
        members={members}
      />
    </>
  );
}
