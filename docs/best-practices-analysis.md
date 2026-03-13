# Best Practices Analyse: shanraisshan/claude-code-best-practice

**Datum:** 2026-03-13
**Quelle:** [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) (14.9k Stars, Claude Code v2.1.74)
**Scope:** Entscheidungs-Dokument — keine Implementierung

---

## Zusammenfassung

Das Repository dokumentiert 14 Agent-Frontmatter-Felder, 10 Skills-Frontmatter-Felder, 55+ Settings und bewährte Workflow-Patterns. Unser Framework nutzt bereits einen soliden Kern dieser Features — einige wichtige Optimierungen werden aber noch nicht ausgeschöpft.

**Sofort adaptieren:** 7 Punkte
**Später:** 7 Punkte
**Nicht relevant:** 5 Punkte

---

## 1. Agent-Frontmatter-Features

Vollständige Tabelle der 14 Felder. Felder in **Fett** nutzen wir bereits.

| Feld | Wir nutzen | Bewertung | Aufwand |
|---|---|---|---|
| **`name`** | ✅ | — | — |
| **`description`** | ✅ | — | — |
| **`tools`** | ✅ | — | — |
| **`model`** | ✅ | — | — |
| **`permissionMode`** | ✅ (orchestrator) | — | — |
| **`skills`** | ✅ (backend, frontend, qa) | — | — |
| `color` | ❌ | Sofort adaptieren | XS |
| `maxTurns` | ❌ | Sofort adaptieren | XS |
| `memory` | ❌ | Später | M |
| `isolation: "worktree"` | ❌ | Später | L |
| `background` | ❌ | Nicht relevant | — |
| `hooks` (scoped) | ❌ | Nicht relevant | — |
| `mcpServers` | ❌ | Nicht relevant | — |
| `disallowedTools` | ❌ | Nicht relevant | — |

### 1.1 `color` — CLI-Farbkodierung

**Bewertung: Sofort adaptieren**

Visuelles Unterscheiden von Agents im CLI-Output. Ohne extra Logik — nur ein Frontmatter-Feld.

**Vorschlag für unsere Agents:**

| Agent | Farbe | Begründung |
|---|---|---|
| orchestrator | `blue` | Haupt-Controller |
| backend | `cyan` | API/Logic |
| frontend | `magenta` | UI |
| data-engineer | `yellow` | DB/Schema |
| devops | `red` | Build/CI |
| qa | `green` | Qualität/Pass |
| security | `orange` | Sicherheit |

**Aufwand:** 7 Zeilen hinzufügen — eine pro Agent-Datei.

---

### 1.2 `maxTurns` — Max. Agentic Turns

**Bewertung: Sofort adaptieren**

Sicherheitsnetz: Verhindert endlos laufende Agents bei Schleifen oder unerwartetem Verhalten. Besonders wichtig für routine Agents, die klar begrenzte Aufgaben haben.

**Vorschlag:**

| Agent | `maxTurns` | Begründung |
|---|---|---|
| orchestrator | nicht setzen | Komplexe Flows, variabel |
| data-engineer | `20` | SQL-Migrations sind begrenzt |
| devops | `15` | Build-Fix ist begrenzt |
| security | `15` | Security-Review ist begrenzt |
| qa | `20` | Review + Fix-Schleife |
| backend | nicht setzen | Business Logic variiert |
| frontend | nicht setzen | UI-Arbeit variiert |

**Aufwand:** XS — Frontmatter-Ergänzung.

---

### 1.3 `memory` — Persistenter Agent-Kontext

**Bewertung: Später**

Agents können eigene MEMORY.md-Dateien pflegen (Scope: `user`, `project`, `local`). Erste 200 Zeilen werden automatisch in den Kontext injiziert.

**Potenzial für unser Framework:**
- `orchestrator` mit `memory: project` → könnte wiederkehrende Architekturentscheidungen, Projektmuster und wiederholt auftretende Bugs merken
- `qa` mit `memory: project` → könnte Testmuster und häufige Fehlerklassen festhalten

**Risiken:**
- Stale Context: Memory kann veralten und zu falschen Annahmen führen
- Divergenz von Code-Realität: MEMORY.md spiegelt Meinungen wider, nicht Ground Truth
- Wartungsaufwand: Agents müssen Memory aktiv kuratieren

**Voraussetzung:** Klare Memory-Governance (was wird gespeichert, wann wird gelöscht).

**Aufwand:** M — Frontmatter + Memory-Guidelines pro Agent.

---

### 1.4 `isolation: "worktree"` — Git-Worktree-Isolation

**Bewertung: Später**

Läuft den Agent in einem temporären Git-Worktree. Automatisches Cleanup wenn keine Änderungen gemacht werden. Ermöglicht parallele Agent-Ausführung ohne Branch-Konflikte.

**Potenzial:** Mehrere Feature-Agents parallel auf verschiedenen Tickets — jeder in eigenem Worktree. Das wäre ein massiver Throughput-Gewinn für die Pipeline.

**Voraussetzung:**
- Pipeline muss mehrere Tickets parallel verarbeiten können (aktuell: sequenziell)
- Worker-Architektur muss angepasst werden
- Merge-Strategie für parallele Branches muss geklärt sein

**Aufwand:** L — Architekturänderung im Worker + Pipeline-SDK.

---

### 1.5 `background: true` — Hintergrund-Ausführung

**Bewertung: Nicht relevant**

Agents laufen permanent im Hintergrund. Unser SDK-Pipeline-System steuert bereits die Ausführung — ein `background: true`-Flag würde das SDK-Controlling umgehen und Konflikte erzeugen.

---

### 1.6 Scoped `hooks` in Agents

**Bewertung: Nicht relevant**

Scoped Hooks ermöglichen agent-spezifische Lifecycle-Events. Das Referenz-Repo nutzt dies für ElevenLabs TTS-Feedback (explizit out of scope). Unser bestehendes Event-System via `send-event.sh` und globale SubagentStart/Stop-Hooks deckt unsere Anforderungen vollständig ab.

---

## 2. Skills-Frontmatter-Features

| Feld | Wir nutzen | Bewertung | Aufwand |
|---|---|---|---|
| **`name`** | ✅ | — | — |
| **`description`** | ✅ | — | — |
| **`allowed-tools`** | ✅ (ticket-writer) | — | — |
| `user-invocable: false` | ❌ | Sofort adaptieren | XS |
| `model` | ❌ | Später | XS |
| `context: fork` | ❌ | Später | S |
| `argument-hint` | ❌ | Später | XS |
| `hooks` | ❌ | Nicht relevant | — |
| `disable-model-invocation` | ❌ | Nicht relevant | — |
| `agent` | ❌ | Nicht relevant | — |

### 2.1 `user-invocable: false` — Reine Agent-Preload-Skills

**Bewertung: Sofort adaptieren**

Versteckt Skills aus dem `/`-Menü, die ausschließlich für Agent-Preloading bestimmt sind (nicht für direkte User-Invocation).

**Betroffene Skills in unserem Framework:**

| Skill | Aktuell | Empfehlung |
|---|---|---|
| `backend.md` | Erscheint im `/` Menü | `user-invocable: false` — wird nur von backend-Agent preloaded |
| `frontend-design.md` | Erscheint im `/` Menü | `user-invocable: false` — wird von frontend-Agent preloaded |
| `design.md` | Erscheint im `/` Menü | `user-invocable: false` |
| `creative-design.md` | Erscheint im `/` Menü | `user-invocable: false` |
| `webapp-testing.md` | Erscheint im `/` Menü | `user-invocable: false` — wird von qa-Agent preloaded |
| `data-engineer.md` | Erscheint im `/` Menü | `user-invocable: false` |
| `ticket-writer.md` | Erscheint im `/` Menü | Bleibt `user-invocable: true` (via `/ticket`) |
| `ux-planning.md` | Erscheint im `/` Menü | Prüfen ob User-invocable sinnvoll |

**Aufwand:** XS — eine Zeile pro Skill-Datei ergänzen.

---

### 2.2 `model`-Override in Skills

**Bewertung: Später**

Skills können ein bestimmtes Modell erzwingen. Nützlich für teure Analyse-Skills, die explizit Opus benötigen, oder für Performance-Skills die Haiku reicht.

**Potenzielle Kandidaten:**
- Schwere Analyse-Skills (Architectural Review) → Opus
- Schnelle Checklisten-Skills → Haiku

**Aufwand:** XS — aber zuerst klären ob wir solche Skills haben/planen.

---

### 2.3 `context: fork` — Isolierter Skill-Subagent

**Bewertung: Später**

Läuft den Skill in einem isolierten Subagent-Kontext statt inline im Haupt-Conversation-Kontext. Verhindert Kontext-Pollution durch schwere Skills.

**Kandidat:** `ticket-writer.md` ist ein inhaltsschwerer Skill — er liest viele Dateien, führt Supabase-Queries aus, fragt interaktiv nach. Mit `context: fork` wäre das sauber isoliert.

**Aufwand:** S — Frontmatter + testen ob das Verhalten identisch bleibt.

---

## 3. Settings-Optimierungen

| Setting | Wir nutzen | Bewertung | Aufwand |
|---|---|---|---|
| `permissions.allow` | ✅ | — | — |
| `hooks` (global) | ✅ | — | — |
| `env` Feld | ❌ | Sofort adaptieren | XS |
| `alwaysThinkingEnabled` | ❌ | Später | XS |
| `agent` Default | ❌ | Nicht relevant | — |
| `teammateMode` | ❌ | Nicht relevant | — |

### 3.1 `env` Feld — Umgebungsvariablen in settings.json

**Bewertung: Sofort adaptieren**

Statt Wrapper-Scripts können Umgebungsvariablen direkt in `.claude/settings.json` gesetzt werden.

**Sofort nützlich:**

```json
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80"
  }
}
```

`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "80"` — triggert Auto-Kompaktierung bei 80% Context-Nutzung (Default: ~95%). Verhindert Context-Overflows bei langen Pipeline-Runs.

Weitere nützliche Variablen:
- `CLAUDE_CODE_SUBAGENT_MODEL` — Override-Modell für alle Subagents (z.B. `haiku` für alle Routine-Agents)

**Aufwand:** XS — 3 Zeilen in settings.json.

---

### 3.2 `alwaysThinkingEnabled` — Extended Thinking global

**Bewertung: Später**

Aktiviert Extended Thinking für alle Sessions standardmäßig. Boris Cherny's persönliche Einstellung.

**Abwägung:**
- ✅ Bessere Entscheidungen bei komplexen Aufgaben (Orchestrator, Backend)
- ❌ Höhere Kosten — Extended Thinking ist teurer
- ❌ Langsamere Responses für Routine-Tasks (DevOps, QA)

**Empfehlung:** Erst evaluieren wenn klarer ist, bei welchen Agents Extended Thinking messbar hilft.

---

### 3.3 `agent` Default und `teammateMode`

**Bewertung: Nicht relevant**

- `agent` Default: Wir verwenden Commands (`/develop`, `/ship`) als Entry Points — kein Default-Agent nötig
- `teammateMode: "tmux"`: Experimentelles Feature, unser Pipeline-System ist ausgereifter als diese UI-Variante

---

## 4. Workflow-Patterns

### 4.1 Command → Agent → Skill Architektur

**Bewertung: Bereits implementiert ✅**

Unser Framework folgt bereits diesem Pattern:
- `/develop` (Command) → orchestrator-Agent → Skills preloaded (backend, frontend, etc.)
- `/ticket` (Command) → ticket-writer Skill (inline)

**Was noch fehlt:** Explizite Dokumentation des Auto-Invocation Resolution Order:
1. Skill (kein Context-Overhead) — bevorzugt
2. Agent (separater Context)
3. Command (niemals auto-invoked)

**Empfehlung:** In CLAUDE.md und agents/orchestrator.md dokumentieren wann welcher Mechanismus genutzt werden soll.

---

### 4.2 Plan Mode für komplexe Tasks

**Bewertung: Sofort adaptieren (Dokumentation)**

Plan Mode (Shift+Tab zweimal) vor der Implementierung: "Investiere Energie in den Plan, damit Claude die Implementierung in einem einzigen Durchgang erledigen kann."

**Pattern aus Boris Cherny's Tips:**
- Eine Claude-Session schreibt den Plan
- Zweite Claude-Session reviewt ihn als Staff Engineer
- Bei Problemen: zurück in Plan Mode, neu planen statt weiter pushen

**Für unser Framework relevant:** Dieses Pattern sollte in CLAUDE.md als Empfehlung für interaktive Entwicklung stehen — unser autonomer Pipeline-Flow nutzt intern schon Planung, aber für manuelle Sessions ist es nicht dokumentiert.

**Aufwand:** XS — Ergänzung in CLAUDE.md (2-3 Zeilen).

---

### 4.3 Parallel Worktrees Strategie

**Bewertung: Später**

"Der einzelne größte Produktivitäts-Unlock" laut Claude Code Team (Feb 2026): 3-5 Git-Worktrees gleichzeitig, jeder mit eigener Claude-Session.

**Für unser Pipeline-Framework:** Kombination mit `isolation: "worktree"` im Agent-Frontmatter würde parallele Ticket-Verarbeitung ermöglichen. Momentan läuft die Pipeline sequenziell.

**Aufwand:** L — Pipeline-Architekturänderung (Worker + SDK).

---

## 5. CLAUDE.md Best Practices

### 5.1 200-Zeilen-Limit pro Datei

**Bewertung: Sofort adaptieren (Monitoring)**

Unsere aktuelle CLAUDE.md hat **96 Zeilen** — gut im Rahmen. Die Agents/Skills liegen teils höher:

| Datei | Zeilen | Status |
|---|---|---|
| CLAUDE.md | 96 | ✅ |
| agents/orchestrator.md | ~144 | ✅ |
| commands/develop.md | ~200+ | ⚠️ Prüfen |
| skills/ticket-writer.md | > 200 | ⚠️ Prüfen |

**Empfehlung:** Limit als Tracking-Regel in CLAUDE.md aufnehmen. Lange Commands/Skills ggf. in Sections aufteilen oder Teile auslagern.

**Aufwand:** XS — Regel dokumentieren, Dateien mittelfristig kürzen.

---

### 5.2 Notes-Directory-Pattern

**Bewertung: Später**

`CLAUDE.md` als Index auf ein `docs/notes/`-Verzeichnis mit thematischen Dateien. Spiegelt wie das Agent-Memory-System funktioniert: `MEMORY.md` als Index + topic-spezifische Dateien.

**Für unser Framework:** Könnten architektonische Entscheidungen, bekannte Probleme und Lösungsmuster in `docs/notes/` ablegen. Momentan steht alles in `CLAUDE.md` oder ist implizit im Code.

**Aufwand:** M — CLAUDE.md umstrukturieren + Notes-Dateien anlegen.

---

### 5.3 Regel "nach jeder Korrektur CLAUDE.md updaten"

**Bewertung: Sofort adaptieren**

Exaktes Zitat Boris Cherny: _"After every correction, end with: 'Update your CLAUDE.md so you don't make that mistake again.' Claude is eerily good at writing rules for itself."_

**Für unser Framework:** Diese Regel sollte in CLAUDE.md explizit stehen — sowohl als Anweisung an den Orchestrator als auch als Entwickler-Guidance. Aktuell keine solche Regel vorhanden.

**Aufwand:** XS — 2-3 Zeilen in CLAUDE.md ergänzen.

---

### 5.4 `/compact` bei 50% Context

**Bewertung: Sofort adaptieren**

Zwei komplementäre Maßnahmen:
1. **Manuell:** `/compact` bei ~50% Kontext-Nutzung ausführen
2. **Automatisch:** `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "80"` in `settings.json` (via `env` Feld)

Besonders relevant für unsere Pipeline: Lange Develop-Sessions mit mehreren Agents können schnell in Context-Overflow-Territorium geraten.

**Aufwand:** XS — settings.json + Hinweis in CLAUDE.md.

---

## Zusammenfassung nach Priorität

### Sofort adaptieren (7 Punkte)

| Nr | Feature | Aufwand | Impact |
|---|---|---|---|
| 1 | `color` in Agent-Frontmatter | XS | CLI-Übersichtlichkeit |
| 2 | `maxTurns` für Routine-Agents | XS | Sicherheit, Kostengrenze |
| 3 | `user-invocable: false` für Preload-Skills | XS | Saubereres UX, weniger Menü-Rauschen |
| 4 | `env` Feld in settings.json (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "80"`) | XS | Context-Management |
| 5 | Plan Mode dokumentieren (in CLAUDE.md) | XS | DX für interaktive Sessions |
| 6 | `/compact` bei 50% + Auto-Compact Guidance in CLAUDE.md | XS | Context-Management |
| 7 | "nach Korrektur CLAUDE.md updaten" Regel | XS | Framework-Selbstverbesserung |

**Gesamtaufwand Sofort:** ~2-3 Stunden

---

### Später (7 Punkte)

| Nr | Feature | Aufwand | Voraussetzung |
|---|---|---|---|
| 1 | `memory: project` für Orchestrator + QA | M | Memory-Governance klären |
| 2 | `isolation: "worktree"` für parallele Agents | L | Pipeline-Architektur anpassen |
| 3 | `context: fork` für ticket-writer Skill | S | Testen ob Verhalten identisch bleibt |
| 4 | `model`-Override in Analyse-Skills | XS | Klären welche Skills das brauchen |
| 5 | `argument-hint` für Skills | XS | DX-Verbesserung, nice to have |
| 6 | `alwaysThinkingEnabled` | XS | Cost/Benefit evaluieren |
| 7 | Notes-Directory-Pattern in CLAUDE.md | M | CLAUDE.md-Refactoring |

---

### Nicht relevant (5 Punkte)

| Feature | Begründung |
|---|---|
| `background: true` | Unser SDK steuert Ausführung — würde kollidieren |
| Scoped `hooks` in Agents | Unser `send-event.sh` System reicht; TTS/Audio ist explizit out of scope |
| `mcpServers` in Agents | Wir nutzen globale MCP-Konfiguration |
| `agent` Default + `teammateMode` | Wir nutzen Commands als Entry Points; experimentelle UI ist für unseren Workflow irrelevant |
| `disable-model-invocation` in Skills | Kein aktueller Use Case |

---

## Nächste Schritte

Die 7 Sofort-Punkte können in einem einzigen Folge-Ticket umgesetzt werden:

**Vorschlag T-3xx: "Quick Wins aus Claude Code Best Practices adaptieren"**
- `color` in alle 7 Agent-Frontmatter ergänzen
- `maxTurns` für 4 Routine-Agents setzen
- `user-invocable: false` für 6 Preload-Skills setzen
- `env: { CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "80" }` in settings.json
- CLAUDE.md erweitern um: Plan-Mode-Guidance, Compact-Guidance, Self-Correction-Regel

Aufwand gesamt: ~2-3 Stunden, hohes Impact-to-Effort-Verhältnis.
