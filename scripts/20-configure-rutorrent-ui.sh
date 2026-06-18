#!/bin/sh
# Configure ruTorrent UI: /share/SN directory picker + standard plugins.
# Restarts lighttpd only (not rtorrent).
#
# Usage:
#   sh scripts/20-configure-rutorrent-ui.sh

set -e
. "$(dirname "$0")/../lib/common.sh"
. "${RECOVERY_ROOT}/lib/configure-rutorrent-ui.sh"

ensure_entware_path
ensure_php_xml
ensure_lighttpd_auth_modules

RUT_WEB="$(find_rutorrent_web)" || die "ruTorrent web root not found"

log "=== Configure ruTorrent UI ==="
log "Web root: ${RUT_WEB}"
log "Download root: ${DATA_ROOT_SLASH}"

apply_rutorrent_ui_config "$RUT_WEB"
restart_lighttpd_if_configured

log "Done. Hard-refresh ruTorrent (Ctrl+F5)."
log "Add Torrent -> Directory should show ${DATA_ROOT_SLASH} and ... folder picker."
log "Plugins tab: enable any extra plugins marked user-defined."
