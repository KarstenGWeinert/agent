# agent

Ein Docker-Image für einen SSH-fähigen Agent-Entwicklungscontainer mit vorinstallierter Toolchain (R, Python/lea, DuckDB, Helix, opencode, Pi) und Agent-Skills.

## Schnellstart

**Voraussetzungen:** Docker und ein GitHub-Token. Der Public Key wird über die Environment-Variable `SSH_PUBLIC_KEY` gesetzt.

```bash
./agent.sh build
export GITHUB_TOKEN_AGENT=ghp_xxx   # Token der Agent-Accounts
export FORGEJO_TOKEN=xxx
export DEEPSEEK_API_KEY=sk-xxx
export SSH_PUBLIC_KEY="ssh-ed25519 AAAA... dein-key"
./agent.sh run
```

Danach per SSH einloggen:

```bash
ssh agent@localhost -p 2222
```

## Benutzer

| Benutzer | Rolle |
|----------|-------|
| `agent`  | Hauptnutzer (opencode, Agent-Skills, passwortloses sudo) |

SSH erlaubt nur `agent`, ausschließlich per Public Key (keine Passwörter, kein Root-Login).

## Enthaltene Tools

| Kategorie   | Tool                                                        |
|-------------|-------------------------------------------------------------|
| Editor      | Helix (`hx`)                                                |
| Agent       | opencode, Pi                                                |
| Git/Hosting | `gh` (GitHub), `fj` (Forgejo-CLI)                           |
| R           | R, pak, data.table, duckdb, shiny, plotly, …                |
| Python      | 3.14, lea-cli, duckdb                                       |
| Daten       | DuckDB CLI                                                  |
| Utilities   | herdr, ripgrep, fd, fzf, scc, air (R-Formatter), …         |
| Skills      | mattpocock Engineering Skills (zur Build-Zeit), forgejo-Skill |

## Konfiguration

- `agent.sh` — steuert Build/Run. Variablen: `IMAGE_NAME`, `CONTAINER_NAME`, `NETWORK_NAME`, `PORT_MAPPING` (Standard: `2222:22`).
- `SSH_PUBLIC_KEY` — Public Key des Benutzers als Environment-Variable; wird zur Laufzeit in `~/.ssh/authorized_keys` geschrieben.
- `dotfiles/` — Konfigurationsdateien in einem das Container-Dateisystem spiegelnden Layout (z. B. `dotfiles/home/agent/.config/helix/config.toml`, `dotfiles/home/agent/.config/herdr/config.toml`, `dotfiles/home/agent/.config/opencode/`, `dotfiles/home/agent/.lintr`).

## DeepSeek-Peak-Guard

Unbeaufsichtigte Nightshift-Runs sollen nicht in die DeepSeek-Peak-Fenster
fallen, in denen der doppelte Preis gilt: Mo–Fr 01:00–04:00 und 06:00–10:00 UTC
(ohne chinesische Feiertage). Der Peak-Guard pausiert den Container in diesen
Fenstern mit `docker pause` und taut ihn danach mit `docker unpause` wieder auf.

`pause` statt `stop`: ein `stop` beendet die Prozesse und damit den Run;
`pause` friert sie ein und erhält Workspace, Prozesszustand und offene Locks.
Offene Netzwerk-Anfragen können am Peer trotzdem timeouten (siehe Grenzen).

Der Guard läuft auf dem Host — der Container hat kein systemd und keinen
Docker-Socket. `agent.sh` steuert ihn, die systemd-Units in `systemd/`
übernehmen die Zeitsteuerung.

### Installation

Die Units werden **nicht** automatisch installiert:

```bash
sudo cp systemd/agent-peak-guard.service systemd/agent-peak-guard.timer /etc/systemd/system/
sudo systemctl daemon-reload
```

In `systemd/agent-peak-guard.service` einmalig anpassen:

- `WorkingDirectory=` — Verzeichnis dieses Repos (dort liegt `agent.sh`).
- `Environment=CONTAINER_NAME=` — nur nötig, wenn der Container nicht
  `opencode-container` heißt.

### Bedienung

```bash
./agent.sh peak-guard enable    # Guard aktivieren und starten
./agent.sh peak-guard disable   # Guard stoppen; taut einen pausierten Container vorher auf
./agent.sh peak-guard status    # Timer-Status und Container-Zustand
./agent.sh peak-guard apply     # Jetzt abgleichen (wird vom Timer aufgerufen)
```

`enable`/`disable`/`status` brauchen `systemctl`-Zugriff (ggf. mit `sudo`
ausführen); sie installieren keine Units und brechen mit einem Hinweis ab, wenn
die Units fehlen. `status` endet auch dann mit Fehlercode, wenn der Container
fehlt. Alle Aktionen sind idempotent.

`apply` berechnet aus der aktuellen UTC-Zeit den Soll-Zustand und pausiert bzw.
taut den Container entsprechend. Ein Neustart oder ein verpasstes Fenster wird
durch `Persistent=true` beim nächsten Start nachgeholt. Fehlt der Container oder
wurde er mit AutoRemove (`--rm`) gestartet, meldet `apply` einen Fehler und
ändert nichts.

### Verhalten und Grenzen

- Bei aktivem Guard wird der **gesamte** Container pausiert — auch wenn gerade
  interaktiv gearbeitet wird. Wer während der Peak-Zeit arbeiten will,
  deaktiviert den Guard vorher.
- Laufende Netzwerk-Anfragen können beim Pausieren hängen bleiben und nach dem
  Auftauen fehlschlagen. Dateien und der Workspace bleiben erhalten; ein
  unterbrochener Run wird **nicht** automatisch fortgesetzt.
- Chinesische Feiertage modelliert der Timer nicht: An diesen Tagen wird
  unnötig pausiert (geringfügiger Kapazitätsverlust).
- `disable` taut einen noch pausierten Container vorher auf, damit er nicht
  eingefroren zurückbleibt.

### Manueller Test

Auf dem Host nacheinander prüfen:

1. `./agent.sh peak-guard enable`, dann innerhalb eines Peak-Fensters
   `./agent.sh peak-guard status` → Container `paused`.
2. Uhrzeit über eine Fenstergrenze laufen lassen (oder `apply` entsprechend
   auslösen) → Container wechselt den Zustand.
3. Host mitten im Fenster neu starten → Container ist nach dem Boot pausiert.
4. `./agent.sh peak-guard disable`, während der Container pausiert ist →
   Container läuft wieder.
5. Dateien im Workspace sind nach Pause/Unpause unverändert.

## Tokens

Der Entrypoint schreibt `GH_TOKEN`, `FORGEJO_TOKEN` und `DEEPSEEK_API_KEY` in die Datei `~/.ssh/environment` des jeweiligen Benutzers; sshd injiziert sie beim SSH-Login in die Shell (`PermitUserEnvironment`). Die Git-Credential-Helper für GitHub und Forgejo lesen daraus automatisch.
