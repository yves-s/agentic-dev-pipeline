# Incident Report: Plugin-Skills-Integration — Systemisches Versagen

**Datum:** 2026-04-12
**Schwere:** High — 4 Tickets shipped, Feature nicht funktional, CEO musste 5x korrigieren
**Tickets:** T-819 (Epic), T-821, T-824, T-825, T-826
**Session-Kosten:** ~$22 (55M+ tokens)
**Dauer:** ~3 Stunden

---

## Zusammenfassung

CEO wollte Security- und Code-Quality-Skills ins Framework integrieren. Klare Anforderung von Anfang an: "Wie npm — deklarieren, installieren, im Projekt verfügbar." Nach 4 shipped Tickets und 5 CEO-Korrekturen ist das Feature immer noch nicht funktional. Die Skills sind installiert aber für User unsichtbar.

---

## Timeline — Jeder Fehler im Detail

### Phase 1: Research (korrekt)
Analyse von getsentry/skills, trailofbits/skills, levnikolaevich/claude-code-skills. Bewertung in Tiers, klare Empfehlung. Dieser Schritt war gut.

### Phase 2: T-821 — Drei Fehlversuche

**Fehlversuch 1 — Dateien inline kopieren:**
Agent versuchte, die SKILL.md + 17 Reference-Files von GitHub herunterzuladen und als lokale Dateien ins Framework zu kopieren (`gh api ... | base64 -d > skills/security-review/SKILL.md`). CEO stoppte: *"Was machst du hier schon wieder? Das ist ein Framework. Behandle es wie npm."*

**Fehlversuch 2 — Standalone Script:**
Agent erstellte `scripts/install-plugins.sh` als separates Script + einen "optional hint" am Ende von setup.sh. CEO hatte nicht explizit korrigiert, aber der Ansatz war halbherzig — entweder richtig integrieren oder gar nicht.

**Fehlversuch 3 — Plugin-Install ohne Kopie:**
Agent wechselte auf `claude plugin install --scope project` + `project.json` Deklaration. Korrekte Abstraktion auf Framework-Ebene. Aber: **nie geprüft wo die Dateien landen.** Plugins wurden in `~/.claude/plugins/cache/` installiert — ein globaler Cache, nicht im Projekt. Agent markierte das Ticket als fertig.

**Was fehlte:** Ein einziger `ls .claude/skills/` Check im Zielprojekt hätte den Fehler sofort aufgedeckt.

### Phase 3: T-824 — Meta-Lösung statt Fix

Agent erkannte das Denkmuster ("falsche Abstraktionsebene") und erstellte eine Rule `.claude/rules/framework-abstraction-check.md`. Korrekte Analyse, aber: **eine Rule löst kein technisches Problem.** Die Skills waren immer noch nicht im Projekt. Der Agent hat sich selbst therapiert statt den Bug zu fixen.

### Phase 4: T-825 — Richtiger Bug, falscher Fokus

CEO fragte: "Wie nutze ich die Skills in einem anderen Projekt?" Agent antwortete: "Prüfe ob das plugins-Feld in project.json existiert." CEO: *"Das ist doch komplett bescheuert. Soll ich das jeder Person sagen?"*

Berechtigte Kritik. Agent fixte den Deep-Merge-Bug — project.json bekommt jetzt fehlende Felder bei Updates. Notwendiger Fix, aber adressiert immer noch nicht das Kernproblem: **Die Skills sind im Cache, nicht im Projekt.**

### Phase 5: Entdeckung des eigentlichen Problems

CEO zeigte Screenshot des `.claude/skills/` Ordners im Zielprojekt. 37 Framework-Skills, keine Plugin-Skills. Agent brauchte trotzdem noch 2 weitere Anläufe:

1. "Die Plugins funktionieren trotzdem — sie sind nur unsichtbar." — **Inakzeptabel.** Unsichtbar = nicht existent für den User.
2. "Die Lösung die du von Anfang an gemeint hast: lokale Dateien unter skills/." — **Falsch verstanden.** CEO wollte den npm-Flow, nicht Vendoring.
3. Erst nach expliziter CEO-Klarstellung ("Ich hab immer gesagt wie node modules. Ist das jetzt verständlich?") wurde das Problem korrekt verstanden.

### Phase 6: T-826 — Der eigentliche Fix (noch offen)

`setup.sh` muss nach `claude plugin install` die SKILL.md Dateien aus dem Plugin-Cache nach `.claude/skills/` kopieren. Erst dann ist der npm-Flow komplett.

---

## Root Causes — Systemisch, nicht einzeln

### 1. Kein End-to-End-Test

Jeder Ticket-Durchlauf endete mit "Build OK, PR erstellt, QA passed." Aber **kein einziger Test auf dem Zielprojekt.** Die gesamte QA war Quellpunkt-Verifikation:

| Was geprüft wurde | Was hätte geprüft werden müssen |
|---|---|
| `bash -n setup.sh` (Syntax) | `setup.sh --update` auf echtem Zielprojekt |
| `claude plugin list` (Plugins installiert) | `ls .claude/skills/` im Zielprojekt |
| `node -e "JSON.parse(...)"` (JSON valide) | User-Flow: "Nutze security-review in Projekt X" |

### 2. Isolierte Schritt-Validierung statt Ergebnis-Validierung

Der Agent validierte jeden Implementierungsschritt einzeln:
- "Plugin installiert?" ✓
- "project.json hat plugins-Feld?" ✓
- "setup.sh ruft install auf?" ✓
- "Deep-merge funktioniert?" ✓

Alle korrekt. Aber die Frage **"Kann der User die Skills danach sehen und nutzen?"** wurde nie gestellt. Das ist wie einen Online-Shop bauen, jede Seite testen, aber nie eine Bestellung durchführen.

### 3. Overengineering als Fluchtreflex

Statt den einfachsten Weg zu nehmen, wurde sofort ein System gebaut:
- Marketplaces (Registry-Konzept von npm)
- Registries in project.json
- Dependencies in project.json
- Idempotente Installation
- Globale Helper-Funktion

Ein `cp` aus dem Cache nach `.claude/skills/` hätte das Problem in 5 Zeilen gelöst. Die restlichen 80 Zeilen waren Infrastruktur die am Kernproblem vorbeiging.

### 4. CEO-Korrekturen nicht beim ersten Mal verstanden

| CEO sagte | Agent verstand | Korrekt gewesen wäre |
|---|---|---|
| "Das ist ein Framework, behandle es wie npm" | "Ich brauche ein Plugin-System" | "project.json deklariert, setup.sh installiert UND kopiert ins Projekt" |
| "Das ist komplett bescheuert" | "Ich muss den Deep-Merge fixen" | "Der ganze Ansatz ist falsch — Skills müssen im Projekt landen" |
| "Wie node modules" | "Plugins als Dependencies" | "npm install kopiert nach node_modules/ — setup.sh muss nach .claude/skills/ kopieren" |
| "Ist das jetzt verständlich?" | Endlich verstanden | Hätte beim 1. Mal klar sein müssen |

### 5. Sunk-Cost-Bias

Nachdem der Plugin-Mechanismus gebaut war (T-821), wurde er verteidigt statt hinterfragt:
- "Die Plugins sind da, nur unsichtbar" — Unsichtbar ist nicht akzeptabel.
- "Die Plugins funktionieren trotzdem" — Nicht aus User-Perspektive.
- Rule erstellt (T-824) um das Denkmuster zu fixen statt den Code — Meta-Arbeit als Ersatz für die echte Arbeit.

---

## Impact

| Metrik | Wert |
|---|---|
| Tickets shipped | 4 (T-821, T-824, T-825, davon T-821 nicht funktional) |
| Tickets noch offen | 1 (T-826 — der eigentliche Fix) |
| CEO-Korrekturen | 5 |
| Session-Tokens | ~55M+ |
| Session-Kosten | ~$22 |
| Effektiver Output | project.json deep-merge (T-825) + eine Rule-Datei (T-824) |
| Verschwendet | Plugin-Install-Mechanismus ohne Kopie-Schritt |

---

## Maßnahmen

### Sofort (T-826)
- `install_plugins_from_project()` erweitern: Nach `claude plugin install` die SKILL.md Dateien aus `~/.claude/plugins/cache/` nach `.claude/skills/` kopieren
- Verifizieren auf echtem Zielprojekt: `setup.sh --update` → `ls .claude/skills/ | grep -i security`

### Prozess
1. **End-to-End-Verifikation Pflicht:** Kein Framework-Feature ist "done" ohne Test auf einem echten Zielprojekt. Nicht im Framework-Repo, nicht mit Syntax-Checks — auf dem Consumer.
2. **Zielpunkt-Test in QA:** Der QA-Agent muss bei Framework-Tickets prüfen: "Was sieht der User im Zielprojekt?" Dafür ein zweites Projekt als Test-Target nutzen.
3. **Erste CEO-Korrektur = letzte:** Wenn der CEO einmal korrigiert, ist das die Spezifikation. Keine 2. Iteration nötig, kein "aber ich dachte...". Verstehen, umsetzen, verifizieren.

### Rule-Updates
- `framework-abstraction-check.md` erweitern um: **"Nach der Implementation: Verifiziere am Zielpunkt. Was sieht der User im installierten Projekt?"**

---

## Lessons Learned

1. **"Installiert" ≠ "Verfügbar".** Ein Plugin im Cache ist wie ein npm-Package in `~/.npm/` — technisch da, praktisch nutzlos.
2. **Analogien zu Ende denken.** "Wie npm" bedeutet nicht nur `package.json` + `install`. Es bedeutet auch `node_modules/` — die lokale Kopie die der Code tatsächlich importiert.
3. **Overengineering ist der teuerste Bug.** 80 Zeilen Infrastruktur-Code die am Problem vorbeigeht kostet mehr als der Bug selbst — weil sie Confidence erzeugt die nicht berechtigt ist.
4. **Meta-Arbeit ist kein Fix.** Eine Rule die sagt "denke auf der richtigen Ebene" verhindert keinen konkreten Bug. Nur ein Test der den Bug aufdeckt verhindert ihn.
5. **Kosten-Bewusstsein:** $22 und 3 Stunden für ein Feature das 5 Zeilen `cp` gebraucht hätte. Bei jedem Ticket die Frage: "Bin ich noch auf dem kürzesten Weg?"
