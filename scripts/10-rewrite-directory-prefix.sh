#!/bin/sh
# Rewrite imported torrent directories from the temporary Entware download root
# to a real NAS root while preserving the trailing subpath.
#
# Dry run:
#   sh scripts/10-rewrite-directory-prefix.sh /share/SN
#
# Apply:
#   sh scripts/10-rewrite-directory-prefix.sh apply /share/SN
#
# Optional explicit old prefix:
#   sh scripts/10-rewrite-directory-prefix.sh apply /share/SN /share/Rdownload/entware/downloads

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

NEW_PREFIX="${1:-/share/SN}"
OLD_PREFIX="${2:-$ENTWARE_DOWNLOADS}"
RPC="${RECOVERY_ROOT}/lib/rtorrent-rpc.php"
REPORT="${BACKUP_ROOT}/rewrite-prefix-$(date +%Y%m%d-%H%M%S).tsv"

[ -f "$RPC" ] || die "Missing XMLRPC helper: $RPC"
[ -S "$SCGI_SOCKET" ] || die "rtorrent SCGI socket missing: $SCGI_SOCKET"

rpc() {
    RTORRENT_SCGI_SOCKET="$SCGI_SOCKET" /opt/bin/php8-cli "$RPC" "$@"
}

normalize_prefix() {
    # Remove trailing slash except for root.
    p="$1"
    while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do
        p="${p%/}"
    done
    echo "$p"
}

OLD_PREFIX="$(normalize_prefix "$OLD_PREFIX")"
NEW_PREFIX="$(normalize_prefix "$NEW_PREFIX")"

mkdir -p "$BACKUP_ROOT"
{
    echo "hash	name	old_directory	new_directory	status"
} > "$REPORT"

log "=== Step 10: Rewrite torrent directory prefix ==="
log "Mode: $([ "$APPLY" = 1 ] && echo apply || echo dry-run)"
log "Old prefix: $OLD_PREFIX"
log "New prefix: $NEW_PREFIX"
log "Report: $REPORT"

hashes=""
for view in "" main started stopped complete incomplete; do
    hashes_json="$(rpc download_list "$view" 2>/dev/null || true)"
    view_hashes="$(echo "$hashes_json" | tr -d '[]" ' | tr ',' '\n' | sed '/^$/d')"
    hashes="$(printf "%s\n%s\n" "$hashes" "$view_hashes" | sed '/^$/d' | sort -u)"
done

if [ -z "$hashes" ]; then
    die "No torrents returned by rtorrent. Is the WebUI showing torrents in the current session?"
fi

echo "$hashes" | while read -r hash; do
    [ -n "$hash" ] || continue

    name="$(rpc d.name "$hash" 2>/dev/null || true)"
    old_dir="$(rpc d.directory "$hash" 2>/dev/null || true)"
    [ -n "$old_dir" ] || old_dir="$(rpc d.directory_base "$hash" 2>/dev/null || true)"

    case "$old_dir" in
        "$OLD_PREFIX")
            suffix=""
            new_dir="$NEW_PREFIX"
            ;;
        "$OLD_PREFIX"/*)
            suffix="${old_dir#$OLD_PREFIX}"
            new_dir="${NEW_PREFIX}${suffix}"
            ;;
        *)
            echo "$hash	$name	$old_dir		SKIP_PREFIX_MISMATCH" >> "$REPORT"
            echo "SKIP: $name -> $old_dir"
            continue
            ;;
    esac

    echo "$hash	$name	$old_dir	$new_dir	MATCH" >> "$REPORT"
    echo "MATCH: $name"
    echo "  $old_dir"
    echo "  -> $new_dir"

    if [ "$APPLY" = 1 ]; then
        rpc d.stop "$hash" >/dev/null 2>&1 || true
        rpc d.directory.set "$hash" "$new_dir" >/dev/null
        rpc d.check_hash "$hash" >/dev/null 2>&1 || true
        echo "$hash	$name	$old_dir	$new_dir	APPLIED" >> "${REPORT}.applied"
    fi
done

log "Report written: $REPORT"
if [ "$APPLY" != 1 ]; then
    log "If this looks correct, apply with:"
    log "  sh scripts/10-rewrite-directory-prefix.sh apply $NEW_PREFIX $OLD_PREFIX"
fi
