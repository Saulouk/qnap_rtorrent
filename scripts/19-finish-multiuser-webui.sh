#!/bin/sh
# Finish multi-user setup when Saulouk rtorrent is already running.
#
# Usage:
#   sh scripts/19-finish-multiuser-webui.sh

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path
ensure_php_xml
[ -f "$HTPASSWD_FILE" ] || die "Missing ${HTPASSWD_FILE} — run 19-configure-two-users.sh first"

export RECOVERY_ROOT
. "${RECOVERY_ROOT}/lib/start-multiuser-rtorrent.sh"
. "${RECOVERY_ROOT}/lib/configure-rutorrent-multiuser.sh"

date > "$MULTIUSER_MARKER"

saulouk_count="$(rpc_torrent_count "$SAULOUK_SOCKET")"
josh_count="$(rpc_torrent_count "$JOSH_SOCKET")"
log "Saulouk torrents: ${saulouk_count}"
log "Josh torrents: ${josh_count}"
log "WebUI: http://$(hostname -i 2>/dev/null | awk '{print $1}'):${WEB_PORT}/rutorrent/"
log "Credentials: ${MULTIUSER_CREDENTIALS}"
