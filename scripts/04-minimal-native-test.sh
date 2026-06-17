#!/bin/sh
# Step 4: Minimal native rtorrent + SCGI test

set -e
. "$(dirname "$0")/../lib/common.sh"

log "=== Step 4: Minimal native rtorrent test ==="

has_entware || die "Entware required"
ensure_entware_path
[ -x /opt/bin/rtorrent ] || die "Run 03-install-entware-rtorrent.sh first"

mkdir -p "$ENTWARE_SESSION" "$ENTWARE_DOWNLOADS" "$ENTWARE_LOGS"

# Minimal config - no QPKG hooks, no initplugins, no DHT spam
cat > "$ENTWARE_RUT_CONF" <<EOF
# Entware minimal rtorrent config (QTS5 recovery)
directory.default.set = ${ENTWARE_DOWNLOADS}
session.path.set = ${ENTWARE_SESSION}
scgi_port = 127.0.0.1:${SCGI_PORT}
system.daemon.set = true
network.listen.set = 0.0.0.0:42001
dht.mode.set = off
EOF

PIDFILE="${ENTWARE_ROOT}/rtorrent.pid"
if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    kill "$oldpid" 2>/dev/null || true
    sleep 2
fi

log "Starting rtorrent (SCGI ${SCGI_PORT})..."
/opt/bin/rtorrent -n -o import="${ENTWARE_RUT_CONF}" \
    >> "${ENTWARE_LOGS}/rtorrent.out" 2>> "${ENTWARE_LOGS}/rtorrent.err" &

echo $! > "$PIDFILE"
sleep 5

if ! ps -p "$(cat "$PIDFILE")" >/dev/null 2>&1; then
    log "rtorrent exited. stderr:"
    tail -30 "${ENTWARE_LOGS}/rtorrent.err" 2>/dev/null || true
    die "rtorrent failed to start"
fi

netstat -lntp 2>/dev/null | grep ":${SCGI_PORT}" || log "WARN: port ${SCGI_PORT} not listening yet"

log "Testing SCGI..."
result=$(scgi_test "$SCGI_PORT")
echo "$result"

if echo "$result" | grep -qiE 'version|rtorrent|methodResponse'; then
    log "SUCCESS: rtorrent SCGI responding"
    echo "SCGI_OK" > "${BACKUP_ROOT}/entware-scgi-test.ok"
else
    log "FAILED: no valid SCGI response"
    tail -20 "${ENTWARE_LOGS}/rtorrent.err" 2>/dev/null || true
    die "SCGI test failed - check ${ENTWARE_LOGS}/rtorrent.err"
fi

log "Step 4 complete."
