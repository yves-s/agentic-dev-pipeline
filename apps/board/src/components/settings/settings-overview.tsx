"use client";

import Link from "next/link";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useWorkspace } from "@/lib/workspace-context";
import type { Project, WorkspaceMember } from "@/lib/types";

interface SettingsOverviewProps {
  stats: {
    projects: number;
    members: number;
    openTickets: number;
    apiKeys: number;
  };
  projects: (Project & { ticketCount: number })[];
  members: WorkspaceMember[];
  totalMembers: number;
  recentActivity: ActivityItem[];
}

export interface ActivityItem {
  id: string;
  type: "ticket_created" | "member_joined" | "project_created";
  title: string;
  timestamp: string;
}

function getInitials(email: string): string {
  const parts = email.split("@")[0].split(/[._-]/);
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return email.slice(0, 2).toUpperCase();
}

function relativeTime(date: string): string {
  const now = Date.now();
  const then = new Date(date).getTime();
  const diff = now - then;
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  return new Date(date).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

const ACTIVITY_DOT_COLORS: Record<ActivityItem["type"], string> = {
  ticket_created: "bg-blue-500",
  member_joined: "bg-emerald-500",
  project_created: "bg-amber-500",
};

const PROJECT_COLORS = [
  "bg-emerald-600",
  "bg-blue-600",
  "bg-amber-600",
  "bg-purple-600",
  "bg-rose-600",
];

const ROLE_LABELS: Record<string, string> = {
  owner: "Owner",
  admin: "Admin",
  member: "Member",
};

export function SettingsOverview({
  stats,
  projects,
  members,
  totalMembers,
  recentActivity,
}: SettingsOverviewProps) {
  const workspace = useWorkspace();
  const slug = workspace.slug;

  return (
    <div className="flex flex-col gap-6">
      {/* Stats Row */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: "Projects", value: stats.projects },
          { label: "Members", value: stats.members },
          { label: "Open Tickets", value: stats.openTickets },
          { label: "API Keys", value: stats.apiKeys },
        ].map((stat) => (
          <Card key={stat.label}>
            <CardContent className="p-4">
              <p className="text-[10px] uppercase tracking-wider text-muted-foreground">
                {stat.label}
              </p>
              <p className="mt-1 text-2xl font-bold">{stat.value}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Two-Column: Projects + Members */}
      <div className="grid gap-4 md:grid-cols-2">
        {/* Projects Card */}
        <Card>
          <CardHeader className="flex-row items-center justify-between pb-3">
            <CardTitle className="text-sm">
              Projects ({stats.projects})
            </CardTitle>
            <Link
              href={`/${slug}/settings/projects`}
              className="text-xs text-primary hover:underline"
            >
              View all &rarr;
            </Link>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {projects.length === 0 ? (
              <p className="py-4 text-center text-sm text-muted-foreground">
                No projects yet.{" "}
                <Link
                  href={`/${slug}/settings/projects`}
                  className="text-primary hover:underline"
                >
                  Create your first project
                </Link>
              </p>
            ) : (
              projects.map((project, i) => (
                <div
                  key={project.id}
                  className="flex items-center gap-3 rounded-md bg-muted/40 px-3 py-2"
                >
                  <div
                    className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-xs font-bold text-white ${PROJECT_COLORS[i % PROJECT_COLORS.length]}`}
                  >
                    {(project.name?.[0] ?? "?").toUpperCase()}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">
                      {project.name}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {project.ticketCount}{" "}
                      {project.ticketCount === 1 ? "ticket" : "tickets"}
                    </p>
                  </div>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        {/* Members Card */}
        <Card>
          <CardHeader className="flex-row items-center justify-between pb-3">
            <CardTitle className="text-sm">
              Members ({stats.members})
            </CardTitle>
            <Link
              href={`/${slug}/settings/members`}
              className="text-xs text-primary hover:underline"
            >
              View all &rarr;
            </Link>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {members.length === 0 ? (
              <p className="py-4 text-center text-sm text-muted-foreground">
                No other members yet.{" "}
                <Link
                  href={`/${slug}/settings/members`}
                  className="text-primary hover:underline"
                >
                  Invite a team member
                </Link>
              </p>
            ) : (
              <>
                {members.map((member) => (
                  <div
                    key={member.id}
                    className="flex items-center gap-3 rounded-md bg-muted/40 px-3 py-2"
                  >
                    <Avatar className="h-7 w-7 shrink-0">
                      <AvatarFallback className="text-[10px]">
                        {getInitials(member.user_email ?? "")}
                      </AvatarFallback>
                    </Avatar>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm truncate">
                        {member.user_email}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {ROLE_LABELS[member.role] ?? member.role}
                      </p>
                    </div>
                  </div>
                ))}
                {totalMembers > members.length && (
                  <Link
                    href={`/${slug}/settings/members`}
                    className="rounded-md bg-muted/40 px-3 py-2 text-center text-xs text-muted-foreground hover:text-foreground transition-colors"
                  >
                    +{totalMembers - members.length} more members
                  </Link>
                )}
              </>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Activity Feed */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm">Recent Activity</CardTitle>
        </CardHeader>
        <CardContent>
          {recentActivity.length === 0 ? (
            <p className="py-4 text-center text-sm text-muted-foreground">
              No recent activity
            </p>
          ) : (
            <div className="flex flex-col gap-3">
              {recentActivity.map((item) => (
                <div key={item.id} className="flex items-start gap-3">
                  <div
                    className={`mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full ${ACTIVITY_DOT_COLORS[item.type]}`}
                  />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm">{item.title}</p>
                    <p className="text-xs text-muted-foreground">
                      {relativeTime(item.timestamp)}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
