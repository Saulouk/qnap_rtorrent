#!/bin/sh
# Apply /share/SN download root to ruTorrent Add Torrent UI (no full stack restart).
#
# Usage:
#   sh scripts/20-apply-download-ui.sh

set -e
. "$(dirname "$0")/../lib/common.sh"
. "${RECOVERY_ROOT}/lib/configure-rutorrent-downloads.sh"

ensure_entware_path
ensure_php_xml

RUT_WEB=""
for candidate in \
    "${ENTWARE_ROOT}/www/rutorrent" \
    /opt/share/rutorrent \
    /opt/www/rutorrent; do
    if [ -f "${candidate}/conf/config.php" ]; then
        RUT_WEB="$candidate"
        break
    fi
done
[ -n "$RUT_WEB" ] || die "ruTorrent not found"

# Patch topDirectory into existing config.php files if missing
for cfg in "${RUT_WEB}/conf/config.php" "${RUT_WEB}/conf/users/"*/config.php; do
    [ -f "$cfg" ] || continue
    if ! grep -q 'topDirectory' "$cfg" 2>/dev/null; then
        sed -i "/^<?php/a\\
	\$topDirectory = '${DATA_ROOT_SLASH}';" "$cfg"
    else
        sed -i "s|\$topDirectory = .*|\$topDirectory = '${DATA_ROOT_SLASH}';|" "$cfg"
    fi
done

apply_rutorrent_download_ui "${RUT_WEB}/conf"
log "Hard-refresh ruTorrent in the browser (Ctrl+F5) after applying."
