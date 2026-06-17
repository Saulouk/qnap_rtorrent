#!/bin/sh
# Step 1: Backup and inventory old QPKG, session, settings, watch, download paths

set -e
. "$(dirname "$0")/../lib/common.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
INV_DIR="${BACKUP_ROOT}/inventory-${STAMP}"
mkdir -p "$INV_DIR"

log "=== Step 1: Backup and inventory ==="
log "Backup directory: $INV_DIR"

# QPKG config
if [ -f /etc/config/qpkg.conf ]; then
    cp /etc/config/qpkg.conf "$INV_DIR/qpkg.conf"
fi

RT_QPKG="/share/CACHEDEV1_DATA/.qpkg/rtorrent"
for f in etc/rtorrent.conf etc/lighttpd/lighttpd.conf var/www/ui/rtorrent/conf/config.php; do
    if [ -f "${RT_QPKG}/${f}" ]; then
        mkdir -p "$INV_DIR/qpkg/$(dirname "$f")"
        cp "${RT_QPKG}/${f}" "$INV_DIR/qpkg/${f}"
    fi
done

# Rdownload data areas
for dir in settings watch logs downloads; do
    src="${RDLINK}/${dir}"
    if [ -d "$src" ]; then
        log "Backing up $src ..."
        mkdir -p "$INV_DIR/rdownload"
        tar -cf "$INV_DIR/rdownload/${dir}.tar" -C "$RDLINK" "$dir" 2>/dev/null || true
    fi
done

# Old session (metadata only listing + small sample, full copy if space allows)
if [ -d "$OLD_SESSION" ]; then
    log "Inventorying old session: $OLD_SESSION"
    mkdir -p "$INV_DIR/session"
    ls -la "$OLD_SESSION" > "$INV_DIR/session/file-list.txt" 2>/dev/null || true
    find "$OLD_SESSION" -maxdepth 1 -type f | wc -l > "$INV_DIR/session/file-count.txt"
    du -sh "$OLD_SESSION" > "$INV_DIR/session/size.txt" 2>/dev/null || true

    # Count torrent metadata files (40-char hex names)
    find "$OLD_SESSION" -maxdepth 1 -type f -name '[0-9a-f][0-9a-f]*' 2>/dev/null | wc -l > "$INV_DIR/session/torrent-meta-count.txt" || true
    find "$OLD_SESSION" -maxdepth 1 -type f -name '*.torrent' 2>/dev/null | wc -l > "$INV_DIR/session/dot-torrent-count.txt" || true

    # Full session backup (can be large)
    log "Creating full session archive (may take a while)..."
    tar -cf "$INV_DIR/session/full-session.tar" -C "$(dirname "$OLD_SESSION")" "$(basename "$OLD_SESSION")" 2>/dev/null || \
        log "WARN: full session tar skipped (disk/permission)"
fi

# Extract paths from session .torrent files (bencode 'path' and 'directory')
log "Extracting saved paths from session metadata..."
PATHS_FILE="$INV_DIR/session/saved-paths.txt"
: > "$PATHS_FILE"
if [ -d "$OLD_SESSION" ]; then
    for f in "$OLD_SESSION"/*; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        case "$base" in
            *.torrent|*.lock|*.pid|ipfilter*|rtorrent.*) continue ;;
        esac
        # rtorrent session files are bencoded; grep for common path strings
        strings "$f" 2>/dev/null | grep -E '^/(share|mnt|home|volume)' >> "$PATHS_FILE" 2>/dev/null || true
    done
    sort -u "$PATHS_FILE" -o "$PATHS_FILE" 2>/dev/null || true
fi

# Summary report
REPORT="$INV_DIR/INVENTORY_REPORT.txt"
{
    echo "QNAP rtorrent inventory - $STAMP"
    echo "Hostname: $(hostname 2>/dev/null || echo unknown)"
    echo "Kernel: $(uname -a)"
    echo ""
    echo "Old session dir: $OLD_SESSION"
    [ -f "$INV_DIR/session/file-count.txt" ] && echo "Session files: $(cat "$INV_DIR/session/file-count.txt")"
    [ -f "$INV_DIR/session/torrent-meta-count.txt" ] && echo "Torrent metadata files: $(cat "$INV_DIR/session/torrent-meta-count.txt")"
    [ -f "$INV_DIR/session/dot-torrent-count.txt" ] && echo ".torrent files in session: $(cat "$INV_DIR/session/dot-torrent-count.txt")"
    [ -f "$INV_DIR/session/size.txt" ] && echo "Session size: $(cat "$INV_DIR/session/size.txt")"
    echo ""
    echo "Downloads dir:"
    [ -d "${RDLINK}/downloads" ] && du -sh "${RDLINK}/downloads" 2>/dev/null || echo "  (missing)"
    echo ""
    echo "Unique paths found in session metadata:"
    [ -f "$PATHS_FILE" ] && head -50 "$PATHS_FILE" || echo "  (none)"
    echo ""
    echo "Suggested path-map.conf entries:"
    if [ -f "$PATHS_FILE" ]; then
        awk -F/ 'NF>=3 {print "/"$2"/"$3"/"$4}' "$PATHS_FILE" 2>/dev/null | sort -u | head -10 | while read -r p; do
            echo "# $p=..."
        done
    fi
} > "$REPORT"

log "Inventory report: $REPORT"
cat "$REPORT"
log "Step 1 complete."
