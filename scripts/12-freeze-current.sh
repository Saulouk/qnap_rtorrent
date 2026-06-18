#!/bin/sh
# Step 12: Freeze current Entware rtorrent state — stop all torrents and watch imports.
#
# Usage:
#   sh scripts/12-freeze-current.sh
#   sh scripts/12-freeze-current.sh unfreeze

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path

MODE="${1:-freeze}"
RPC="${RECOVERY_ROOT}/lib/rtorrent-rpc.php"
FREEZE_MARKER="${ENTWARE_ROOT}/.frozen"
WATCH_BACKUP="${ENTWARE_ROOT}/watch.frozen-backup"

[ -f "$RPC" ] || die "Missing XMLRPC helper: $RPC"

rpc() {
    RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" /opt/bin/php8-cli "$RPC" "$@"
}

log "=== Step 12: Freeze current torrent activity ==="
log "Mode: $MODE"

if [ "$MODE" = "unfreeze" ]; then
  if [ -d "$WATCH_BACKUP" ]; then
    rm -rf "$ENTWARE_WATCH"
    mv "$WATCH_BACKUP" "$ENTWARE_WATCH"
    log "Restored watch directory from $WATCH_BACKUP"
  fi
  rm -f "$FREEZE_MARKER"
  log "Unfrozen. Re-add watch dirs to rtorrent.conf if needed, then restart rtorrent."
  exit 0
fi

if [ ! -S "$SCGI_SOCKET" ]; then
  log "WARNING: SCGI socket missing — rtorrent may not be running."
  log "Creating freeze marker anyway so imports do not auto-start later."
  date > "$FREEZE_MARKER"
  exit 0
fi

stopped=0
for view in main started; do
  hashes_json="$(rpc download_list "$view" 2>/dev/null || true)"
  echo "$hashes_json" | tr -d '[]" ' | tr ',' '\n' | sed '/^$/d' | while read -r hash; do
    [ -n "$hash" ] || continue
  name="$(rpc d.name "$hash" 2>/dev/null || echo "$hash")"
  rpc d.stop "$hash" >/dev/null 2>&1 && {
    log "Stopped: $name"
    stopped=$((stopped + 1))
  } || log "Could not stop: $name"
  done
done

if [ -d "$ENTWARE_WATCH" ] && [ ! -d "$WATCH_BACKUP" ]; then
  mv "$ENTWARE_WATCH" "$WATCH_BACKUP"
  mkdir -p "$ENTWARE_WATCH"
  log "Moved watch dir aside to $WATCH_BACKUP (prevents new auto-imports)"
fi

date > "$FREEZE_MARKER"
log "Freeze marker: $FREEZE_MARKER"
log "Stopped torrents (best effort). Verify in ruTorrent that nothing is active."
log "To restore watch imports later: sh scripts/12-freeze-current.sh unfreeze"
