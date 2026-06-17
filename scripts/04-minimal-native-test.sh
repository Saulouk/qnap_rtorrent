#!/bin/sh
# Step 4: Minimal native rtorrent + SCGI test (Entware rtorrent 0.15.x)

set -e
. "$(dirname "$0")/../lib/common.sh"

log "=== Step 4: Minimal native rtorrent test ==="

has_entware || die "Entware required"
ensure_entware_path
[ -x /opt/bin/rtorrent ] || die "Run 03-install-entware-rtorrent.sh first"

install_pkg() {
    /opt/bin/opkg list-installed 2>/dev/null | grep -q "^$1 " || /opt/bin/opkg install "$1" 2>/dev/null || true
}
install_pkg rtorrent-rpc

mkdir -p "$ENTWARE_SESSION" "$ENTWARE_DOWNLOADS" "$ENTWARE_LOGS"
rm -f "$SCGI_SOCKET"

# rtorrent 0.15 syntax; unix socket is more reliable than TCP on QNAP
cat > "$ENTWARE_RUT_CONF" <<EOF
# Entware rtorrent 0.15 - QTS5 recovery (minimal valid config)
session.path.set = ${ENTWARE_SESSION}
directory.default.set = ${ENTWARE_DOWNLOADS}
network.scgi.open_local = ${SCGI_SOCKET}
schedule2 = scgi_permission, 0, 0, "execute=chmod,\"a+w\",${SCGI_SOCKET}"
network.port_range.set = 42001-42099
EOF

PIDFILE="${ENTWARE_ROOT}/rtorrent.pid"
if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    kill "$oldpid" 2>/dev/null || true
    sleep 2
fi
pkill -x rtorrent 2>/dev/null || true
sleep 1

log "Preflight: run rtorrent in foreground briefly to capture config errors..."
: > "${ENTWARE_LOGS}/rtorrent.err"
if command -v timeout >/dev/null 2>&1; then
    timeout 3 /opt/bin/rtorrent -n -o "import=${ENTWARE_RUT_CONF}" \
        >> "${ENTWARE_LOGS}/rtorrent.out" 2>> "${ENTWARE_LOGS}/rtorrent.err" || true
else
    /opt/bin/rtorrent -n -o "import=${ENTWARE_RUT_CONF}" \
        >> "${ENTWARE_LOGS}/rtorrent.out" 2>> "${ENTWARE_LOGS}/rtorrent.err" &
    _pf=$!
    sleep 3
    kill "$_pf" 2>/dev/null || true
fi

if grep -qiE 'error|failed|parse' "${ENTWARE_LOGS}/rtorrent.err" 2>/dev/null; then
    log "Config/runtime messages:"
    tail -20 "${ENTWARE_LOGS}/rtorrent.err" || true
fi

log "Starting rtorrent (SCGI socket ${SCGI_SOCKET})..."
/opt/bin/rtorrent -n -o "import=${ENTWARE_RUT_CONF}" \
    >> "${ENTWARE_LOGS}/rtorrent.out" 2>> "${ENTWARE_LOGS}/rtorrent.err" &

echo $! > "$PIDFILE"
sleep 6

if ! ps -p "$(cat "$PIDFILE")" >/dev/null 2>&1; then
    log "rtorrent exited. stderr:"
    tail -40 "${ENTWARE_LOGS}/rtorrent.err" 2>/dev/null || true
    log "stdout:"
    tail -20 "${ENTWARE_LOGS}/rtorrent.out" 2>/dev/null || true
    die "rtorrent failed to start - see ${ENTWARE_LOGS}/rtorrent.err"
fi

[ -S "$SCGI_SOCKET" ] || log "WARN: socket not created yet: $SCGI_SOCKET"
ls -la "$SCGI_SOCKET" 2>/dev/null || true

log "Testing SCGI..."
result=$(scgi_test "$SCGI_SOCKET")
echo "$result"

if echo "$result" | grep -qiE 'version|rtorrent|methodResponse|client'; then
    log "SUCCESS: rtorrent SCGI responding"
    echo "SCGI_OK" > "${BACKUP_ROOT}/entware-scgi-test.ok"
else
    log "FAILED: no valid SCGI response"
    tail -30 "${ENTWARE_LOGS}/rtorrent.err" 2>/dev/null || true
    die "SCGI test failed - check ${ENTWARE_LOGS}/rtorrent.err"
fi

log "Step 4 complete."
