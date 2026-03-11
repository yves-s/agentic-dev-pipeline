"use client";

import dynamic from "next/dynamic";
import type { Ticket, Project, WorkspaceMember } from "@/lib/types";

const Board = dynamic(() => import("./board").then((m) => m.Board), {
  ssr: false,
});

interface BoardClientProps {
  initialTickets: Ticket[];
  initialColumnCounts: Record<string, number>;
  workspaceId: string;
  workspaceSlug: string;
  projects: Project[];
  members: WorkspaceMember[];
}

export function BoardClient({
  initialTickets,
  initialColumnCounts,
  workspaceId,
  workspaceSlug,
  projects,
  members,
}: BoardClientProps) {
  return (
    <Board
      initialTickets={initialTickets}
      initialColumnCounts={initialColumnCounts}
      workspaceId={workspaceId}
      workspaceSlug={workspaceSlug}
      projects={projects}
      members={members}
    />
  );
}
