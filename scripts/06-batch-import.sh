#!/bin/sh
# Step 6: Batch import old torrents with optional path remapping

set -e
. "$(dirname "$0")/../lib/common.sh"

log "=== Step 6: Batch import old torrents ==="

BATCH_SIZE="${1:-10}"
SOURCE_DIR="${2:-$OLD_SESSION}"
IMPORT_DIR="${ENTWARE_ROOT}/import-staging"
IMPORT_LOG="${ENTWARE_LOGS}/import.log"
mkdir -p "$IMPORT_DIR" "$ENTWARE_LOGS" "$ENTWARE_WATCH/start"

[ -d "$SOURCE_DIR" ] || die "Source directory not found: $SOURCE_DIR"
[ -x /opt/bin/rtorrent ] || die "Entware rtorrent not installed"

ensure_entware_path

# Ensure rtorrent running
if [ ! -f "${ENTWARE_ROOT}/rtorrent.pid" ] || ! /bin/ps -ef | grep -v grep | grep -q "/opt/bin/rtorrent"; then
    log "Starting rtorrent for import..."
    "$(dirname "$0")/04-minimal-native-test.sh"
fi

apply_path_map() {
    srcfile="$1"
    dstfile="$2"
    cp "$srcfile" "$dstfile"
    if [ -f "$PATH_MAP" ]; then
        while IFS= read -r line; do
            case "$line" in ''|'#'*) continue ;; esac
            old="${line%%=*}"
            new="${line#*=}"
            [ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ] || continue
            if grep -q "$old" "$dstfile" 2>/dev/null; then
                sed -i "s|${old}|${new}|g" "$dstfile" 2>/dev/null || \
                    sed "s|${old}|${new}|g" "$dstfile" > "${dstfile}.tmp" && mv "${dstfile}.tmp" "$dstfile"
                log "  remapped path: $old -> $new"
            fi
        done < "$PATH_MAP"
    fi
}

import_via_xmlrpc() {
  torrent_path="$1"
  method="${2:-load.start}"
  /opt/bin/php8-cli -r "
\$socket = '${SCGI_SOCKET}';
\$path = '${torrent_path}';
\$method = '${method}';
\$body = '<?xml version=\"1.0\"?><methodCall><methodName>'.\$method.'</methodName><params><param><value><string>'.htmlspecialchars(\$path, ENT_XML1).'</string></value></param></params></methodCall>';
\$headers = \"CONTENT_LENGTH\\0\".strlen(\$body).\"\\0SCGI\\0\".\"1\\0REQUEST_METHOD\\0POST\\0REQUEST_URI\\0/RPC2\\0\";
\$req = strlen(\$headers).':'.\$headers.','.\$body;
\$s = stream_socket_client('unix://'.\$socket, \$e, \$es, 5);
if (!\$s) exit(1);
fwrite(\$s, \$req);
echo stream_get_contents(\$s);
" 2>/dev/null | grep -q methodResponse && return 0
  return 1
}

count=0
imported=0
failed=0

log "Importing up to $BATCH_SIZE torrents"
log "Source directory: $SOURCE_DIR"
log "Edit $PATH_MAP for path remapping before larger imports"

for meta in "$SOURCE_DIR"/*; do
    [ -f "$meta" ] || continue
    base="$(basename "$meta")"
    case "$base" in
        *.lock|*.pid|ipfilter*|rtorrent.*|*.dat|*.gz|*.response) continue ;;
    esac
    # Accept normal .torrent files and rtorrent 40-char session metadata.
    case "$base" in
        *.torrent) ;;
        *) echo "$base" | grep -qE '^[0-9a-fA-F]{40}$' || continue ;;
    esac

    count=$((count + 1))
    [ "$count" -le "$BATCH_SIZE" ] || break

    staged="${IMPORT_DIR}/${base}"
    apply_path_map "$meta" "$staged"

    # Also try companion .torrent if this is a raw rtorrent session metadata file.
    dot_torrent="${SOURCE_DIR}/${base}.torrent"
    load_file="$staged"
    if [ -f "$dot_torrent" ]; then
        staged_t="${IMPORT_DIR}/${base}.torrent"
        apply_path_map "$dot_torrent" "$staged_t"
        load_file="$staged_t"
    fi

    log "Import [$count/$BATCH_SIZE]: $base"
    cp "$load_file" "${ENTWARE_WATCH}/start/" 2>/dev/null || true
    if import_via_xmlrpc "$load_file" "load.start"; then
        imported=$((imported + 1))
        echo "$(date) OK $base" >> "$IMPORT_LOG"
    else
        # Fallback: copy into watch/start; rtorrent will pick it up on its schedule.
        cp "$load_file" "${ENTWARE_WATCH}/start/" 2>/dev/null && {
            imported=$((imported + 1))
            echo "$(date) WATCH $base" >> "$IMPORT_LOG"
        } || {
            failed=$((failed + 1))
            echo "$(date) FAIL $base" >> "$IMPORT_LOG"
            log "  WARN: import failed for $base"
        }
    fi
done

log "Import batch done: imported=$imported failed=$failed (log: $IMPORT_LOG)"
log "Re-run with larger batch: $0 50 \"$SOURCE_DIR\""
log "Step 6 complete."
