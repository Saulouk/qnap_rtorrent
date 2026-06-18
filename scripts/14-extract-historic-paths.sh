#!/bin/sh
# Step 14: Extract hash/name/old-path map from historic backups (bencode + strings).
#
# Usage:
#   sh scripts/14-extract-historic-paths.sh
#   sh scripts/14-extract-historic-paths.sh /path/to/session.bak... /share/SN
#
# With filesystem fallback for torrents missing metadata paths:
#   sh scripts/14-extract-historic-paths.sh /path/to/torrents /share/SN fallback

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path

PRIMARY_SOURCE="${1:-/share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720}"
if [ -z "$PRIMARY_SOURCE" ] || [ ! -d "$PRIMARY_SOURCE" ]; then
  PRIMARY_SOURCE="/share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720"
fi
DATA_ROOT="${2:-/share/SN}"
FALLBACK="${3:-}"
STAMP="$(date +%Y%m%d-%H%M%S)"
MAP="${BACKUP_ROOT}/historic-path-map-${STAMP}.tsv"
EXTRACT="${RECOVERY_ROOT}/lib/extract-historic-paths.php"
FALLBACK_PHP="${RECOVERY_ROOT}/lib/filesystem-path-fallback.php"
SOURCES_LIST="${BACKUP_ROOT}/path-sources-latest.list"

[ -f "$EXTRACT" ] || die "Missing extractor: $EXTRACT"
php_bin="/opt/bin/php8-cli"
[ -x "$php_bin" ] || php_bin="/opt/bin/php"
[ -x "$php_bin" ] || die "php8-cli not found"

mkdir -p "$BACKUP_ROOT"
: > "$MAP"
echo "hash	name	old_path	source	via" > "$MAP"

log "=== Step 14: Extract historic path map ==="
log "Primary source: $PRIMARY_SOURCE"
log "Output: $MAP"

scan_dir() {
  dir="$1"
  [ -d "$dir" ] || return 0
  tmp="${BACKUP_ROOT}/historic-path-map.partial.$$"
  "$php_bin" "$EXTRACT" "$dir" "$tmp" || true
  if [ -f "$tmp" ]; then
    tail -n +2 "$tmp" >> "$MAP"
    rm -f "$tmp"
    log "Scanned: $dir"
  fi
}

scan_dir "$PRIMARY_SOURCE"

if [ -f "$SOURCES_LIST" ]; then
  while read -r dir; do
    [ -n "$dir" ] || continue
    [ "$dir" = "$PRIMARY_SOURCE" ] && continue
    scan_dir "$dir"
  done < "$SOURCES_LIST"
else
  for dir in \
    /share/Rdownload/session.disabled-debug \
    /share/CACHEDEV1_DATA/Rdownload/settings \
    /share/CACHEDEV1_DATA/.qpkg/rtorrent/var; do
    scan_dir "$dir"
  done
fi

log "Scanning archived session tarballs (if any)..."
for tarf in $(find /share/Public/rtorrent-debug-backup /share/Rdownload /share/CACHEDEV1_DATA/Rdownload \
  -maxdepth 4 -type f \( -name 'session*.tar' -o -name 'session*.tar.gz' -o -name 'session*.tgz' \) 2>/dev/null); do
  tmp="${BACKUP_ROOT}/tar-extract.$$"
  mkdir -p "$tmp"
  if tar -xf "$tarf" -C "$tmp" 2>/dev/null; then
    scan_dir "$tmp"
    log "Scanned tarball: $tarf"
  fi
  rm -rf "$tmp"
done

# Deduplicate by hash (keep first = highest priority source order)
dedup="${MAP}.dedup"
{
  head -n 1 "$MAP"
  tail -n +2 "$MAP" | awk -F'\t' '!seen[$1]++'
} > "$dedup"
mv "$dedup" "$MAP"

rows="$(tail -n +2 "$MAP" | wc -l | tr -d ' ')"
log "Extracted $rows rows with path metadata"

if [ "$FALLBACK" = "fallback" ] || [ "$rows" -lt 10 ]; then
  log "Running filesystem fallback under $DATA_ROOT ..."
  [ -f "$FALLBACK_PHP" ] || die "Missing fallback helper: $FALLBACK_PHP"
  "$php_bin" "$FALLBACK_PHP" "$PRIMARY_SOURCE" "$DATA_ROOT" "$MAP"
fi

ln -sfn "$(basename "$MAP")" "${BACKUP_ROOT}/historic-path-map-latest.tsv"
log "Path map: $MAP"
log "Latest symlink: ${BACKUP_ROOT}/historic-path-map-latest.tsv"
