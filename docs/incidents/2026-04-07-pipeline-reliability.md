# Incident Report: Pipeline Reliability Crisis

**Date:** 2026-04-07
**Duration:** Ongoing since ~2026-03-15 (3 Wochen)
**Severity:** Critical — Pipeline war nie zuverlässig produktionsfähig
**Author:** CTO (Product CTO Analysis)

---

## Summary

Die Just Ship Pipeline hat in 3 Wochen 61 Commits erhalten die Stabilität und Reliability adressieren. Trotzdem hat die Pipeline nie zuverlässig ein Ticket end-to-end durchgebracht. Tickets blieben stuck, der Orchestrator delegierte nie an Experten-Agents, Preview-URLs waren nie sichtbar, und bei jedem Versuch das zu fixen wurde "done" gemeldet ohne Verification. Am 2026-04-07 eskalierte der CEO nach dem wiederholten Fehlschlag von T-608 und T-467.

---

## Timeline

| Zeit | Event |
|------|-------|
| ~03-15 | Pipeline-Entwicklung beginnt, erste Commits |
| 03-15 – 04-06 | **61 Pipeline-Commits**: Retries, Timeouts, Watchdogs, Recovery, Supervisors, Quality Gates — alle als "done" markiert |
| 04-06 22:36 | T-608 (Board-Bug) wird erstellt, Pipeline gestartet |
| 04-06 22:44 | T-608 PR erstellt — Vercel-Check failt (Author: `claude-dev@pipeline`) |
| 04-06 22:44 – 04-07 04:04 | **T-608 hängt 12+ Stunden** — kein Retry, keine Benachrichtigung, Pipeline meldet `done` |
| 04-07 ~04:00 | CEO eskaliert: "Hier schon wieder. Es scheint einfach nicht zu funktionieren." |
| 04-07 04:04 | T-608 manuell gemergt |
| 04-07 04:06 | Vercel-Integration vom Board-Repo entfernt (T-611) |
| 04-07 04:14 | Diagnose-Intent eingebaut (T-613) — damit CTO-Analyse in Zukunft getriggert wird |
| 04-07 04:31 | E2E Smoke Test erstellt (T-614) |
| 04-07 ~17:00 | T-467 Root Cause analysiert: Push-Rejection wegen stale Remote-Branch |
| 04-07 17:24 | T-612 Fix deployed: Push-Recovery, Remote-Branch-Cleanup, Ship-Status-Rollback |
| 04-07 17:45 | Versuch SSH auf **72.60.32.232** (Hosting-VPS) statt **187.124.9.221** (Pipeline-VPS) — 30+ Minuten verschwendet |
| 04-07 17:49 | T-467 auf VPS gestartet — "Deleted stale remote branch" im Log bestätigt Fix |
| 04-07 18:02 | T-467 durchgelaufen — aber 13 Minuten für ein Spacing-Ticket, `agents:[]` im Log |
| 04-07 18:12 | Root Cause gefunden: `loadAgents(workDir)` statt `projectDir` — `.claude/agents/` ist gitignored |
| 04-07 18:20 | T-610 gestartet nach T-621 Fix — `agents:["backend","frontend","qa",...]` im Log |
| 04-07 18:23 | **T-610 in 3 Minuten durchgelaufen** — erste erfolgreiche Pipeline mit Agents |

---

## Root Causes

### Primary Cause: Keine End-to-End Verification

Kein einziger Pipeline-Fix in 3 Wochen und 61 Commits wurde jemals end-to-end verifiziert. Der QA-Agent prüft Acceptance Criteria gegen Code — nicht ob die Pipeline danach tatsächlich ein Ticket von A bis Z durchbringt. Jeder Fix deckt nur den spezifischen Failure-Pfad ab, der nächste unbekannte Pfad blockiert wieder alles.

**Google SRE Analogie:** Das Team hatte ein "Declaration Gate" statt ein "Verification Gate" — "done" bedeutete "Code gemergt", nicht "Problem nachweislich nicht mehr reproduzierbar in Produktion".

### Contributing Factors

**CF-1: `agents:[]` seit Wochen unentdeckt**
`loadAgents(workDir)` suchte im Worktree statt im Projekt-Root. `.claude/agents/` ist gitignored → existiert nicht im Worktree → Orchestrator hatte nie Zugang zu Experten-Agents. Bedeutet: die gesamte Multi-Agent-Architektur (Backend, Frontend, QA Agents) war auf dem VPS nie aktiv. Der Orchestrator hat seit Beginn alles selbst gemacht — langsamer, ohne Expertise, ohne Delegation.

**CF-2: Keine Environment-Parity**
Lokale Entwicklung funktioniert weil Claude Code `.claude/agents/` automatisch liest. Auf dem VPS läuft der SDK `query()`-Call, der Agents explizit übergeben bekommt. Dieser Unterschied wurde nie getestet. Zusätzlich: `project.json` auf dem VPS hatte kein `hosting`-Feld obwohl lokal Coolify konfiguriert war → Preview-URL konnte nie ermittelt werden.

**CF-3: Falsche Server-IP**
Das Team hat 30+ Minuten versucht SSH auf den Hosting-VPS (72.60.32.232) statt den Pipeline-VPS (187.124.9.221) zu machen. Es gab keine zentrale, maschinenlesbare Referenz welcher Server welche Funktion hat. IPs waren in keiner Config-Datei dokumentiert — nur im Gedächtnis.

**CF-4: Develop-Prozess umgangen**
T-621 und T-622 wurden über raw `Agent`-Tool-Calls implementiert statt über `/develop`. Die Agents liefen ohne Skills, ohne Agent-Definitionen, ohne QA — exakt das Problem das gleichzeitig auf dem VPS gefixt wurde.

**CF-5: Vercel-Integration als Altlast**
Die Vercel GitHub-Integration war noch auf dem Board-Repo aktiv obwohl Coolify das Hosting übernommen hat. Jeder Pipeline-PR bekam einen failing Vercel-Check mit "No GitHub account found matching commit author email". Dieser Check blockierte T-608 für 12+ Stunden.

**CF-6: Preview-URL hinter QA-Tier-Gate**
Die Preview-URL-Ermittlung (Vercel + Coolify) war nur bei `qaTier === "full"` aktiv. Die meisten Tickets werden als `light` eingestuft → Preview-URL wurde nie ermittelt.

---

## Impact

- **CEO-Vertrauen massiv beschädigt** — "Das ist komplett amateurhaft", "Wir drehen uns im Kreis"
- **Kundenvertrauen gefährdet** — "Wenn aktuell irgendjemand Just Ship mit der Pipeline verwenden würde, dann würden sie sofort aufgeben"
- **3 Wochen Engineering-Aufwand** (61 Commits) ohne funktionierendes Ergebnis
- **T-608:** 12+ Stunden stuck
- **T-467:** 2 gescheiterte Versuche, erst beim 3. durchgelaufen
- **Agents nie aktiv auf VPS** — gesamte Multi-Agent-Architektur war Fassade

---

## What Went Well

- CTO-Diagnose (nachdem der Intent eingebaut wurde) hat die systemischen Ursachen korrekt identifiziert statt nur Symptome zu fixen
- E2E Smoke Test (T-614) als Konzept ist richtig — verhindert in Zukunft "done ohne Beweis"
- Alle Fixes am Ende der Session wurden auf dem VPS verifiziert (T-467, T-610)
- T-610 lief in 3 Minuten mit Agents durch — Beweis dass die Architektur funktioniert wenn sie korrekt konfiguriert ist

---

## What Went Wrong

### 1. "Done" ohne Verification (61 Mal)
Kein einziger der 61 Pipeline-Commits wurde end-to-end getestet. Der Prozess war: Code schreiben → TypeScript kompiliert → PR → Merge → "done". Ob die Pipeline danach ein echtes Ticket durchbringt wurde nie geprüft.

### 2. Symptom-Fixing statt Root-Cause-Analyse
Jedes Mal wenn ein Ticket stuck war, wurde der spezifische Fehler gefixt (Retry hier, Timeout da, Recovery dort) — ohne zu fragen warum das Pattern immer wieder auftritt. Es fehlte die CTO/Diagnose-Ebene.

### 3. Lokaler Test ≠ VPS-Test
Alles was lokal funktioniert wurde als funktionierend angenommen. Der Unterschied zwischen lokaler Claude-Code-Ausführung und VPS-SDK-Ausführung wurde nie verifiziert. `agents:[]` war der schlimmste Ausdruck davon.

### 4. Config-Drift zwischen lokal und VPS
`project.json` auf dem VPS war nicht aktuell (fehlendes `hosting`-Feld). Es gibt keinen Mechanismus der sicherstellt dass VPS-Config und lokale Config synchron sind.

### 5. Keine Environment-Registry
Kein maschinenlesbarer Ort der sagt "Pipeline-VPS ist 187.124.9.221, Hosting-VPS ist 72.60.32.232". Das Team hat aus dem Gedächtnis gearbeitet und die falsche IP verwendet.

### 6. Eigene Regeln gebrochen
Der PM (Orchestrator) hat den Develop-Prozess umgangen obwohl CLAUDE.md explizit sagt: "Du implementierst NIEMALS direkt". Die Ausrede "ist ja nur eine Zeile" ist das gleiche Muster das bei Kunden-Projekten zu Qualitätsproblemen führt.

---

## Action Items

### P0 — Sofort (diese Woche)

| # | Action | Owner | Verification |
|---|--------|-------|-------------|
| 1 | **VPS-Config-Sync automatisieren** — `project.json` wird bei jedem Deploy automatisch vom Repo auf den VPS gesynct. Kein manuelles Kopieren. | Backend | `ssh root@187.124.9.221 'docker exec vps-pipeline-server-1 cat /home/claude-dev/projects/just-ship-board/project.json'` zeigt identische Config wie lokal |
| 2 | **Environment-Registry** — `.claude/rules/` Regel die Pipeline-VPS (187.124.9.221) und Hosting-VPS (72.60.32.232) als maschinenlesbare Referenz enthält. Jeder SSH-Befehl MUSS die Registry konsultieren. | DevOps | Memory + Rule existiert, wird von Agents gelesen |
| 3 | **Smoke Test als Merge-Gate für Pipeline-Tickets** — kein Merge ohne `bash scripts/pipeline-smoke-test.sh` PASS + VPS-Verification | DevOps | Definition of Done in CLAUDE.md aktualisiert (bereits done mit T-614) |

### P1 — Diese Woche

| # | Action | Owner | Verification |
|---|--------|-------|-------------|
| 4 | **VPS-Integration-Test** — erweiterter Smoke Test der ein echtes Ticket auf dem VPS durch die Pipeline schickt und `status: in_review` + `agents` im Log verifiziert | Backend | Script existiert, läuft nach jedem Pipeline-Deploy |
| 5 | **Config-Validation beim Container-Start** — Pipeline-Server prüft beim Startup ob jedes registrierte Projekt `hosting`, `agents/`, `CLAUDE.md` hat. Warnt laut bei fehlender Config. | Backend | Container-Log zeigt Warnings bei fehlender Config |
| 6 | **Enforce /develop — keine raw Agent-Spawns** — Rule in `.claude/rules/` die verhindert dass der PM direkt implementiert | PM | Rule existiert, wird bei jedem Task gelesen |

### P2 — Nächste Woche

| # | Action | Owner | Verification |
|---|--------|-------|-------------|
| 7 | **Postmortem-Kultur etablieren** — nach jedem Pipeline-Incident ein kurzes Postmortem in `docs/incidents/`. Template bereitstellen. | PM | Template existiert, erster Report ist dieser hier |
| 8 | **Regression-Detection** — wenn ein Ticket mehr als 1x den Cycle `done → in_progress → done` durchläuft, automatisch Flag im Board | Backend | Board-UI zeigt "Regression" Badge |
| 9 | **SLO für Pipeline** — messbare Ziele: >90% Success Rate, <10 Min Durchlaufzeit für S-Tickets, 0 stuck Tickets >1h | PM | Dashboard im Board |

---

## Lessons Learned

### 1. Verification > Declaration
"Done" muss "verifiziert" bedeuten, nicht "committed". Google SRE: "Ein Fix ohne Verification ist eine Hypothese, kein Fix." Unser neuer Standard: Pipeline-Tickets sind erst done wenn ein echtes Ticket auf dem VPS durchgelaufen ist.

### 2. Lokale Tests sind notwendig, aber nicht hinreichend
Der Unterschied zwischen lokaler Ausführung (Claude Code liest `.claude/agents/` automatisch) und VPS-Ausführung (SDK `query()` bekommt Agents explizit) war wochenlang unsichtbar. VPS-Verification ist Pflicht.

### 3. Config-Drift ist ein stiller Killer
`project.json` auf dem VPS war veraltet, `hosting`-Feld fehlte, `agents` waren unsichtbar. Kein Startup-Check hat das bemerkt. Startup-Validation (fail fast) muss Standard sein.

### 4. Fix-Loops erkennen und eskalieren
Wenn dasselbe Problem-Muster (stuck Tickets) zum 3. Mal auftritt, ist es kein Bug mehr — es ist ein Architektur-Problem. Der Reflex "noch ein Fix" muss durch "Root-Cause-Analyse auf System-Ebene" ersetzt werden. Der Diagnose-Intent (T-613) ist der erste Schritt dazu.

### 5. Eigene Regeln gelten immer
"JEDE Änderung geht durch den Develop-Prozess" — auch unter Zeitdruck, auch bei "nur einer Zeile". Die Regeln existieren nicht für den Normalfall, sondern für den Stressfall.

### 6. Infrastruktur-Wissen muss maschinenlesbar sein
Server-IPs, Credentials-Pfade, Environment-Zuordnungen dürfen nicht im Kopf sein. Sie müssen in Config-Dateien stehen die automatisch gelesen werden. Ein Mensch der sich eine IP merken muss, wird sie verwechseln.

---

## Systemic Changes Required

Basierend auf Google SRE Practices und den Learnings aus diesem Incident:

### 1. Production Readiness Review für Pipeline
Vor jedem Pipeline-Feature-Release: Checklist durchgehen. Nicht als Bürokratie, sondern als "würde ich das in Produktion laufen lassen wenn Kunden davon abhängen?".

### 2. Immutable Deployments
`project.json` und `.claude/` Config auf dem VPS sollen nicht manuell gepatcht werden. Sie kommen aus dem Docker-Image oder werden beim Deployment automatisch aus dem Repo gezogen.

### 3. Startup-Validation
Der Pipeline-Server prüft beim Start ob jedes Projekt korrekt konfiguriert ist:
- `agents/` Verzeichnis existiert und enthält Dateien
- `project.json` hat `hosting`-Feld wenn erwartet
- Git-Remote ist erreichbar
- Board-API antwortet

Bei Failure: laut loggen, Health-Endpoint meldet "degraded".

### 4. Observability
Nicht nur "Pipeline completed" loggen, sondern:
- Welche Agents wurden geladen? (bereits gefixt mit T-621)
- Wie lange hat jede Phase gedauert?
- Wurde die Preview-URL gesetzt?
- Hat der Orchestrator delegiert oder alles selbst gemacht?

---

*Dieser Report ist das erste Postmortem im Just Ship Projekt. Das Template wird für zukünftige Incidents wiederverwendet.*
