"use client";

import { Bot, CheckCircle2, XCircle, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import type { ActiveAgent } from "@/lib/hooks/use-agent-activity";
import type { Ticket } from "@/lib/types";

interface AgentPanelProps {
  activeAgents: ActiveAgent[];
  tickets: Ticket[];
  onTicketClick: (ticket: Ticket) => void;
}

const STATUS_CONFIG = {
  running: {
    Icon: Loader2,
    className: "text-amber-500 animate-spin",
  },
  completed: {
    Icon: CheckCircle2,
    className: "text-emerald-500",
  },
  failed: {
    Icon: XCircle,
    className: "text-red-500",
  },
} as const;

const AGENT_TYPE_COLOR: Record<string, string> = {
  frontend: "bg-violet-100 text-violet-700",
  backend: "bg-sky-100 text-sky-700",
  qa: "bg-emerald-100 text-emerald-700",
  devops: "bg-orange-100 text-orange-700",
  "data-engineer": "bg-amber-100 text-amber-700",
  security: "bg-red-100 text-red-700",
  orchestrator: "bg-indigo-100 text-indigo-700",
  plan: "bg-purple-100 text-purple-700",
};

export function AgentPanel({
  activeAgents,
  tickets,
  onTicketClick,
}: AgentPanelProps) {
  if (activeAgents.length === 0) return null;

  return (
    <div className="border-b bg-muted/20 px-6 py-2.5">
      <div className="flex items-center gap-3 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        <div className="flex items-center gap-1.5 shrink-0 text-[11px] font-medium text-muted-foreground">
          <Bot className="h-3.5 w-3.5" />
          <span>Agents</span>
          <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-amber-500 px-1 text-[9px] font-bold text-white">
            {activeAgents.length}
          </span>
        </div>

        <div className="w-px h-4 bg-border shrink-0" />

        <div className="flex items-center gap-2">
          {activeAgents.map((agent) => {
            const ticket = tickets.find((t) => t.id === agent.ticket_id);
            const { Icon, className } = STATUS_CONFIG[agent.status];
            const typeColor =
              AGENT_TYPE_COLOR[agent.agent_type.toLowerCase()] ??
              "bg-slate-100 text-slate-600";

            return (
              <button
                key={`${agent.ticket_id}-${agent.agent_type}`}
                onClick={() => ticket && onTicketClick(ticket)}
                disabled={!ticket}
                className={cn(
                  "flex items-center gap-1.5 rounded-full border bg-white px-2.5 py-1 text-[11px] shrink-0",
                  "transition-shadow hover:shadow-sm",
                  ticket ? "cursor-pointer" : "cursor-default opacity-70"
                )}
              >
                <span
                  className={cn(
                    "rounded-full px-1.5 py-0 text-[10px] font-semibold leading-4",
                    typeColor
                  )}
                >
                  {agent.agent_type}
                </span>
                {ticket && (
                  <span className="font-mono text-muted-foreground">
                    T-{ticket.number}
                  </span>
                )}
                <Icon className={cn("h-3 w-3 shrink-0", className)} />
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
