#!/bin/sh
# Step 13: Inventory every old path-bearing candidate (sessions, sidecars, settings, backups).
#
# Usage:
#   sh scripts/13-find-path-sources.sh
#
# Output:
#   /share/Public/rtorrent-debug-backup/path-sources-<stamp>.txt
#   /share/Public/rtorrent-debug-backup/path-sources-<stamp>.list

set -e
. "$(dirname "$0")/../lib/common.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${BACKUP_ROOT}/path-sources-${STAMP}.txt"
LIST="${BACKUP_ROOT}/path-sources-${STAMP}.list"
mkdir -p "$BACKUP_ROOT"

log "=== Step 13: Find historic path sources ==="
log "Report: $REPORT"
log "Source list: $LIST"

: > "$LIST"

append_dir_if_useful() {
  dir="$1"
  [ -d "$dir" ] || return 0
  count="$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
  echo "  DIR $dir ($count files)" >> "$REPORT"
  echo "$dir" >> "$LIST"
}

{
  echo "Historic path source inventory - $STAMP"
  echo "Host: $(hostname 2>/dev/null || echo unknown)"
  echo ""

  echo "=== Candidate directories ==="
  for d in \
    /share/Rdownload/session.disabled-debug \
    /share/CACHEDEV1_DATA/Rdownload/session.disabled-debug \
    /share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720 \
    /share/CACHEDEV1_DATA/Rdownload/settings \
    /share/Rdownload/settings \
    /share/CACHEDEV1_DATA/.qpkg/rtorrent/var \
    /share/CACHEDEV1_DATA/.qpkg/rtorrent/share \
    /share/Public/rtorrent-debug-backup \
    /share/SN; do
    append_dir_if_useful "$d"
  done

  echo ""
  echo "=== session.bak* directories ==="
  for root in /share/Rdownload /share/CACHEDEV1_DATA/Rdownload /share/CACHEDEV2_DATA/Rdownload; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 2 -type d -name 'session.bak*' 2>/dev/null | while read -r d; do
      append_dir_if_useful "$d"
    done
  done

  echo ""
  echo "=== Sidecar and session file counts ==="
  for d in $(sort -u "$LIST"); do
    [ -d "$d" ] || continue
    tc="$(find "$d" -type f -name '*.torrent' 2>/dev/null | wc -l | tr -d ' ')"
    rt="$(find "$d" -type f -name '*.torrent.rtorrent' 2>/dev/null | wc -l | tr -d ' ')"
    lr="$(find "$d" -type f -name '*.torrent.libtorrent_resume' 2>/dev/null | wc -l | tr -d ' ')"
    sess="$(find "$d" -maxdepth 3 -type f 2>/dev/null | while read -r f; do
      b="$(basename "$f")"
      echo "$b" | grep -Eq '^[0-9a-fA-F]{40}$' && echo 1
    done | wc -l | tr -d ' ')"
    echo "  $d: .torrent=$tc .rtorrent=$rt .libtorrent_resume=$lr bare_hash=$sess"
  done

  echo ""
  echo "=== Archived session tarballs ==="
  find /share/Public/rtorrent-debug-backup /share/Rdownload /share/CACHEDEV1_DATA/Rdownload \
    -maxdepth 4 -type f \( -name 'session*.tar*' -o -name '*session*.tgz' -o -name '*session*.gz' \) 2>/dev/null

  echo ""
  echo "=== ruTorrent plugin/history candidates ==="
  find /share/Rdownload/settings /share/CACHEDEV1_DATA/Rdownload/settings \
    -maxdepth 6 -type f \( \
      -name '*.dat' -o -name '*.json' -o -name '*.php' -o -name 'history*' -o -name '*labels*' \
    \) 2>/dev/null | head -200

  echo ""
  echo "=== Path strings in settings (text scan) ==="
  if command -v strings >/dev/null 2>&1; then
    for f in /share/Rdownload/settings/* /share/CACHEDEV1_DATA/Rdownload/settings/*; do
      [ -f "$f" ] || continue
      strings "$f" 2>/dev/null | grep -E '/share/|Movies|Drama Series|Software' | sed "s|^|$f: |" | head -50
    done
  else
    echo "  strings not available"
  fi

  echo ""
  echo "=== Sample sidecar path strings (first 20 files) ==="
  if command -v strings >/dev/null 2>&1; then
    find /share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720 \
      -maxdepth 1 -type f -name '*.torrent.rtorrent' 2>/dev/null | head -20 | while read -r f; do
      hits="$(strings "$f" 2>/dev/null | grep -E '/share/|Movies|Drama Series|Software' | head -5)"
      if [ -n "$hits" ]; then
        echo "--- $f ---"
        echo "$hits"
      fi
    done
  fi
} > "$REPORT"

ln -sfn "$(basename "$REPORT")" "${BACKUP_ROOT}/path-sources-latest.txt"
ln -sfn "$(basename "$LIST")" "${BACKUP_ROOT}/path-sources-latest.list"

cat "$REPORT"
log "Step 13 complete. Use path-sources-latest.list with step 14."
