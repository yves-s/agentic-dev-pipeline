# Website CTO Sections Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three new sections to the just-ship landing page — differentiation ("Every project. From scratch?"), messenger bento card, and "Built with just-ship" showcase — to prepare for CTO review.

**Architecture:** Three new React components following the existing pattern (exported function components with Tailwind classes, matching the established design system). Each component is a self-contained section. The messenger card is a new row in the existing Features bento grid. Page order updates in `page.tsx`.

**Tech Stack:** Next.js 16, React 19, Tailwind CSS v4, Sora + JetBrains Mono fonts

**Mockup:** `apps/web/mockup-new-sections.html` — approved reference for all visual decisions

---

## Chunk 1: Three New Sections

### Task 1: Create Differentiation Section Component

**Files:**
- Create: `apps/web/src/components/differentiation.tsx`

- [ ] **Step 1: Create the component file**

Create `apps/web/src/components/differentiation.tsx` with the full "Every project. From scratch?" section. This is a two-column comparison layout:

- **Left column ("The usual setup"):** 5 numbered pain steps describing the typical AI tool setup journey (IDE → Notion MCP → build agents → create skills → no autonomous pipeline), ending with a red "Repeat for every new project." callout.
- **Right column ("With just-ship"):** 5 checkmark items (battle-tested agents, 17 proven skills, live board, autonomous pipeline, portable), ending with a blue `./setup.sh` callout.
- **Below both columns:** A row of competitor chips — Cursor/Windsurf (IDE), Devin (SaaS $500/mo), Claude Code (CLI, no workflow), just-ship (Framework, end-to-end autonomous). The just-ship chip is accent-highlighted.

Design tokens to match (from `globals.css`):
- Section bg: `bg-brand-950`, padding: `py-24 sm:py-32` (brand-950 is intentional here — visual break after HowItWorks which uses brand-900)
- Cards: `rounded-2xl border border-brand-800 bg-brand-900`
- Pain highlight: `text-danger` (#ef4444)
- Solution card: border `border-accent/30`, subtle gradient bg
- Solution checks: green `bg-success/10` circle with `text-success` checkmark
- Pain numbers: `rounded-lg bg-brand-800 text-brand-500`
- Grid: `grid grid-cols-1 gap-8 md:grid-cols-2`
- Typography: Section title `text-3xl sm:text-4xl font-bold text-white`, subtitle `text-brand-400`
- Competitor chips: `rounded-xl border border-brand-800 bg-brand-900 px-5 py-2.5 text-sm`

Reference the mockup HTML (`mockup-new-sections.html`) for exact copy and structure — the HTML section starts around line 494, CSS styles around line 108.

Export as `Differentiation`.

- [ ] **Step 2: Verify it builds**

Run: `cd apps/web && npx next build`
Expected: Build succeeds (static export)

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/differentiation.tsx
git commit -m "feat(web): add differentiation section — 'Every project. From scratch?'"
```

---

### Task 2: Add Messenger Card + Open Source Card to Features Bento Grid

**Files:**
- Modify: `apps/web/src/components/features.tsx`

- [ ] **Step 1: Add MessengerCell and OpenSourceCell components**

Add two new cell components inside `features.tsx`, following the existing pattern (private function components above the exported `Features` function):

**`MessengerCell`** (spans 2 cols — use `className="col-span-1 sm:col-span-2 ..."` like LiveBoardCell/VpsCell):
- Label: "Ship from anywhere" with a `Coming Soon` badge (small inline span, `bg-accent/10 text-accent text-[9px] uppercase font-bold px-1.5 py-0.5 rounded ml-2`)
- Headline: "Manage your dev flow by chat"
- Copy: "Write tickets, check status, approve PRs — from Telegram, Slack, or WhatsApp. Your entire dev workflow, wherever you are."
- Messenger icon row: Telegram (highlighted with `border-accent/30 text-accent`), Slack, WhatsApp, iMessage — styled as small chips on dark surface bg
- Chat demo section (on `#12141c` background): 4 messages simulating a Telegram conversation:
  1. User (avatar "Y", `bg-brand-800`): "Add dark mode support to the settings page"
  2. Bot (avatar "js", `bg-accent/15`): "T-324 created. Agents are on it." + "Preview ready in ~12 min" + preview URL `preview-t324.just-ship.dev` as mono accent link
  3. User: "Sieht gut aus, ship it"
  4. Bot: green dot + "Merged to main. T-324 done."
- Chat bubbles: user = `bg-brand-800 text-brand-200`, bot = `bg-accent/5 border border-accent/15 text-brand-300`

**`OpenSourceCell`** (1 col like CostRoutingCell):
- Label: "Open Source"
- Headline: "Your infra. Your data."
- Copy: "Self-hosted on your VPS. No vendor lock-in, no data leaving your infrastructure. Fork it, extend it, own it."
- Checklist section on dark surface bg: 4 items with green checkmarks — "MIT License", "Self-hosted pipeline", "No telemetry", "~$4-8/mo hosting"

- [ ] **Step 2: Add new row to the Features grid**

In the `Features` component's grid, add a new Row 4 comment block after the existing Row 3 (the three SmallCells):

```tsx
{/* Row 4 */}
<MessengerCell />
<OpenSourceCell />
```

- [ ] **Step 3: Verify it builds**

Run: `cd apps/web && npx next build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/features.tsx
git commit -m "feat(web): add messenger and open source bento cards to features grid"
```

---

### Task 3: Create Showcase Section Component

**Files:**
- Create: `apps/web/src/components/showcase.tsx`

- [ ] **Step 1: Create the component file**

Create `apps/web/src/components/showcase.tsx` with the "Built with just-ship" section:

- Section bg: `bg-brand-950 py-24 sm:py-32` (matches visual rhythm — Skills uses brand-900, QuickStart uses brand-900, so brand-950 creates contrast)
- Section title: "Built with just-ship"
- Subtitle: "Real products, shipping autonomously. Every PR reviewed by a human — built by agents."
- 4-column grid (`grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4`)

Four cards, each with: logo placeholder (colored gradient div with letter, `w-12 h-12 rounded-xl`), name, description, and a stat/meta row:

1. **Aime** — logo gradient purple-blue, letter "A"
   - Desc: "AI-powered productivity platform. Newsletter, entries, and more."
   - Stat: "300+" / "tickets shipped"

2. **19ELF** — logo gradient green, letters "19"
   - Desc: "Website built and maintained entirely through just-ship pipeline."
   - Stat: "100%" / "autonomous delivery"

3. **just-ship** — logo `bg-accent/10 text-accent`, triangle symbol
   - Desc: "This framework. Built, maintained, and evolved with itself."
   - Stat: "meta" / "self-improving"
   - Card has subtle accent border: `border-accent/20`

4. **& more** — logo gradient amber, "+" symbol
   - Desc: "Multiple client projects shipping daily with just-ship agents."
   - Meta: "90%+ success rate" / "tickets → PRs without intervention"

Card styling: `rounded-2xl border border-brand-800 bg-brand-900 p-8 text-center`
Stat divider: `border-t border-brand-800 mt-4 pt-4`
Stat number: `font-mono text-lg font-bold text-accent`
Stat label: `text-[11px] text-brand-600`

Export as `Showcase`.

- [ ] **Step 2: Verify it builds**

Run: `cd apps/web && npx next build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/showcase.tsx
git commit -m "feat(web): add 'Built with just-ship' showcase section"
```

---

### Task 4: Wire Sections into Page

**Files:**
- Modify: `apps/web/src/app/page.tsx`

- [ ] **Step 1: Add imports and update page order**

Add three new imports and reorder the sections:

```tsx
import { Hero } from "@/components/hero";
import { HowItWorks } from "@/components/how-it-works";
import { Differentiation } from "@/components/differentiation";
import { Agents } from "@/components/agents";
import { Commands } from "@/components/commands";
import { Features } from "@/components/features";
import { Skills } from "@/components/skills";
import { Showcase } from "@/components/showcase";
import { QuickStart } from "@/components/quick-start";
import { Footer } from "@/components/footer";

export default function Home() {
  return (
    <main>
      <Hero />
      <HowItWorks />
      <Differentiation />
      <Agents />
      <Commands />
      <Features />
      <Skills />
      <Showcase />
      <QuickStart />
      <Footer />
    </main>
  );
}
```

- [ ] **Step 2: Verify full build**

Run: `cd apps/web && npx next build`
Expected: Build succeeds, all pages generated

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/app/page.tsx
git commit -m "feat(web): wire differentiation, showcase sections into page layout"
```

---

### Task 5: Visual Verification & Cleanup

- [ ] **Step 1: Start dev server and verify all sections render**

Run: `cd apps/web && npx next dev`
Check: Open http://localhost:3001 (port 3001 per package.json dev script) and verify:
1. Differentiation section appears after How It Works
2. Messenger + Open Source cards appear as Row 4 in Bento
3. Showcase section appears before Quick Start
4. All sections match the approved mockup styling
5. Mobile responsive (grid collapses to single column)

- [ ] **Step 2: Delete the mockup file**

```bash
rm apps/web/mockup-new-sections.html
```

- [ ] **Step 3: Final build check**

Run: `cd apps/web && npx next build`
Expected: Clean build, no warnings

- [ ] **Step 4: Commit cleanup**

```bash
git rm apps/web/mockup-new-sections.html
git commit -m "chore(web): remove mockup file after implementation"
```
