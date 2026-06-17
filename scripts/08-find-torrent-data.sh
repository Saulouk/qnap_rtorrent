#!/bin/sh
# Locate old .torrent files and rtorrent session metadata after QPKG migration.

set -e
. "$(dirname "$0")/../lib/common.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${BACKUP_ROOT}/torrent-data-search-${STAMP}.txt"
mkdir -p "$BACKUP_ROOT"

log "=== Step 8: Find old torrent data ==="
log "Report: $REPORT"

{
    echo "QNAP rtorrent torrent-data search - $STAMP"
    echo "Host: $(hostname 2>/dev/null || echo unknown)"
    echo "Kernel: $(uname -a)"
    echo ""

    echo "Known rtorrent/Rdownload directories:"
    for d in \
        /share/Rdownload \
        /share/CACHEDEV1_DATA/Rdownload \
        /share/CACHEDEV2_DATA/Rdownload \
        /share/CACHEDEV1_DATA/.qpkg/rtorrent \
        /share/CACHEDEV2_DATA/.qpkg/rtorrent \
        /share/Public/rtorrent-debug-backup; do
        if [ -e "$d" ]; then
            echo "  EXISTS: $d"
            ls -ld "$d" 2>/dev/null || true
        else
            echo "  missing: $d"
        fi
    done
    echo ""

    echo "Session-like directories under likely roots:"
    for root in /share/Rdownload /share/CACHEDEV1_DATA/Rdownload /share/CACHEDEV1_DATA/.qpkg/rtorrent /share/Public; do
        [ -d "$root" ] || continue
        find "$root" -maxdepth 5 -type d \( -iname '*session*' -o -iname '*torrent*' -o -iname '*watch*' \) 2>/dev/null
    done | sort -u
    echo ""

    echo ".torrent files under likely roots:"
    for root in /share/Rdownload /share/CACHEDEV1_DATA/Rdownload /share/CACHEDEV1_DATA/.qpkg/rtorrent /share/Public; do
        [ -d "$root" ] || continue
        find "$root" -maxdepth 8 -type f -name '*.torrent' 2>/dev/null
    done | sort -u
    echo ""

    echo "rtorrent 40-char session metadata candidates:"
    for root in /share/Rdownload /share/CACHEDEV1_DATA/Rdownload /share/CACHEDEV1_DATA/.qpkg/rtorrent /share/Public; do
        [ -d "$root" ] || continue
        find "$root" -maxdepth 8 -type f 2>/dev/null | while read -r f; do
            b="$(basename "$f")"
            echo "$b" | grep -Eq '^[0-9a-fA-F]{40}$' && echo "$f"
        done
    done | sort -u
    echo ""

    echo "Likely download data directories and sizes:"
    for d in \
        /share/Rdownload/downloads \
        /share/Rdownload/complete \
        /share/Rdownload/incomplete \
        /share/CACHEDEV1_DATA/Rdownload/downloads \
        /share/CACHEDEV1_DATA/Rdownload/complete \
        /share/CACHEDEV1_DATA/Rdownload/incomplete; do
        [ -d "$d" ] && du -sh "$d" 2>/dev/null
    done
    echo ""

    echo "Path strings found in candidate metadata:"
    if command -v strings >/dev/null 2>&1; then
        for root in /share/Rdownload /share/CACHEDEV1_DATA/Rdownload /share/CACHEDEV1_DATA/.qpkg/rtorrent; do
            [ -d "$root" ] || continue
            find "$root" -maxdepth 8 -type f 2>/dev/null | while read -r f; do
                b="$(basename "$f")"
                case "$b" in
                    *.torrent|*.dat|*.gz|*.response|*.pid|*.lock) ;;
                    *)
                        echo "$b" | grep -Eq '^[0-9a-fA-F]{40}$' || continue
                        strings "$f" 2>/dev/null | grep -E '^/(share|mnt|home|volume)' | sed "s|^|$f: |"
                        ;;
                esac
            done
        done | sort -u
    else
        echo "  strings command not available"
    fi
} > "$REPORT"

cat "$REPORT"
log "Step 8 complete."
