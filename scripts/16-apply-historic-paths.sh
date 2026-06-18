#!/bin/sh
# Step 16: Apply historic paths via d.directory.set + d.check_hash.
#
# Dry run (first 5 OK rows):
#   sh scripts/16-apply-historic-paths.sh
#
# Apply small batch:
#   sh scripts/16-apply-historic-paths.sh apply 5
#
# Apply all OK rows:
#   sh scripts/16-apply-historic-paths.sh apply-all
#
# Apply all + remove wrong Entware partial downloads:
#   sh scripts/16-apply-historic-paths.sh apply-all cleanup

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path
ensure_php_xml

MODE="${1:-dry-run}"
BATCH_SIZE="${2:-5}"
CLEANUP="${3:-}"
MAP="${HISTORIC_MAP_VALIDATED}"
RPC="${RECOVERY_ROOT}/lib/rtorrent-rpc.php"
IMPORT_PHP="${RECOVERY_ROOT}/lib/import-torrent.php"
TORRENT_SOURCE="${HISTORIC_TORRENT_DIR}"
STAGING="${ENTWARE_ROOT}/import-historic"
WATCH_LOAD="${ENTWARE_WATCH}/load"
REPORT="${BACKUP_ROOT}/apply-historic-paths-$(date +%Y%m%d-%H%M%S).tsv"
WORK="${BACKUP_ROOT}/apply-historic-work.$$"

[ -f "$MAP" ] || die "Validated map not found: $MAP (run steps 14-15 first)"
[ -f "$RPC" ] || die "Missing XMLRPC helper: $RPC"
[ -f "$IMPORT_PHP" ] || die "Missing import helper: $IMPORT_PHP"
[ -d "$TORRENT_SOURCE" ] || die "Torrent source not found: $TORRENT_SOURCE"
mkdir -p "$STAGING" "$WATCH_LOAD"

php_bin="/opt/bin/php8-cli"
[ -x "$php_bin" ] || php_bin="/opt/bin/php"

if [ ! -S "$SCGI_SOCKET" ]; then
  log "WARNING: SCGI socket missing. Restart stack first:"
  log "  sh scripts/18-restart-stack.sh"
  die "rtorrent SCGI socket missing: $SCGI_SOCKET"
fi

rpc() {
  RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" "$php_bin" "$RPC" "$@"
}

rpc_err() {
  RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" "$php_bin" "$RPC" "$@" 2>&1
}

hash_lc() {
  printf '%s' "$1" | tr 'A-F' 'a-f'
}

torrent_is_loaded() {
  hash="$(hash_lc "$1")"
  rpc download_list 2>/dev/null | tr -d '[]" ' | tr ',' '\n' | grep -qi "^${hash}$"
}

import_torrent_stopped() {
  torrent_file="$1"
  hash="$(hash_lc "$2")"
  if torrent_is_loaded "$hash"; then
    return 0
  fi
  staged="${STAGING}/${hash}.torrent"
  cp "$torrent_file" "$staged"

  err_file="${BACKUP_ROOT}/import-torrent.err.$$"
  if RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" "$php_bin" "$IMPORT_PHP" "$staged" >"${BACKUP_ROOT}/import-torrent.out.$$" 2>"$err_file"; then
    sleep 2
    torrent_is_loaded "$hash" && return 0
  fi

  # Fallback: rtorrent watch schedule uses load.normal on this folder.
  cp "$staged" "${WATCH_LOAD}/${hash}.torrent"
  i=0
  while [ "$i" -lt 15 ]; do
    sleep 2
    torrent_is_loaded "$hash" && return 0
    i=$((i + 1))
  done

  log "  import failed: $(head -3 "$err_file" 2>/dev/null | tr '\n' ' ')"
  rm -f "$err_file" "${BACKUP_ROOT}/import-torrent.out.$$"
  return 1
}

log "=== Step 16: Apply historic paths ==="
log "Mode: $MODE"
log "Map: $MAP"
log "Torrent source: $TORRENT_SOURCE"
log "Report: $REPORT"

limit=999999
case "$MODE" in
  dry-run|apply) limit="$BATCH_SIZE" ;;
  apply-all) limit=999999 ;;
  *) die "Unknown mode: $MODE (use dry-run, apply, or apply-all)" ;;
esac

awk -F'\t' -v lim="$limit" 'NR==1 || ($6=="OK" && ++n<=lim)' "$MAP" > "$WORK"

{
  echo "hash	name	old_path	new_path	status	result"
} > "$REPORT"

tail -n +2 "$WORK" | while IFS="$(printf '\t')" read -r hash name old_path new_path exists_at status source via; do
  [ -n "$hash" ] || continue
  [ -n "$new_path" ] || continue

  torrent_file="$(find_torrent_by_hash "$hash" "$TORRENT_SOURCE")"

  echo "PLAN: $name"
  echo "  -> $new_path"

  if [ "$MODE" = "dry-run" ]; then
    echo "$hash	$name	$old_path	$new_path	$status	DRY_RUN" >> "$REPORT"
    continue
  fi

  if [ -z "$torrent_file" ] || [ ! -f "$torrent_file" ]; then
    echo "$hash	$name	$old_path	$new_path	$status	NO_TORRENT_FILE" >> "$REPORT"
    log "SKIP (no .torrent): $hash"
    continue
  fi

  hash_lc="$(hash_lc "$hash")"

  if ! import_torrent_stopped "$torrent_file" "$hash"; then
    echo "$hash	$name	$old_path	$new_path	$status	IMPORT_FAILED" >> "$REPORT"
    log "IMPORT FAILED: $name"
    continue
  fi

  rpc d.stop "$hash_lc" >/dev/null 2>&1 || true
  if ! rpc d.directory.set "$hash_lc" "$new_path" >/dev/null 2>&1; then
    echo "$hash	$name	$old_path	$new_path	$status	DIRECTORY_SET_FAILED" >> "$REPORT"
    log "DIRECTORY SET FAILED: $name"
    continue
  fi
  rpc d.check_hash "$hash_lc" >/dev/null 2>&1 || true

  echo "$hash	$name	$old_path	$new_path	$status	APPLIED" >> "$REPORT"
  log "APPLIED: $name -> $new_path"
done

rm -f "$WORK"
log "Report: $REPORT"

if [ "$MODE" = "apply" ]; then
  log "Batch applied (max $BATCH_SIZE). Verify in ruTorrent, then:"
  log "  sh scripts/16-apply-historic-paths.sh apply-all"
elif [ "$MODE" = "apply-all" ] && [ "$CLEANUP" = "cleanup" ]; then
  log "=== Cleanup wrong Entware downloads (partial only) ==="
  if [ -d "$ENTWARE_DOWNLOADS" ]; then
    find "$ENTWARE_DOWNLOADS" -mindepth 1 -maxdepth 3 -type d 2>/dev/null | while read -r d; do
      if find "$d" -type f -name '*.part' 2>/dev/null | grep -q .; then
        log "Removing partial: $d"
        rm -rf "$d"
      fi
    done
  fi
  log "Cleanup complete. Old QPKG backups left intact."
fi
