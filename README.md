# agent

Ein Docker-Image für einen SSH-fähigen Agent-Entwicklungscontainer mit vorinstallierter Toolchain (R, Python/lea, DuckDB, Helix, opencode) und Agent-Skills.

## Schnellstart

**Voraussetzungen:** Docker, eine Datei `authorizedkeys` mit deinem Public Key, und ein GitHub-Token.

```bash
./agent.sh build
export GITHUB_TOKEN_AGENT=ghp_xxx   # Token der Agent-Accounts
export GITHUB_TOKEN_NERT=ghp_xxx
export FORGEJO_TOKEN=xxx
export DEEPSEEK_API_KEY=sk-xxx
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
| Agent       | opencode                                                    |
| Git/Hosting | `gh` (GitHub), `fj` (Forgejo-CLI)                           |
| R           | R, pak, data.table, duckdb, shiny, plotly, …                |
| Python      | 3.14, lea-cli, duckdb                                       |
| Daten       | DuckDB CLI                                                  |
| Utilities   | tmux, ripgrep, fd, fzf, tokei, air (R-Formatter), …         |
| Skills      | mattpocock Engineering Skills (zur Build-Zeit), forgejo-Skill |

## Konfiguration

- `agent.sh` — steuert Build/Run. Variablen: `IMAGE_NAME`, `CONTAINER_NAME`, `NETWORK_NAME`, `PORT_MAPPING` (Standard: `2222:22`).
- `authorizedkeys` — derselbe Public Key für den Benutzer.
- `hx_config.toml` / `tmux.conf` — Helix- bzw. tmux-Konfiguration.
- `opencode/` — opencode-Konfiguration (`opencode.json`, `tui.json`, `commands/`, `skills/`).

## Tokens

Der Entrypoint schreibt `GH_TOKEN`, `FORGEJO_TOKEN` und `DEEPSEEK_API_KEY` in die Datei `~/.ssh/environment` des jeweiligen Benutzers; sshd injiziert sie beim SSH-Login in die Shell (`PermitUserEnvironment`). Die Git-Credential-Helper für GitHub und Forgejo lesen daraus automatisch.
