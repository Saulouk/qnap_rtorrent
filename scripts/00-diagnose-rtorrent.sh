#!/bin/sh
# Quick diagnostic for Entware rtorrent startup failures

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path
mkdir -p "$ENTWARE_SESSION" "$ENTWARE_DOWNLOADS" "$ENTWARE_LOGS"

log "=== rtorrent diagnostic ==="
log "Binary: $(which rtorrent)"
/opt/bin/rtorrent -h 2>&1 | head -3 || true
echo ""

log "Installed packages:"
/opt/bin/opkg list-installed 2>/dev/null | grep -iE 'rtorrent|rutorrent|php8|lighttpd|xmlrpc' || true
echo ""

log "Writing test config to ${ENTWARE_RUT_CONF} ..."
cat > "$ENTWARE_RUT_CONF" <<EOF
session.path.set = ${ENTWARE_SESSION}
directory.default.set = ${ENTWARE_DOWNLOADS}
network.scgi.open_local = ${SCGI_SOCKET}
schedule2 = scgi_permission, 0, 0, "execute=chmod,\"a+w\",${SCGI_SOCKET}"
EOF

rm -f "$SCGI_SOCKET"
log "Running rtorrent in foreground for 8 seconds (all output below):"
echo "---"
( /opt/bin/rtorrent -n -o "import=${ENTWARE_RUT_CONF}" 2>&1 & echo $! > /tmp/rtdiag.pid
  sleep 8
  kill "$(cat /tmp/rtdiag.pid)" 2>/dev/null || true
) | tee "${ENTWARE_LOGS}/diagnose.out"
echo "---"
echo ""
ls -la "$SCGI_SOCKET" 2>/dev/null || log "Socket not created: $SCGI_SOCKET"
echo ""
log "If you see parse errors above, paste diagnose.out"
