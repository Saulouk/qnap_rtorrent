#!/bin/sh
# Retarget already-loaded torrents using the validated historic path map.
#
# This is for cases where torrents imported successfully, but their save paths
# are empty/default in rtorrent. It does not import new torrents.
#
# Usage:
#   sh scripts/17-retarget-loaded-paths.sh
#   sh scripts/17-retarget-loaded-paths.sh apply

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path
ensure_php_xml

MODE="${1:-dry-run}"
APPLY=0
[ "$MODE" = "apply" ] && APPLY=1

MAP="${HISTORIC_MAP_VALIDATED}"
RPC="${RECOVERY_ROOT}/lib/rtorrent-rpc.php"
REPORT="${BACKUP_ROOT}/retarget-loaded-paths-$(date +%Y%m%d-%H%M%S).tsv"

[ -f "$MAP" ] || die "Validated map not found: $MAP"
[ -f "$RPC" ] || die "Missing XMLRPC helper: $RPC"
[ -S "$SCGI_SOCKET" ] || die "rtorrent SCGI socket missing: $SCGI_SOCKET"

php_bin="/opt/bin/php8-cli"
[ -x "$php_bin" ] || php_bin="/opt/bin/php"

rpc() {
  RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" "$php_bin" "$RPC" "$@"
}

hash_lc() {
  printf '%s' "$1" | tr 'A-F' 'a-f'
}

loaded_hashes() {
  rpc download_list 2>/dev/null | tr -d '[]" ' | tr ',' '\n' | sed '/^$/d' | tr 'A-F' 'a-f'
}

is_loaded() {
  h="$(hash_lc "$1")"
  printf '%s\n' "$LOADED" | grep -qi "^${h}$"
}

choose_setter() {
  name="$1"
  new_path="$2"
  exists_at="$3"

  # If the verified object is exactly the path itself, then the saved path is a
  # full base path (typical multi-file torrent folder). Otherwise, new_path is
  # a parent directory and d.directory.set should be used.
  if [ "$exists_at" = "$new_path" ]; then
    echo "d.directory_base.set"
    return 0
  fi

  base="$(basename "$new_path" 2>/dev/null || echo "")"
  if [ "$base" = "$name" ] && [ -d "$new_path" ]; then
    echo "d.directory_base.set"
    return 0
  fi

  echo "d.directory.set"
}

log "=== Retarget already-loaded torrents ==="
log "Mode: $([ "$APPLY" = 1 ] && echo apply || echo dry-run)"
log "Map: $MAP"
log "Report: $REPORT"

LOADED="$(loaded_hashes)"
loaded_count="$(printf '%s\n' "$LOADED" | sed '/^$/d' | wc -l | tr -d ' ')"
log "Loaded torrents: $loaded_count"

{
  echo "hash	name	new_path	exists_at	setter	before_directory	after_directory	after_directory_base	result"
} > "$REPORT"

matched=0
applied=0
missing=0
failed=0

tail -n +2 "$MAP" | while IFS="$(printf '\t')" read -r hash name old_path new_path exists_at status source via; do
  [ "$status" = "OK" ] || continue
  [ -n "$hash" ] || continue
  [ -n "$new_path" ] || continue

  h="$(hash_lc "$hash")"
  if ! is_loaded "$h"; then
    missing=$((missing + 1))
    continue
  fi

  matched=$((matched + 1))
  setter="$(choose_setter "$name" "$new_path" "$exists_at")"
  before="$(rpc d.directory "$h" 2>/dev/null || true)"

  if [ "$APPLY" = 1 ]; then
    rpc d.stop "$h" >/dev/null 2>&1 || true
    if rpc "$setter" "$h" "$new_path" >/dev/null 2>&1; then
      rpc d.save_full_session "$h" >/dev/null 2>&1 || true
      rpc d.check_hash "$h" >/dev/null 2>&1 || true
      result="APPLIED"
      applied=$((applied + 1))
    else
      result="SET_FAILED"
      failed=$((failed + 1))
    fi
  else
    result="DRY_RUN"
  fi

  after="$(rpc d.directory "$h" 2>/dev/null || true)"
  after_base="$(rpc d.directory_base "$h" 2>/dev/null || true)"
  echo "$hash	$name	$new_path	$exists_at	$setter	$before	$after	$after_base	$result" >> "$REPORT"
  log "$result: $name -> $new_path ($setter)"
done

log "Report: $REPORT"
log "Run for real with: sh scripts/17-retarget-loaded-paths.sh apply"
