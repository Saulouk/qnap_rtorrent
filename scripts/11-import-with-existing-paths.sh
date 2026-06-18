#!/bin/sh
# Import .torrent files and set each torrent's directory to the existing NAS data.
#
# Dry run:
#   sh scripts/11-import-with-existing-paths.sh /path/to/old/torrents /share/SN 20
#
# Apply:
#   sh scripts/11-import-with-existing-paths.sh apply /path/to/old/torrents /share/SN 20

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path

MODE="${1:-dry-run}"
if [ "$MODE" = "apply" ]; then
    APPLY=1
    shift
else
    APPLY=0
fi

SOURCE_DIR="${1:-/share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720}"
TARGET_ROOT="${2:-/share/SN}"
BATCH_SIZE="${3:-20}"
RPC="${RECOVERY_ROOT}/lib/rtorrent-rpc.php"
TORRENT_NAME="${RECOVERY_ROOT}/lib/torrent-name.php"
REPORT="${BACKUP_ROOT}/import-existing-paths-$(date +%Y%m%d-%H%M%S).tsv"
STAGING="${ENTWARE_ROOT}/import-existing"

[ -d "$SOURCE_DIR" ] || die "Source torrent directory not found: $SOURCE_DIR"
[ -d "$TARGET_ROOT" ] || die "Target data root not found: $TARGET_ROOT"
[ -S "$SCGI_SOCKET" ] || die "rtorrent SCGI socket missing: $SCGI_SOCKET"
[ -f "$RPC" ] || die "Missing XMLRPC helper: $RPC"
[ -f "$TORRENT_NAME" ] || die "Missing torrent-name helper: $TORRENT_NAME"

mkdir -p "$BACKUP_ROOT" "$STAGING"

rpc() {
    RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" /opt/bin/php8-cli "$RPC" "$@"
}

find_existing_parent() {
    name="$1"
    candidates="${ENTWARE_ROOT}/existing-path-candidates.$$"
    : > "$candidates"

    find "$TARGET_ROOT" -maxdepth 8 -type d -name "$name" 2>/dev/null >> "$candidates" || true
    find "$TARGET_ROOT" -maxdepth 8 -type f -name "$name" 2>/dev/null >> "$candidates" || true

    sort -u "$candidates" -o "$candidates" 2>/dev/null || true
    count=$(wc -l < "$candidates" | tr -d ' ')

    if [ "$count" = "1" ]; then
        found="$(sed -n '1p' "$candidates")"
        rm -f "$candidates"
        dirname "$found"
        return 0
    fi

    if [ "$count" -gt 1 ]; then
        echo "AMBIGUOUS:$candidates"
        return 2
    fi

    rm -f "$candidates"
    return 1
}

log "=== Step 11: Import torrents with existing NAS paths ==="
log "Mode: $([ "$APPLY" = 1 ] && echo apply || echo dry-run)"
log "Source torrents: $SOURCE_DIR"
log "Target data root: $TARGET_ROOT"
log "Batch size: $BATCH_SIZE"
log "Report: $REPORT"

{
    echo "hash	torrent_file	torrent_name	target_directory	status"
} > "$REPORT"

count=0
matched=0
missing=0
ambiguous=0
applied=0

for torrent in "$SOURCE_DIR"/*.torrent; do
    [ -f "$torrent" ] || continue
    count=$((count + 1))
    [ "$count" -le "$BATCH_SIZE" ] || break

    base="$(basename "$torrent")"
    hash="${base%.torrent}"
    name="$(/opt/bin/php8-cli "$TORRENT_NAME" "$torrent" 2>/dev/null || true)"

    if [ -z "$name" ]; then
        echo "$hash	$base			NO_NAME" >> "$REPORT"
        echo "NO_NAME: $base"
        continue
    fi

    target="$(find_existing_parent "$name" || true)"
    case "$target" in
        AMBIGUOUS:*)
            cand="${target#AMBIGUOUS:}"
            echo "$hash	$base	$name	$cand	AMBIGUOUS" >> "$REPORT"
            echo "AMBIGUOUS: $name (see $cand)"
            ambiguous=$((ambiguous + 1))
            continue
            ;;
        "")
            echo "$hash	$base	$name		MISSING" >> "$REPORT"
            echo "MISSING: $name"
            missing=$((missing + 1))
            continue
            ;;
    esac

    echo "$hash	$base	$name	$target	MATCH" >> "$REPORT"
    echo "MATCH: $name -> $target"
    matched=$((matched + 1))

    if [ "$APPLY" = 1 ]; then
        staged="${STAGING}/${base}"
        cp "$torrent" "$staged"

        # Load stopped/normal first, set path, then check existing data.
        rpc load.normal "$staged" >/dev/null 2>&1 || rpc load.start "$staged" >/dev/null 2>&1 || true
        sleep 1
        rpc d.stop "$hash" >/dev/null 2>&1 || true
        rpc d.directory.set "$hash" "$target" >/dev/null
        rpc d.check_hash "$hash" >/dev/null 2>&1 || true
        echo "$hash	$base	$name	$target	APPLIED" >> "${REPORT}.applied"
        applied=$((applied + 1))
    fi
done

log "Summary: matched=$matched missing=$missing ambiguous=$ambiguous applied=$applied"
log "Report written: $REPORT"

if [ "$APPLY" != 1 ]; then
    log "If matches look correct, apply with:"
    log "  sh scripts/11-import-with-existing-paths.sh apply \"$SOURCE_DIR\" \"$TARGET_ROOT\" $BATCH_SIZE"
fi
