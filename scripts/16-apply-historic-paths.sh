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

MODE="${1:-dry-run}"
BATCH_SIZE="${2:-5}"
CLEANUP="${3:-}"
MAP="${HISTORIC_MAP_VALIDATED}"
RPC="${RECOVERY_ROOT}/lib/rtorrent-rpc.php"
TORRENT_SOURCE="${HISTORIC_TORRENT_DIR}"
STAGING="${ENTWARE_ROOT}/import-historic"
REPORT="${BACKUP_ROOT}/apply-historic-paths-$(date +%Y%m%d-%H%M%S).tsv"
WORK="${BACKUP_ROOT}/apply-historic-work.$$"

[ -f "$MAP" ] || die "Validated map not found: $MAP (run steps 14-15 first)"
[ -f "$RPC" ] || die "Missing XMLRPC helper: $RPC"
[ -S "$SCGI_SOCKET" ] || die "rtorrent SCGI socket missing: $SCGI_SOCKET"
mkdir -p "$STAGING"

php_bin="/opt/bin/php8-cli"
[ -x "$php_bin" ] || php_bin="/opt/bin/php"

rpc() {
  RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" "$php_bin" "$RPC" "$@"
}

hash_lc() {
  echo "$1" | tr 'A-F' 'a-f'
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
  rpc load.normal "$staged" >/dev/null 2>&1 || rpc load "$staged" >/dev/null 2>&1 || return 1
  sleep 1
  torrent_is_loaded "$hash"
}

log "=== Step 16: Apply historic paths ==="
log "Mode: $MODE"
log "Map: $MAP"
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

applied=0
tail -n +2 "$WORK" | while IFS="$(printf '\t')" read -r hash name old_path new_path exists_at status source via; do
  [ -n "$hash" ] || continue
  [ -n "$new_path" ] || continue

  torrent_file="${TORRENT_SOURCE}/${hash}.torrent"
  if [ ! -f "$torrent_file" ]; then
    torrent_file="$(find "$TORRENT_SOURCE" -maxdepth 2 -type f -iname "${hash}.torrent" 2>/dev/null | head -1)"
  fi

  echo "PLAN: $name"
  echo "  -> $new_path"

  if [ "$MODE" = "dry-run" ]; then
    echo "$hash	$name	$old_path	$new_path	$status	DRY_RUN" >> "$REPORT"
    continue
  fi

  if [ ! -f "$torrent_file" ]; then
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
  rpc d.directory.set "$hash_lc" "$new_path" >/dev/null
  rpc d.check_hash "$hash_lc" >/dev/null 2>&1 || true

  echo "$hash	$name	$old_path	$new_path	$status	APPLIED" >> "$REPORT"
  log "APPLIED: $name -> $new_path"
  applied=$((applied + 1))
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
