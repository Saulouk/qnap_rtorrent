#!/bin/sh
# Download/sync all upstream ruTorrent plugins, enable them in plugins.ini,
# clear plugin cache, and restart lighttpd. Does not restart rtorrent.
#
# Usage:
#   sh scripts/21-sync-all-rutorrent-plugins.sh

set -e
. "$(dirname "$0")/../lib/common.sh"
. "${RECOVERY_ROOT}/lib/configure-rutorrent-ui.sh"
. "${RECOVERY_ROOT}/lib/configure-rutorrent-plugins.sh"

ensure_entware_path
ensure_php_xml
ensure_lighttpd_auth_modules

RUT_WEB="$(find_rutorrent_web)" || die "ruTorrent web root not found"
RUT_CONF_DIR="${RUT_WEB}/conf"

log "=== Sync all ruTorrent plugins ==="
log "Web root: ${RUT_WEB}"

ensure_rutorrent_plugins_installed "$RUT_WEB"
write_rutorrent_plugins_ini "$RUT_CONF_DIR" "$RUT_WEB"
clear_rutorrent_plugin_cache
rutorrent_init_plugins "$RUT_WEB"
restart_lighttpd_if_configured

enabled_count="$(grep -c '^enabled = yes' "${RUT_CONF_DIR}/plugins.ini" 2>/dev/null || echo 0)"
disabled_count="$(grep -c '^enabled = no' "${RUT_CONF_DIR}/plugins.ini" 2>/dev/null || echo 0)"
log "Enabled plugins: ${enabled_count}"
log "Disabled plugins: ${disabled_count}"
log "Done. Hard-refresh ruTorrent (Ctrl+F5)."
