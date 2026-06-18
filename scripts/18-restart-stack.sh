#!/bin/sh
# Restart Entware rtorrent + ruTorrent web stack.
#
# Usage:
#   sh scripts/18-restart-stack.sh

set -e
. "$(dirname "$0")/../lib/common.sh"

log "=== Restart Entware rtorrent stack ==="
ensure_entware_path
ensure_php_xml

if multiuser_enabled; then
    log "Multi-user mode detected"
    export RECOVERY_ROOT
    . "${RECOVERY_ROOT}/lib/start-multiuser-rtorrent.sh"
    . "${RECOVERY_ROOT}/lib/configure-rutorrent-multiuser.sh"
    date > "$MULTIUSER_MARKER" 2>/dev/null || true
else
    sh "$(dirname "$0")/04-minimal-native-test.sh"
    sh "$(dirname "$0")/05-configure-rutorrent.sh"
fi

log "Stack restarted."
log "Web UI: http://$(hostname -i 2>/dev/null | awk '{print $1}'):${WEB_PORT}/rutorrent/"
