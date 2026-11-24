#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# agent.sh
# Helper script for building and running your "agent" Docker container
# Put this in the same directory as your Dockerfile
# -----------------------------------------------------------------------------

# Get the directory of the actual script file (follows symlinks)
SCRIPT_DIR="$( cd -P "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )"

# Default values — override via environment variables
IMAGE_NAME="${IMAGE_NAME:-opencode-image}"
CONTAINER_NAME="${CONTAINER_NAME:-opencode-container}"
NETWORK_NAME="${NETWORK_NAME:-dev-network}"
PORT_MAPPING="${PORT_MAPPING:-2222:22}"

# DeepSeek peak guard systemd units (see systemd/ and README)
PEAK_GUARD_SERVICE="agent-peak-guard.service"
PEAK_GUARD_TIMER="agent-peak-guard.timer"

usage() {
  cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  build          Build the Docker image
  run            Run (or restart) the container in detached mode
  stop           Stop and remove the running container
  logs           Show container logs (follow with -f)
  exec           Open an interactive shell inside the container
  peak-guard     Manage the DeepSeek peak guard (enable|disable|status|apply)
  help           Show this help message

Environment variables you can set:
  IMAGE_NAME       Docker image name (default: $IMAGE_NAME)
  CONTAINER_NAME   Container name     (default: $CONTAINER_NAME)
  PORT_MAPPING     Port mapping       (default: $PORT_MAPPING)
EOF
}

build() {
  echo "→ Changing to script directory: $SCRIPT_DIR"
  cd "$SCRIPT_DIR" || { echo "Error: cannot cd to $SCRIPT_DIR"; exit 1; }

  echo "→ Building Docker image: $IMAGE_NAME"
  docker build --progress=plain -t "$IMAGE_NAME" .

  echo "→ Build complete."
}

run() {
  # Testen, ob das Netzwerk existiert, andernfalls erstellen
  if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    echo "Netzwerk '$NETWORK_NAME' existiert nicht. Erstelle Netzwerk..."
    docker network create "$NETWORK_NAME"
  else
    echo "Netzwerk '$NETWORK_NAME' ist bereits vorhanden."
  fi

  echo "→ Starting container '$CONTAINER_NAME' im Netzwerk $NETWORK_NAME..."
  echo "FT: $FORGEJO_TOKEN"
  # Stop and remove if already running
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

  # Try to start it
  if ! docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    -p "$PORT_MAPPING" \
    --restart unless-stopped \
    -e GITHUB_TOKEN_AGENT \
    -e FORGEJO_TOKEN \
    -e DEEPSEEK_API_KEY \
    -e SSH_PUBLIC_KEY \
    "$IMAGE_NAME"; then
    echo "❌ Failed to create container" >&2
    exit 1
  fi

  # Wait and check
  echo "→ Waiting up to 20 seconds for container to be running ..."
  sleep 1
  local waited=0
  while [ $waited -lt 20 ]; do
    if docker inspect "$CONTAINER_NAME" --format '{{.State.Running}}' 2>/dev/null | grep -q '^true$'; then
      echo "→ Container is running."
      echo "→ Connect with: ssh agent@localhost -p 2222"
      echo "→ Or open shell: $0 exec"
      return 0
    fi

    sleep 1
    ((waited++))
  done

  # If we get here → failure
  echo "❌ Container failed to start (not running after 20 seconds)" >&2
  echo "   Logs:" >&2
  docker logs "$CONTAINER_NAME" >&2 2>/dev/null || echo "   (no logs available)" >&2
  exit 1
}

stop() {
  echo "→ Stopping and removing container '$CONTAINER_NAME' ..."
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
  echo "→ Done."
}

logs() {
  docker logs -f "$CONTAINER_NAME" 2>&1
}

exec_shell() {
  docker exec -it "$CONTAINER_NAME" bash
}

# -----------------------------------------------------------------------------
# DeepSeek peak guard
#
# The container has no systemd and no Docker socket, so the guard lives on the
# host: a systemd timer (systemd/) calls `agent.sh peak-guard apply` at every
# peak boundary. `apply` is an idempotent reconcile: it derives the desired
# state from the current UTC time and pauses or unpauses the container.
# -----------------------------------------------------------------------------

peak_guard_usage() {
  cat << EOF
Usage: $(basename "$0") peak-guard <action>

Actions:
  enable     Enable and start the peak guard (units must be installed)
  disable    Disable the guard; unpauses a paused container first
  status     Show timer state and the container's actual/desired state;
             exits non-zero if the units are missing or the container is absent
  apply      Reconcile the container to the current peak/off-peak state

The guard pauses the container during DeepSeek peak windows
(Mon-Fri 01:00-04:00 and 06:00-10:00 UTC) and unpauses it otherwise.
The systemd units in systemd/ must be installed manually (see README).
EOF
}

# Return success when the current UTC time is inside a DeepSeek peak window.
peak_guard_is_peak() {
  local dow hour minute minutes
  read -r dow hour minute < <(date -u '+%u %H %M')
  minutes=$(( 10#$hour * 60 + 10#$minute ))

  # Mon-Fri (1-5), 01:00<=t<04:00 or 06:00<=t<10:00 UTC
  (( 10#$dow <= 5 )) || return 1
  (( (minutes >= 60 && minutes < 240) || (minutes >= 360 && minutes < 600) ))
}

# Print the state the container should be in right now.
peak_guard_desired_state() {
  if peak_guard_is_peak; then
    echo "paused"
  else
    echo "running"
  fi
}

peak_guard_units_installed() {
  systemctl cat "$PEAK_GUARD_SERVICE" >/dev/null 2>&1 &&
    systemctl cat "$PEAK_GUARD_TIMER" >/dev/null 2>&1
}

peak_guard_require_units() {
  peak_guard_units_installed && return 0
  {
    echo "❌ Peak-guard units are not installed."
    echo "   Install them first (see README):"
    echo "     sudo cp systemd/$PEAK_GUARD_SERVICE systemd/$PEAK_GUARD_TIMER /etc/systemd/system/"
    echo "     sudo systemctl daemon-reload"
  } >&2
  return 1
}

peak_guard_inspect() {
  docker inspect --format "$1" "$CONTAINER_NAME" 2>/dev/null
}

peak_guard_container_exists() {
  command -v docker >/dev/null 2>&1 &&
    docker inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

# Fail unless docker is available, the container exists, and it is not
# auto-removed (which would make pause/unpause unreliable).
peak_guard_require_target() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ docker not found on PATH." >&2
    return 1
  fi
  if ! peak_guard_container_exists; then
    echo "❌ Container '$CONTAINER_NAME' not found." >&2
    return 1
  fi
  if [[ "$(peak_guard_inspect '{{.HostConfig.AutoRemove}}')" == "true" ]]; then
    echo "❌ Container '$CONTAINER_NAME' has AutoRemove set; refusing to pause it." >&2
    return 1
  fi
}

peak_guard_apply() {
  peak_guard_require_target || return 1

  local desired running paused
  desired="$(peak_guard_desired_state)"
  running="$(peak_guard_inspect '{{.State.Running}}')"

  # On boot the timer's Persistent catch-up can fire before Docker has
  # restarted the container. When we need it paused, give Docker a moment.
  if [[ "$running" != "true" && "$desired" == "paused" ]]; then
    local _
    for _ in {1..30}; do
      sleep 2
      if [[ "$(peak_guard_inspect '{{.State.Running}}')" == "true" ]]; then
        running="true"
        break
      fi
    done
  fi

  if [[ "$running" != "true" ]]; then
    echo "→ Container '$CONTAINER_NAME' is not running; nothing to do."
    return 0
  fi

  paused="$(peak_guard_inspect '{{.State.Paused}}')"

  if [[ "$desired" == "paused" && "$paused" == "true" ]]; then
    echo "→ Container '$CONTAINER_NAME' already paused (peak window)."
    return 0
  fi
  if [[ "$desired" == "running" && "$paused" == "false" ]]; then
    echo "→ Container '$CONTAINER_NAME' already running (off-peak)."
    return 0
  fi

  if [[ "$desired" == "paused" ]]; then
    docker pause "$CONTAINER_NAME" >/dev/null
    echo "→ Paused '$CONTAINER_NAME' (DeepSeek peak window)."
  else
    docker unpause "$CONTAINER_NAME" >/dev/null
    echo "→ Unpaused '$CONTAINER_NAME' (off-peak)."
  fi
}

peak_guard_enable() {
  peak_guard_require_units || return 1
  systemctl enable --now "$PEAK_GUARD_TIMER"
  echo "→ Peak guard enabled."
}

peak_guard_disable() {
  peak_guard_require_units || return 1

  if peak_guard_container_exists &&
     [[ "$(peak_guard_inspect '{{.State.Paused}}')" == "true" ]]; then
    docker unpause "$CONTAINER_NAME" >/dev/null
    echo "→ Unpaused '$CONTAINER_NAME' before disabling."
  fi

  systemctl disable --now "$PEAK_GUARD_TIMER"
  echo "→ Peak guard disabled."
}

peak_guard_status() {
  local rc=0 desired
  desired="$(peak_guard_desired_state)"

  if peak_guard_units_installed; then
    local enabled active
    enabled="$(systemctl is-enabled "$PEAK_GUARD_TIMER" 2>/dev/null || true)"
    active="$(systemctl is-active "$PEAK_GUARD_TIMER" 2>/dev/null || true)"
    echo "Timer:     ${enabled:-unknown} / ${active:-unknown}"
  else
    echo "Timer:     not installed (see README)"
    rc=1
  fi

  if peak_guard_container_exists; then
    local running paused
    running="$(peak_guard_inspect '{{.State.Running}}')"
    paused="$(peak_guard_inspect '{{.State.Paused}}')"
    if [[ "$running" != "true" ]]; then
      echo "Container: $CONTAINER_NAME not running"
    elif [[ "$paused" == "true" ]]; then
      echo "Container: $CONTAINER_NAME paused"
    else
      echo "Container: $CONTAINER_NAME running"
    fi
  else
    echo "Container: $CONTAINER_NAME not found"
    rc=1
  fi

  if [[ "$desired" == "paused" ]]; then
    echo "Desired:   paused (peak window)"
  else
    echo "Desired:   running (off-peak)"
  fi

  return "$rc"
}

peak_guard_dispatch() {
  case "${1:-}" in
    enable)  peak_guard_enable ;;
    disable) peak_guard_disable ;;
    status)  peak_guard_status ;;
    apply)   peak_guard_apply ;;
    "" )     peak_guard_usage; return 1 ;;
    help|--help|-h) peak_guard_usage ;;
    *)
      echo "Unknown peak-guard action: $1" >&2
      peak_guard_usage
      return 1
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Main command dispatch
# -----------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ $# -eq 0 ]; then
    usage
    exit 1
  fi

  case "$1" in
    build)
      build
      ;;
    run)
      run
      ;;
    stop)
      stop
      ;;
    logs)
      logs
      ;;
    exec)
      exec_shell
      ;;
    peak-guard)
      shift
      peak_guard_dispatch "$@"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      echo "Unknown command: $1"
      usage
      exit 1
      ;;
  esac
fi
