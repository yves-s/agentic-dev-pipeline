# Settings Workspace Overview Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Settings pages with a Sanity-inspired Workspace Identity Header, horizontal tab navigation, and a new Overview dashboard tab.

**Architecture:** Replace the current settings layout (header + left sidebar nav) with a two-part header: workspace identity block (avatar, name, ID, slug, created date) and horizontal tab bar. The default `/[slug]/settings` route renders a new Overview page with stats, project/member summaries, and a derived activity feed. General settings moves to `/[slug]/settings/general`.

**Tech Stack:** Next.js 16 (App Router), React 19, TypeScript, Tailwind CSS 4, shadcn/ui, Supabase, `useWorkspace()` context

**Spec:** `docs/superpowers/specs/2026-03-15-settings-workspace-overview-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `src/components/ui/copy-button.tsx` | **New.** Reusable copy-to-clipboard button with "Copied!" feedback |
| `src/components/settings/workspace-identity-header.tsx` | **New.** Client component: avatar, workspace name, ID (truncated + copy), slug, created date |
| `src/components/settings/settings-nav.tsx` | **Rewrite.** Vertical sidebar → horizontal tab bar with active-state logic |
| `src/app/[slug]/settings/layout.tsx` | **Rewrite.** Identity header + horizontal tabs + full-width content area |
| `src/app/[slug]/settings/general/page.tsx` | **New.** Server component that fetches workspace and renders `SettingsGeneral` |
| `src/app/[slug]/settings/page.tsx` | **Rewrite.** Overview page with stats, projects, members, activity |
| `src/components/settings/settings-overview.tsx` | **New.** Client component for the Overview dashboard content |
| `src/app/[slug]/settings/loading.tsx` | **New.** Skeleton loading state for the Overview page |

All paths are relative to `apps/board/`.

---

## Chunk 1: Foundation (CopyButton, Identity Header, Tabs, Layout)

### Task 1: CopyButton UI Component

**Files:**
- Create: `src/components/ui/copy-button.tsx`

- [ ] **Step 1: Create CopyButton component**

```tsx
"use client";

import { useState } from "react";
import { Copy, Check } from "lucide-react";
import { cn } from "@/lib/utils";

interface CopyButtonProps {
  value: string;
  className?: string;
}

export function CopyButton({ value, className }: CopyButtonProps) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API not available — silently fail
    }
  }

  return (
    <button
      type="button"
      onClick={handleCopy}
      className={cn(
        "inline-flex items-center justify-center h-5 w-5 rounded text-muted-foreground hover:text-foreground hover:bg-accent transition-colors",
        className
      )}
      title={copied ? "Copied!" : "Copy to clipboard"}
    >
      {copied ? (
        <Check className="h-3 w-3 text-emerald-500" />
      ) : (
        <Copy className="h-3 w-3" />
      )}
    </button>
  );
}
```

- [ ] **Step 2: Verify it renders**

Run: `cd apps/board && npx next build 2>&1 | head -20` (or `npm run dev` and check manually)

- [ ] **Step 3: Commit**

```bash
git add apps/board/src/components/ui/copy-button.tsx
git commit -m "feat(board): add reusable CopyButton component"
```

---

### Task 2: Workspace Identity Header

**Files:**
- Create: `src/components/settings/workspace-identity-header.tsx`

- [ ] **Step 1: Create WorkspaceIdentityHeader component**

```tsx
"use client";

import { useWorkspace } from "@/lib/workspace-context";
import { CopyButton } from "@/components/ui/copy-button";

function formatDate(date: string): string {
  return new Date(date).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function truncateId(id: string): string {
  return id.length > 8 ? id.slice(0, 8) + "…" : id;
}

export function WorkspaceIdentityHeader() {
  const workspace = useWorkspace();

  return (
    <div className="flex items-start gap-4 px-6 pt-6 pb-4">
      <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-primary text-lg font-bold text-primary-foreground">
        {(workspace.name?.[0] ?? "?").toUpperCase()}
      </div>
      <div className="flex-1 min-w-0">
        <h1 className="text-xl font-bold truncate">{workspace.name}</h1>
        <div className="mt-1 flex flex-wrap items-center gap-x-5 gap-y-1">
          <div>
            <span className="text-[10px] uppercase tracking-wider text-muted-foreground">
              Workspace ID
            </span>
            <div className="flex items-center gap-1">
              <span
                className="font-mono text-xs text-muted-foreground"
                title={workspace.id}
              >
                {truncateId(workspace.id)}
              </span>
              <CopyButton value={workspace.id} />
            </div>
          </div>
          <div>
            <span className="text-[10px] uppercase tracking-wider text-muted-foreground">
              Slug
            </span>
            <div className="font-mono text-xs text-muted-foreground">
              {workspace.slug}
            </div>
          </div>
          <div>
            <span className="text-[10px] uppercase tracking-wider text-muted-foreground">
              Created
            </span>
            <div className="text-xs text-muted-foreground">
              {formatDate(workspace.created_at)}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/board/src/components/settings/workspace-identity-header.tsx
git commit -m "feat(board): add WorkspaceIdentityHeader component"
```

---

### Task 3: Rewrite SettingsNav (Horizontal Tabs)

**Files:**
- Modify: `src/components/settings/settings-nav.tsx`

- [ ] **Step 1: Rewrite settings-nav.tsx from vertical sidebar to horizontal tabs**

```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

interface SettingsNavProps {
  slug: string;
}

const TABS = [
  { label: "Overview", href: (slug: string) => `/${slug}/settings` },
  { label: "Projects", href: (slug: string) => `/${slug}/settings/projects` },
  { label: "Members", href: (slug: string) => `/${slug}/settings/members` },
  { label: "API Keys", href: (slug: string) => `/${slug}/settings/api-keys` },
  { label: "General", href: (slug: string) => `/${slug}/settings/general` },
];

export function SettingsNav({ slug }: SettingsNavProps) {
  const pathname = usePathname();

  return (
    <nav className="flex overflow-x-auto border-b px-6">
      {TABS.map((tab) => {
        const href = tab.href(slug);
        // Overview: exact match only (must not match /settings/general etc.)
        // Other tabs: startsWith match
        const isActive =
          href === `/${slug}/settings`
            ? pathname === href
            : pathname.startsWith(href);

        return (
          <Link
            key={tab.label}
            href={href}
            className={cn(
              "shrink-0 border-b-2 px-4 py-2.5 text-sm font-medium transition-colors",
              isActive
                ? "border-primary text-foreground"
                : "border-transparent text-muted-foreground hover:text-foreground"
            )}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/board/src/components/settings/settings-nav.tsx
git commit -m "feat(board): rewrite SettingsNav as horizontal tab bar"
```

---

### Task 4: Rewrite Settings Layout

**Files:**
- Modify: `src/app/[slug]/settings/layout.tsx`

- [ ] **Step 1: Rewrite layout with identity header + horizontal tabs**

```tsx
import { SettingsNav } from "@/components/settings/settings-nav";
import { WorkspaceIdentityHeader } from "@/components/settings/workspace-identity-header";

interface SettingsLayoutProps {
  children: React.ReactNode;
  params: Promise<{ slug: string }>;
}

export default async function SettingsLayout({
  children,
  params,
}: SettingsLayoutProps) {
  const { slug } = await params;

  return (
    <div className="flex flex-1 flex-col overflow-hidden">
      <WorkspaceIdentityHeader />
      <SettingsNav slug={slug} />
      <div className="flex-1 overflow-auto">
        <div className="mx-auto w-full max-w-5xl px-6 py-6">
          {children}
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/board/src/app/\\[slug\\]/settings/layout.tsx
git commit -m "feat(board): rewrite settings layout with identity header and horizontal tabs"
```

---

### Task 5: Move General to Sub-Route

**Files:**
- Create: `src/app/[slug]/settings/general/page.tsx`
- Modify: `src/app/[slug]/settings/page.tsx` (will be fully rewritten in Task 7)

- [ ] **Step 1: Create general/page.tsx**

```tsx
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SettingsGeneral } from "@/components/settings/settings-general";

export default async function GeneralSettingsPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const supabase = await createClient();

  const { data: workspace } = await supabase
    .from("workspaces")
    .select("*")
    .eq("slug", slug)
    .single();

  if (!workspace) redirect("/");

  return <SettingsGeneral workspace={workspace} />;
}
```

- [ ] **Step 2: Verify the route works**

Run: `npm run dev` and navigate to `/{slug}/settings/general` — should show the workspace name + slug cards.

- [ ] **Step 3: Commit**

```bash
git add apps/board/src/app/\\[slug\\]/settings/general/page.tsx
git commit -m "feat(board): add /settings/general route for workspace name/slug editing"
```

---

## Chunk 2: Overview Page

### Task 6: SettingsOverview Component

**Files:**
- Create: `src/components/settings/settings-overview.tsx`

- [ ] **Step 1: Create SettingsOverview component**

This is a client component that receives pre-fetched data and renders the dashboard.

```tsx
"use client";

import Link from "next/link";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useWorkspace } from "@/lib/workspace-context";
import type { Project, WorkspaceMember, Ticket } from "@/lib/types";

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
```

- [ ] **Step 2: Commit**

```bash
git add apps/board/src/components/settings/settings-overview.tsx
git commit -m "feat(board): add SettingsOverview dashboard component"
```

---

### Task 7: Rewrite Settings Page (Overview Data Fetching)

**Files:**
- Modify: `src/app/[slug]/settings/page.tsx`

- [ ] **Step 1: Rewrite page.tsx as Overview with data fetching**

```tsx
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

  // All queries in parallel
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
```

- [ ] **Step 2: Verify the overview page renders**

Run: `npm run dev` and navigate to `/{slug}/settings` — should show the full overview dashboard.

- [ ] **Step 3: Commit**

```bash
git add apps/board/src/app/\\[slug\\]/settings/page.tsx
git commit -m "feat(board): rewrite /settings as Overview dashboard with stats and activity feed"
```

---

### Task 8: Loading State

**Files:**
- Create: `src/app/[slug]/settings/loading.tsx`

- [ ] **Step 1: Create loading skeleton**

```tsx
import { Card, CardContent, CardHeader } from "@/components/ui/card";

function Skeleton({ className }: { className?: string }) {
  return (
    <div className={`animate-pulse rounded-md bg-muted ${className ?? ""}`} />
  );
}

export default function SettingsLoading() {
  return (
    <div className="flex flex-col gap-6">
      {/* Stats skeleton */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Card key={i}>
            <CardContent className="p-4">
              <Skeleton className="h-3 w-16 mb-2" />
              <Skeleton className="h-7 w-10" />
            </CardContent>
          </Card>
        ))}
      </div>
      {/* Two-column skeleton */}
      <div className="grid gap-4 md:grid-cols-2">
        {Array.from({ length: 2 }).map((_, i) => (
          <Card key={i}>
            <CardHeader className="pb-3">
              <Skeleton className="h-4 w-24" />
            </CardHeader>
            <CardContent className="flex flex-col gap-2">
              {Array.from({ length: 3 }).map((_, j) => (
                <Skeleton key={j} className="h-12 w-full" />
              ))}
            </CardContent>
          </Card>
        ))}
      </div>
      {/* Activity skeleton */}
      <Card>
        <CardHeader className="pb-3">
          <Skeleton className="h-4 w-28" />
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-8 w-full" />
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/board/src/app/\\[slug\\]/settings/loading.tsx
git commit -m "feat(board): add loading skeleton for settings overview"
```

---

### Task 9: Build Verification & Final Commit

- [ ] **Step 1: Run the build**

```bash
cd apps/board && npm run build
```

Expected: Build succeeds with no errors.

- [ ] **Step 2: Fix any build errors if needed**

- [ ] **Step 3: Manual verification checklist**

Run `npm run dev` and verify:
- `/{slug}/settings` → Shows Overview with stats, projects, members, activity
- `/{slug}/settings/general` → Shows workspace name + slug edit forms
- `/{slug}/settings/projects` → Unchanged, still works
- `/{slug}/settings/members` → Unchanged, still works
- `/{slug}/settings/api-keys` → Unchanged, still works
- Identity header visible on all settings tabs (name, ID with copy, slug, created)
- Horizontal tabs: correct active states (Overview exact match, others startsWith)
- Copy button on Workspace ID works (copies full UUID, shows checkmark)
- Empty states render correctly if workspace has no projects/members/tickets
- Responsive: stats go 2-col on narrow viewport, projects/members stack

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A apps/board/src
git commit -m "fix(board): address build/runtime issues in settings overview"
```
