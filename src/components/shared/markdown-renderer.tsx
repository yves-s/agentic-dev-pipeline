"use client";

import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { cn } from "@/lib/utils";

interface MarkdownRendererProps {
  content: string;
  className?: string;
}

export function MarkdownRenderer({ content, className }: MarkdownRendererProps) {
  return (
    <div
      className={cn(
        "max-w-none text-sm text-foreground leading-relaxed",
        // Headings
        "[&_h1]:text-lg [&_h1]:font-semibold [&_h1]:tracking-tight [&_h1]:mt-4 [&_h1]:mb-2",
        "[&_h2]:text-base [&_h2]:font-semibold [&_h2]:tracking-tight [&_h2]:mt-3 [&_h2]:mb-1.5",
        "[&_h3]:text-sm [&_h3]:font-semibold [&_h3]:tracking-tight [&_h3]:mt-2 [&_h3]:mb-1",
        // Paragraphs
        "[&_p]:my-1.5 [&_p]:leading-relaxed",
        // Lists
        "[&_ul]:my-1.5 [&_ul]:pl-5 [&_ul]:list-disc",
        "[&_ol]:my-1.5 [&_ol]:pl-5 [&_ol]:list-decimal",
        "[&_li]:my-0.5",
        "[&_li>ul]:my-0.5 [&_li>ol]:my-0.5",
        // Inline code
        "[&_:not(pre)>code]:rounded [&_:not(pre)>code]:bg-muted [&_:not(pre)>code]:px-1 [&_:not(pre)>code]:py-0.5 [&_:not(pre)>code]:text-xs [&_:not(pre)>code]:font-mono",
        // Code blocks
        "[&_pre]:bg-muted [&_pre]:rounded-md [&_pre]:p-3 [&_pre]:text-xs [&_pre]:overflow-x-auto [&_pre]:my-2",
        "[&_pre_code]:bg-transparent [&_pre_code]:p-0 [&_pre_code]:text-xs [&_pre_code]:font-mono",
        // Links
        "[&_a]:text-primary [&_a]:underline [&_a]:underline-offset-2",
        // Blockquotes
        "[&_blockquote]:border-l-2 [&_blockquote]:border-border [&_blockquote]:pl-3 [&_blockquote]:my-2 [&_blockquote]:text-muted-foreground [&_blockquote]:italic",
        // Horizontal rules
        "[&_hr]:my-3 [&_hr]:border-border",
        // Tables (GFM)
        "[&_table]:w-full [&_table]:my-2 [&_table]:text-xs [&_table]:border-collapse",
        "[&_th]:border [&_th]:border-border [&_th]:px-2 [&_th]:py-1 [&_th]:text-left [&_th]:font-semibold [&_th]:bg-muted/50",
        "[&_td]:border [&_td]:border-border [&_td]:px-2 [&_td]:py-1",
        // Checkboxes (GFM task lists)
        "[&_input[type=checkbox]]:mr-1.5 [&_input[type=checkbox]]:accent-primary",
        // Strong / emphasis
        "[&_strong]:font-semibold",
        "[&_em]:italic",
        className
      )}
    >
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
    </div>
  );
}
