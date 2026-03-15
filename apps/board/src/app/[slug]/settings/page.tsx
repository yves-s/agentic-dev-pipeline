import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  SettingsOverview,
  type ActivityItem,
} from "@/components/settings/settings-overview";

export default async function SettingsPage({
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

  if (!workspace) redirect("/");

  const wid = workspace.id;

  // All queries in a single parallel batch — no sequential waterfalls
  const [
    projectsResult,
    membersResult,
    openTicketsResult,
    apiKeysResult,
    recentTicketsResult,
    recentMembersResult,
    recentProjectsResult,
    projectCountResult,
    memberCountResult,
  ] = await Promise.all([
    supabase
      .from("projects")
      .select("*")
      .eq("workspace_id", wid)
      .order("name")
      .limit(5),
    supabase
      .from("workspace_members")
      .select("id, workspace_id, user_id, role, joined_at, user_email")
      .eq("workspace_id", wid)
      .order("joined_at")
      .limit(5),
    supabase
      .from("tickets")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", wid)
      .not("status", "in", '("done","cancelled")'),
    supabase
      .from("api_keys")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", wid)
      .is("revoked_at", null),
    supabase
      .from("tickets")
      .select("id, number, title, created_at")
      .eq("workspace_id", wid)
      .order("created_at", { ascending: false })
      .limit(10),
    supabase
      .from("workspace_members")
      .select("id, user_email, joined_at")
      .eq("workspace_id", wid)
      .order("joined_at", { ascending: false })
      .limit(5),
    supabase
      .from("projects")
      .select("id, name, created_at")
      .eq("workspace_id", wid)
      .order("created_at", { ascending: false })
      .limit(5),
    supabase
      .from("projects")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", wid),
    supabase
      .from("workspace_members")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", wid),
  ]);

  const projects = projectsResult.data ?? [];
  const members = membersResult.data ?? [];

  // Get ticket counts per project (N+1 but capped at 5 projects — acceptable trade-off)
  const projectsWithCounts = await Promise.all(
    projects.map(async (project) => {
      const { count } = await supabase
        .from("tickets")
        .select("id", { count: "exact", head: true })
        .eq("project_id", project.id);
      return { ...project, ticketCount: count ?? 0 };
    })
  );

  // Build activity feed
  const activity: ActivityItem[] = [];

  for (const t of recentTicketsResult.data ?? []) {
    activity.push({
      id: `ticket-${t.id}`,
      type: "ticket_created",
      title: `Ticket #${t.number} created: ${t.title}`,
      timestamp: t.created_at,
    });
  }

  for (const m of recentMembersResult.data ?? []) {
    activity.push({
      id: `member-${m.id}`,
      type: "member_joined",
      title: `${m.user_email ?? "A user"} joined the workspace`,
      timestamp: m.joined_at,
    });
  }

  for (const p of recentProjectsResult.data ?? []) {
    activity.push({
      id: `project-${p.id}`,
      type: "project_created",
      title: `Project "${p.name}" created`,
      timestamp: p.created_at,
    });
  }

  // Sort by timestamp descending, limit to 10
  activity.sort(
    (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
  );
  const recentActivity = activity.slice(0, 10);

  return (
    <SettingsOverview
      stats={{
        projects: projectCountResult.count ?? projects.length,
        members: memberCountResult.count ?? members.length,
        openTickets: openTicketsResult.count ?? 0,
        apiKeys: apiKeysResult.count ?? 0,
      }}
      projects={projectsWithCounts}
      members={members}
      totalMembers={memberCountResult.count ?? members.length}
      recentActivity={recentActivity}
    />
  );
}
