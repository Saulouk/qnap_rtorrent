#!/bin/sh
# Retarget already-imported torrents to existing NAS data by matching torrent names.
#
# Dry run:
#   sh scripts/09-retarget-by-existing-data.sh
#
# Apply:
#   sh scripts/09-retarget-by-existing-data.sh apply /share/CACHEDEV1_DATA/Rdownload/downloads /share/CACHEDEV1_DATA/Rdownload/complete

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path

MODE="${1:-dry-run}"
if [ "$MODE" = "apply" ]; then
    shift
    APPLY=1
else
    APPLY=0
fi

RPC="${RECOVERY_ROOT}/lib/rtorrent-rpc.php"
[ -f "$RPC" ] || die "Missing XMLRPC helper: $RPC"
[ -S "$SCGI_SOCKET" ] || die "rtorrent SCGI socket missing: $SCGI_SOCKET"

if [ "$#" -gt 0 ]; then
    SEARCH_ROOTS="$*"
else
    SEARCH_ROOTS="/share/CACHEDEV1_DATA/Rdownload/downloads /share/CACHEDEV1_DATA/Rdownload/complete /share/CACHEDEV1_DATA/Rdownload /share/CACHEDEV2_DATA/Rdownload /share/Rdownload"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${BACKUP_ROOT}/retarget-${STAMP}.tsv"
mkdir -p "$BACKUP_ROOT" "$ENTWARE_LOGS"

rpc() {
    RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" /opt/bin/php8-cli "$RPC" "$@"
}

json_list_hashes() {
    rpc download_list main 2>/dev/null || rpc download_list 2>/dev/null
}

find_existing_data() {
    name="$1"
    candidates="${ENTWARE_ROOT}/retarget-candidates.$$"
    : > "$candidates"

    for root in $SEARCH_ROOTS; do
        [ -d "$root" ] || continue
        # Prefer exact directory matches, then exact file matches.
        find "$root" -maxdepth 8 -type d -name "$name" 2>/dev/null >> "$candidates" || true
        find "$root" -maxdepth 8 -type f -name "$name" 2>/dev/null >> "$candidates" || true
    done

    # Do not match the new wrong download area.
    grep -v "^${ENTWARE_DOWNLOADS}/" "$candidates" | sort -u > "${candidates}.filtered" || true
    mv "${candidates}.filtered" "$candidates"

    count=$(wc -l < "$candidates" | tr -d ' ')
    if [ "$count" = "1" ]; then
        found=$(sed -n '1p' "$candidates")
        rm -f "$candidates"
        if [ -d "$found" ]; then
            dirname "$found"
        else
            dirname "$found"
        fi
        return 0
    fi

    if [ "$count" -gt 1 ]; then
        echo "AMBIGUOUS:$candidates"
        return 2
    fi

    rm -f "$candidates"
    return 1
}

log "=== Step 9: Retarget imported torrents to existing data ==="
log "Mode: $([ "$APPLY" = 1 ] && echo apply || echo dry-run)"
log "Search roots: $SEARCH_ROOTS"
log "Report: $REPORT"

{
    echo "hash	name	current_directory	target_directory	status"
} > "$REPORT"

log "Querying rtorrent for imported torrent hashes..."
hashes_json="$(json_list_hashes)"
hashes="$(echo "$hashes_json" | tr -d '[]" ' | tr ',' '\n' | sed '/^$/d')"

if [ -z "$hashes" ]; then
    die "No torrents returned by rtorrent download_list"
fi

if [ "$APPLY" = 1 ]; then
    log "Stopping current torrents before retargeting..."
    echo "$hashes" | while read -r hash; do
        [ -n "$hash" ] || continue
        rpc d.stop "$hash" >/dev/null 2>&1 || true
    done
fi

matched=0
ambiguous=0
missing=0
applied=0

echo "$hashes" | while read -r hash; do
    [ -n "$hash" ] || continue
    name="$(rpc d.name "$hash" 2>/dev/null || true)"
    current="$(rpc d.directory "$hash" 2>/dev/null || true)"

    if [ -z "$name" ]; then
        echo "$hash		$current		NO_NAME" >> "$REPORT"
        continue
    fi

    target="$(find_existing_data "$name" || true)"
    case "$target" in
        AMBIGUOUS:*)
            cand="${target#AMBIGUOUS:}"
            echo "$hash	$name	$current	$cand	AMBIGUOUS" >> "$REPORT"
            echo "AMBIGUOUS: $name (see $cand)"
            ambiguous=$((ambiguous + 1))
            ;;
        "")
            echo "$hash	$name	$current		MISSING" >> "$REPORT"
            echo "MISSING: $name"
            missing=$((missing + 1))
            ;;
        *)
            echo "$hash	$name	$current	$target	MATCH" >> "$REPORT"
            echo "MATCH: $name -> $target"
            matched=$((matched + 1))
            if [ "$APPLY" = 1 ]; then
                rpc d.stop "$hash" >/dev/null 2>&1 || true
                rpc d.directory.set "$hash" "$target" >/dev/null
                rpc d.check_hash "$hash" >/dev/null 2>&1 || true
                applied=$((applied + 1))
                echo "$hash	$name	$current	$target	APPLIED" >> "${REPORT}.applied"
            fi
            ;;
    esac
done

log "Retarget report written: $REPORT"
log "If dry-run looked good, rerun:"
log "  sh scripts/09-retarget-by-existing-data.sh apply $SEARCH_ROOTS"
