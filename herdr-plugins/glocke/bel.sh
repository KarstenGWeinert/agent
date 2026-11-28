#!/usr/bin/env bash
# Schickt ein Terminal-BEL an alle Herdr-Clients, sobald ein Agent aufhoert zu
# arbeiten. Kein Netzzugriff, keine Abhaengigkeiten ausser jq.
#
# Warum direkt auf das PTY und nicht in ein Pane: die Ausgabe eines Event-Hooks
# landet in `herdr plugin log`, nicht auf dem Terminal. Das PTY des Clients ist
# der einzige Kanal, der ueber SSH beim lokalen Terminal-Emulator ankommt.

set -uo pipefail

log_dir="${HERDR_PLUGIN_STATE_DIR:-/tmp}"
log="$log_dir/bel.log"

status="$(printf '%s' "${HERDR_PLUGIN_EVENT_JSON:-}" \
  | jq -r '.. | .agent_status? // empty' 2>/dev/null | head -n1)"

case "$status" in
  blocked) bel=$'\a\a' ;;   # will Eingabe  -> zweimal
  done)    bel=$'\a'   ;;   # fertig        -> einmal
  *)       exit 0      ;;
esac

sent=0
for pid in $(pgrep -x herdr 2>/dev/null); do
  tty="$(readlink "/proc/$pid/fd/0" 2>/dev/null)" || continue
  [[ $tty == /dev/pts/* && -w $tty ]] || continue
  printf '%s' "$bel" > "$tty" 2>/dev/null && sent=$((sent + 1))
done

printf '[%s] status=%s clients=%s\n' "$(date -Iseconds)" "$status" "$sent" \
  >> "$log" 2>/dev/null || true

exit 0
