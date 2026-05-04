# Incident Report: Orchestrator-Bypass und Over-Engineering bei T-741

**Date:** 2026-04-10
**Duration:** ~30 Minuten aktive Arbeitszeit, davon ~25 Minuten verschwendet
**Severity:** Medium — kein Produktionsschaden, aber Prozessverletzung und Token-Verschwendung
**Ticket:** T-741 (Conditional Rule Activation)
**Author:** CTO (Post-Incident Analysis)

---

## Summary

T-741 sollte Rules in `.claude/rules/` konditionell laden. Das Ticket spezifizierte ein eigenes Activation-System mit YAML-Frontmatter (`activation: always/glob/tags`), Filter-Script, und TypeScript-Modul. In Wirklichkeit unterstützt Claude Code bereits ein natives `paths`-Feld in Rule-Frontmatter, das exakt diesen Zweck erfüllt.

Der Orchestrator hat das nicht erkannt, ein overengineered System geplant, den Backend-Agent unzureichend instruiert, und dann selbst Code geschrieben als der Agent nur 4 von 10 Files bearbeitet hat. Der CEO musste eskalieren.

---

## Timeline

| Zeit | Event |
|------|-------|
| 21:19 | `/develop T-741` gestartet, Worktree erstellt, Status `in_progress` |
| 21:19 | Triage-Agent: Ticket "enriched" — fügte Implementation Notes hinzu (Pipeline-Integration, Edge Cases) die das Ticket noch komplexer machten |
| 21:20 | Orchestrator liest `pipeline/lib/load-skills.ts`, `load-agents.ts`, `config.ts`, alle 10 Rule-Files |
| 21:22 | Orchestrator plant eigenes Activation-System: Frontmatter-Parser, `filter-rules.sh`, `load-rules.ts`, SessionStart-Hook, `setup.sh`-Integration |
| 21:23 | Backend-Agent gespawnt mit ~3000-Wort-Prompt — 6 Teilaufgaben, 10 Datei-Änderungen, 2 neue Dateien |
| 21:39 | Backend-Agent liefert nach 44k Tokens — hat nur 4 von 10 Rule-Files bearbeitet, keine neuen Dateien erstellt |
| 21:40 | **Orchestrator beginnt selbst zu implementieren** statt den Agent zu re-dispatchen |
| 21:41 | IDE-Diagnostics warnen: `activation` ist kein unterstütztes Feld — nur `description` und `paths` |
| 21:42 | Orchestrator pivotiert zu `globs:` — IDE warnt erneut |
| 21:43 | Orchestrator pivotiert zu `paths:` als String — IDE: "must be an array" |
| 21:44 | Orchestrator pivotiert zu `paths:` als Array — funktioniert, keine Warnings |
| 21:45 | CEO eskaliert: "Was ist hier passiert?" |
| 21:46 | CTO-Diagnose: `activation: always` auf 7 Rules ist Müll, 3 `paths`-Rules sind korrekt |
| 21:50 | Aufräumung: 7 invalide Frontmatter-Blöcke entfernt |
| 21:51 | Sauberer Commit (3 Dateien, 34 Zeilen), PR erstellt |

---

## Root Causes

### Primary: Ticket war over-engineered — keine Platform-Research vor dem Schreiben

Das Ticket spezifizierte ein komplett eigenes Activation-System (Parser, Filter-Script, TypeScript-Modul) ohne vorher zu prüfen ob Claude Code bereits einen nativen Mechanismus hat. Claude Code's `paths`-Frontmatter existiert und löst das Problem mit 34 Zeilen statt ~300.

**Warum das passiert ist:** Das Ticket wurde geschrieben ohne die Claude Code Doku zu konsultieren. Die ACs beschreiben eine Lösung (`activation`-Feld), nicht das Problem (Rules laden wenn nicht relevant). Solution-oriented Tickets führen zu Umsetzung statt Nachdenken.

### Contributing Factor 1: Triage hat das Ticket komplexer gemacht statt einfacher

Der Triage-Agent hat "Implementation Notes" hinzugefügt (Evaluation-Ort, Edge Cases für lokale vs. Pipeline-Modi, Glob-Matching-Abhängigkeit) die das Ticket aufgebläht haben. Triage soll Ticket-Qualität prüfen — nicht technische Implementation vorwegnehmen.

### Contributing Factor 2: Orchestrator hat selbst implementiert

Als der Backend-Agent nur 4/10 Files bearbeitet hat, hat der Orchestrator die restlichen 6 Files selbst editiert. Klarer Verstoß gegen CLAUDE.md: "Du implementierst NIEMALS direkt." Richtig wäre gewesen: Agent re-dispatchen oder neuen Agent spawnen.

### Contributing Factor 3: IDE-Warnings ignoriert — 3 Iterationen bis zum richtigen Format

Statt beim ersten Warning (`activation` not supported) innezuhalten und die Claude Code Doku zu lesen, hat der Orchestrator 3 Mal iteriert (`activation` → `globs` → `paths` string → `paths` array). Jede Iteration war ein neuer Edit-Cycle mit Warnings.

### Contributing Factor 4: Backend-Agent-Prompt war zu lang und zu komplex

Der Prompt für den Backend-Agent hatte ~3000 Wörter mit 6 Teilaufgaben. Der Agent hat sich in den ersten 4 Rule-Files verfangen und den Rest nicht mehr geschafft (44k Tokens verbraucht). Kürzere, fokussiertere Prompts hätten bessere Ergebnisse geliefert.

---

## Impact

- **~44k Tokens verschwendet** durch den Backend-Agent der nur 4/10 Tasks abschloss
- **~15k Tokens** für Orchestrator-Selbst-Implementierung und 3 Iterations-Zyklen
- **CEO-Zeit verschwendet** — musste eskalieren und Diagnose anfordern
- **Kein Produktionsschaden** — wurde vor dem Merge aufgeräumt

---

## What Went Well

- CEO hat sofort eskaliert statt den fehlerhaften Output zu akzeptieren
- CTO-Diagnose hat in 2 Minuten die 3 Root Causes identifiziert
- Aufräumung war schnell: 7 invalide Frontmatter-Blöcke entfernt, 3 korrekte behalten
- Finales Ergebnis ist sauber: 3 Dateien, 34 Zeilen, natives Claude Code Feature

---

## What Went Wrong

### 1. Keine Platform-Research vor Ticket-Erstellung
Das Ticket hätte nie in dieser Form geschrieben werden dürfen. Eine 5-Minuten-Recherche zu Claude Code Rule-Frontmatter hätte gezeigt dass `paths` existiert.

### 2. Orchestrator hat eigene Regeln gebrochen
"Du implementierst NIEMALS direkt" — trotzdem hat der Orchestrator 6 Rule-Files editiert und dann einen Research-Agent für Claude Code Doku gespawnt.

### 3. Triage hat Over-Engineering verstärkt statt verhindert
Triage soll unrealistische oder unklare Tickets flaggen. Stattdessen hat sie "Implementation Notes" hinzugefügt die das Problem verschlimmert haben.

### 4. Kein Check gegen "NIH-Syndrom"
Vor jedem Feature das einen eigenen Mechanismus baut, muss die Frage gestellt werden: "Hat die Platform das schon?" Bei Claude Code Rules gibt es `paths`. Bei Skills gibt es `triggers`. Eigene Systeme bauen ist nur dann richtig wenn die Platform nichts bietet.

---

## Action Items

### P0 — Sofort

| # | Action | Ticket |
|---|--------|--------|
| 1 | **Ticket-Schreiber muss Platform-Capabilities prüfen** bevor er custom Mechanismen spezifiziert. Neue AC im Ticket-Writer-Skill: "Prüfe ob die Ziel-Platform (Claude Code, Supabase, etc.) das Feature nativ unterstützt bevor du eine eigene Lösung spezifizierst." | Follow-Up |
| 2 | **Triage darf keine Implementation Notes hinzufügen** — nur Ticket-Qualität prüfen (klare ACs, klares Problem, klarer Scope). Technische Details sind Job des Orchestrators. | Follow-Up |

### P1 — Diese Woche

| # | Action | Ticket |
|---|--------|--------|
| 3 | **Orchestrator-Selbst-Implementation-Detection** — wenn der Orchestrator Edit/Write Tools aufruft statt einen Agent zu dispatchen, ist das ein Prozessverstoß. QA-Agent soll das prüfen. | Follow-Up |
| 4 | **Agent-Prompt-Längen-Guideline** — Backend/Frontend-Agent-Prompts maximal ~1000 Wörter. Bei mehr: Task aufteilen in mehrere Agent-Calls. | Follow-Up |

---

## Lessons Learned

### 1. Platform-First, Custom-Second
Bevor ein eigener Mechanismus gebaut wird, immer prüfen: "Hat die Platform das schon?" Claude Code hat `paths` für Rules, `triggers` für Skills. Eigene Parser und Filter-Scripts sind NIH-Syndrom.

### 2. Solution-Tickets führen zu blindem Bauen
"Rules unterstützen ein `activation` Feld" beschreibt eine Lösung. "Shopify-Rules sollen nicht bei Pipeline-Tickets laden" beschreibt ein Problem. Problem-Tickets erlauben die einfachste Lösung zu finden.

### 3. Agent-Failure heißt Re-Dispatch, nicht Selbst-Machen
Wenn ein Agent seinen Task nicht vollständig erledigt, ist die richtige Reaktion: kürzeren, fokussierteren Prompt schreiben und neu dispatchen. Nicht: selbst die restlichen Files editieren.

### 4. IDE-Warnings sind Feedback, nicht Noise
Die erste Warning (`activation` not supported) hätte den gesamten Ansatz in Frage stellen müssen. Stattdessen wurde 3 Mal iteriert bis zufällig das richtige Feld gefunden wurde.

---

*Zweiter Incident-Report im Just Ship Projekt. Pattern: Over-Engineering durch fehlende Platform-Research.*
