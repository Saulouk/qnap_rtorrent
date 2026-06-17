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
install_pkg dtach
[ -x /opt/bin/dtach ] || die "dtach is required to give rtorrent a pseudo-terminal"

mkdir -p "$ENTWARE_SESSION" "$ENTWARE_DOWNLOADS" "$ENTWARE_LOGS"
rm -f "$SCGI_SOCKET" "$DTACH_SOCKET"

# rtorrent 0.15 syntax; unix socket is more reliable than TCP on QNAP
cat > "$ENTWARE_RUT_CONF" <<EOF
# Entware rtorrent 0.15 - QTS5 recovery (minimal valid config)
session.path.set = ${ENTWARE_SESSION}
directory.default.set = ${ENTWARE_DOWNLOADS}
network.scgi.open_local = ${SCGI_SOCKET}
schedule2 = scgi_permission, 0, 0, "execute=chmod,\"a+w\",${SCGI_SOCKET}"
EOF

PIDFILE="${ENTWARE_ROOT}/rtorrent.pid"
if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    kill "$oldpid" 2>/dev/null || true
    sleep 2
fi
pkill -x rtorrent 2>/dev/null || true
pkill -x dtach 2>/dev/null || true
sleep 1

: > "${ENTWARE_LOGS}/rtorrent.err"
: > "${ENTWARE_LOGS}/rtorrent.out"

export TERM="${TERM:-vt100}"
log "Starting rtorrent under dtach (SCGI socket ${SCGI_SOCKET})..."
/opt/bin/dtach -n "$DTACH_SOCKET" /opt/bin/rtorrent -n -o "import=${ENTWARE_RUT_CONF}" \
    >> "${ENTWARE_LOGS}/rtorrent.out" 2>> "${ENTWARE_LOGS}/rtorrent.err" || true

sleep 6
pid=$(/bin/ps -ef | awk '/\/opt\/bin\/rtorrent/ && /entware\/rtorrent.conf/ {print $1; exit}')
[ -n "$pid" ] && echo "$pid" > "$PIDFILE"

if [ -z "$pid" ] || ! /bin/ps -p "$pid" >/dev/null 2>&1; then
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
