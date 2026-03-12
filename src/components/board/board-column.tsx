"use client";

import { useDroppable } from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { TicketCard } from "./ticket-card";
import type { Ticket } from "@/lib/types";
import type { TicketStatus } from "@/lib/constants";

interface BoardColumnProps {
  status: TicketStatus;
  label: string;
  tickets: Ticket[];
  totalCount?: number;
  hasMore?: boolean;
  isLoadingMore?: boolean;
  onLoadMore?: () => void;
  onTicketClick: (ticket: Ticket) => void;
  isAgentActive?: (ticketId: string) => boolean;
  getAgentActivity?: (ticketId: string) => { agent_type: string; event_type: string } | null;
  onAddTicket?: (status: TicketStatus, projectId: string | null) => void;
}

const COLUMN_DOT: Record<TicketStatus, string> = {
  backlog: "bg-slate-400",
  ready_to_develop: "bg-sky-500",
  in_progress: "bg-amber-500",
  in_review: "bg-violet-500",
  done: "bg-emerald-500",
  cancelled: "bg-red-400",
};

const COLUMN_HEADER_BG: Record<TicketStatus, string> = {
  backlog: "bg-slate-100",
  ready_to_develop: "bg-sky-100",
  in_progress: "bg-amber-100",
  in_review: "bg-violet-100",
  done: "bg-emerald-100",
  cancelled: "bg-red-100",
};

const COLUMN_BG: Record<TicketStatus, string> = {
  backlog: "bg-slate-50",
  ready_to_develop: "bg-sky-50",
  in_progress: "bg-amber-50",
  in_review: "bg-violet-50",
  done: "bg-emerald-50",
  cancelled: "bg-red-50",
};

export function BoardColumn({
  status,
  label,
  tickets,
  totalCount,
  hasMore,
  isLoadingMore,
  onLoadMore,
  onTicketClick,
  isAgentActive,
  getAgentActivity,
  onAddTicket,
}: BoardColumnProps) {
  const { setNodeRef, isOver } = useDroppable({ id: status });
  const displayCount = totalCount ?? tickets.length;

  return (
    <div className="flex w-72 shrink-0 flex-col gap-3">
      {/* Column header */}
      <div className="flex items-center gap-2 px-1">
        <div
          className={cn(
            "flex items-center gap-1.5 rounded-full px-2.5 py-0.5",
            COLUMN_HEADER_BG[status] ?? "bg-slate-100"
          )}
        >
          <span
            className={cn(
              "h-2 w-2 rounded-full shrink-0",
              COLUMN_DOT[status] ?? "bg-slate-400"
            )}
          />
          <span className="text-sm font-medium">{label}</span>
        </div>
        <span className="ml-auto rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground font-medium">
          {displayCount}
        </span>
      </div>

      {/* Drop zone */}
      <div
        ref={setNodeRef}
        className={cn(
          "flex flex-1 flex-col gap-2 rounded-xl p-2 min-h-[200px] overflow-y-auto transition-colors",
          isOver
            ? "bg-primary/5 ring-1 ring-primary/20"
            : COLUMN_BG[status] ?? "bg-muted/50"
        )}
      >
        <SortableContext items={tickets.map((t) => t.id)} strategy={verticalListSortingStrategy}>
          {tickets.map((ticket) => (
            <TicketCard
              key={ticket.id}
              ticket={ticket}
              onClick={onTicketClick}
              agentActive={isAgentActive?.(ticket.id) ?? false}
              agentActivity={getAgentActivity?.(ticket.id) ?? null}
            />
          ))}
        </SortableContext>

        {hasMore && (
          <button
            type="button"
            onClick={onLoadMore}
            disabled={isLoadingMore}
            className="mt-1 flex items-center justify-center gap-1.5 rounded-lg py-2 text-xs font-medium text-muted-foreground hover:text-foreground hover:bg-muted/80 transition-colors disabled:opacity-50"
          >
            {isLoadingMore ? (
              <>
                <Loader2 className="h-3 w-3 animate-spin" />
                Laden…
              </>
            ) : (
              `Mehr Tickets laden (${tickets.length}/${displayCount})`
            )}
          </button>
        )}
      </div>
    </div>
  );
}
