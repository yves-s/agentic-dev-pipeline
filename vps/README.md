# VPS Setup — Agentic Dev Pipeline 24/7

Autonome Dev-Pipeline auf Hostinger VPS (Ubuntu 22.04).

## Architektur

```
Supabase (tickets)
    │
    │  status = 'ready_to_develop'
    │
    ▼
worker.sh (pollt alle 60s)
    │
    │  claim: pipeline_status → 'running'
    │
    ▼
.pipeline/run.sh <ticket_number> <title> <body> <labels>
    │
    │  claude --agent orchestrator --dangerously-skip-permissions
    │
    ▼
GitHub PR + Supabase status → 'in_review'
```

Der Worker läuft als `claude-dev` User via systemd. Pro Projekt ein Service.

---

## Schritt 1: VPS vorbereiten

Auf Hostinger: VPS erstellen, Ubuntu 22.04, root-Zugang per SSH.

```bash
# Lokaler Rechner
ssh root@<VPS-IP>
```

---

## Schritt 2: Setup ausführen

```bash
# Auf dem VPS als root
curl -fsSL https://raw.githubusercontent.com/yves-s/agentic-dev-pipeline/main/vps/setup-vps.sh -o /tmp/setup-vps.sh
chmod +x /tmp/setup-vps.sh
bash /tmp/setup-vps.sh
```

Das Script fragt interaktiv nach:
- `ANTHROPIC_API_KEY` — Claude API Key
- `GH_TOKEN` — GitHub Personal Access Token (Scopes: `repo`, `workflow`)

Alternativ als Umgebungsvariablen übergeben:
```bash
ANTHROPIC_API_KEY=sk-ant-... GH_TOKEN=ghp_... bash /tmp/setup-vps.sh
```

Das Script installiert:
- Node.js 20, git, gh, python3, jq
- Claude Code CLI (`claude`)
- `claude-dev` User
- systemd Service Template

---

## Schritt 3: Projekt klonen + Pipeline installieren

```bash
su - claude-dev

# Projekt klonen
git clone https://$GH_TOKEN@github.com/org/repo.git ~/mein-projekt

# Pipeline-Framework installieren
cd ~/mein-projekt
~/agentic-dev-pipeline/setup.sh

# project.json anpassen (Supabase-IDs, Build-Commands)
nano project.json
```

---

## Schritt 4: Projekt-Config erstellen

Für jeden Worker eine `.env.{projekt-slug}` Datei:

```bash
cat > /home/claude-dev/.env.mein-projekt <<'EOF'
# Supabase
SUPABASE_URL=https://usvzrksqbtwasgvolkyu.supabase.co
SUPABASE_SERVICE_KEY=eyJ...
SUPABASE_PROJECT_ID=dc2b647e-80cb-4661-8f27-ff811534a0a8

# Projekt
PROJECT_DIR=/home/claude-dev/mein-projekt

# Worker
POLL_INTERVAL=60
EOF

chmod 600 /home/claude-dev/.env.mein-projekt
chown claude-dev:claude-dev /home/claude-dev/.env.mein-projekt
```

> **Supabase Service Key** → Supabase Dashboard → Project Settings → API → `service_role` Key

> **SUPABASE_PROJECT_ID** → UUID aus der `project_id` Spalte in der `tickets` Tabelle (nicht die Supabase-Projekt-ID)

---

## Schritt 5: Worker starten

```bash
# Als root
sudo systemctl enable --now agentic-dev-pipeline@mein-projekt

# Logs live
journalctl -fu agentic-dev-pipeline@mein-projekt

# Status
systemctl status agentic-dev-pipeline@mein-projekt
```

---

## Mehrere Projekte

Für jedes Projekt eine separate `.env.{slug}` und einen separaten Service:

```bash
# Projekt 2
cat > /home/claude-dev/.env.anderes-projekt <<'EOF'
SUPABASE_PROJECT_ID=andere-uuid-...
PROJECT_DIR=/home/claude-dev/anderes-projekt
POLL_INTERVAL=60
EOF

sudo systemctl enable --now agentic-dev-pipeline@anderes-projekt
```

Beide Worker laufen unabhängig. Da jeder nur Tickets seines eigenen `project_id` pollt, gibt es keine Konflikte.

---

## Logs

```bash
# Live-Log des Workers
journalctl -fu agentic-dev-pipeline@mein-projekt

# Pipeline-Logs (pro Ticket)
ls ~/pipeline-logs/
tail -100 ~/pipeline-logs/T--267-*.log

# Alle aktuellen Worker
systemctl list-units "agentic-dev-pipeline@*"
```

---

## Tickets in die Queue stellen

Tickets landen automatisch im Worker, sobald `status = 'ready_to_develop'` UND `pipeline_status IS NULL`.

```sql
-- Ticket für Pipeline freigeben
UPDATE public.tickets
SET status = 'ready_to_develop', pipeline_status = NULL
WHERE number = 267;
```

Oder via `/ticket` Slash-Command in Claude Code (schreibt direkt nach Supabase).

---

## Troubleshooting

### Worker startet nicht
```bash
systemctl status agentic-dev-pipeline@mein-projekt
journalctl -u agentic-dev-pipeline@mein-projekt -n 50
```

### Häufige Fehler

| Fehler | Ursache | Fix |
|--------|---------|-----|
| `ANTHROPIC_API_KEY muss gesetzt sein` | .env nicht geladen | `EnvironmentFile` in Service prüfen |
| `Pipeline runner nicht gefunden` | setup.sh nicht ausgeführt | `cd ~/projekt && ~/agentic-dev-pipeline/setup.sh` |
| `Supabase nicht erreichbar` | Netzwerk/Key | SUPABASE_URL + SERVICE_KEY prüfen |
| `gh: authentication required` | GH_TOKEN abgelaufen | Neuen Token generieren, in .env eintragen |
| `claude: command not found` | npm global path fehlt | `export PATH="$(npm root -g)/.bin:$PATH"` |

### Pipeline manuell testen
```bash
su - claude-dev
source ~/.env
source ~/.env.mein-projekt

cd ~/mein-projekt
.pipeline/run.sh 267 "Test-Ticket" "Manueller Test" ""
```

### Ticket manuell zurücksetzen
Wenn ein Ticket in `pipeline_status = 'running'` feststeckt:
```sql
UPDATE public.tickets
SET pipeline_status = NULL, status = 'ready_to_develop'
WHERE number = 267;
```

---

## Framework updaten

```bash
su - claude-dev
cd ~/agentic-dev-pipeline && git pull

# In jedem Projekt
cd ~/mein-projekt
~/agentic-dev-pipeline/setup.sh --update

# Worker neu starten (damit worker.sh aktuell ist)
sudo systemctl restart agentic-dev-pipeline@mein-projekt
```

---

## Kosten-Schätzung (Anthropic API)

| Ticket-Typ | Agents | Kosten |
|-----------|--------|--------|
| Einfacher Bug | Orchestrator + 1 Agent | ~€1–2 |
| Feature mit DB + UI | Orchestrator + 3 Agents | ~€3–5 |
| Komplexes Feature | Orchestrator + 5 Agents | ~€5–10 |

Orchestrator läuft auf Opus (teuerster), Sub-Agents auf Sonnet/Haiku.
Bei 5 Tickets/Tag: ~€15–25/Tag Anthropic-Kosten.

VPS-Kosten Hostinger: ~€4–8/Monat (VPS 1 oder VPS 2).
