#!/bin/sh
# Step 7: Disable broken rtorrent-Pro QPKG and install Entware autostart

set -e
. "$(dirname "$0")/../lib/common.sh"

log "=== Step 7: Disable old QPKG ==="

RT_SH="/share/CACHEDEV1_DATA/.qpkg/rtorrent/rtorrent.sh"
QPKG_CONF="/etc/config/qpkg.conf"

# Stop old package
if [ -x "$RT_SH" ]; then
    log "Stopping rtorrent-Pro QPKG..."
    "$RT_SH" stop 2>/dev/null || true
    sleep 5
fi

# Disable autostart in qpkg.conf
if [ -f "$QPKG_CONF" ] && grep -q '^\[rtorrent\]' "$QPKG_CONF"; then
    cp "$QPKG_CONF" "${BACKUP_ROOT}/qpkg.conf.before-disable.$(date +%s)"
    if grep -q '^Enable = TRUE' "$QPKG_CONF"; then
        sed -i '/^\[rtorrent\]/,/^\[/ s/^Enable = TRUE/Enable = FALSE/' "$QPKG_CONF" 2>/dev/null || \
            sed -i 's/^Enable = TRUE/Enable = FALSE/' "$QPKG_CONF"
        log "Set rtorrent Enable=FALSE in qpkg.conf"
    fi
fi

# Kill stray QPKG processes
for pat in 'rtorrent.sh' 'lighttpd.*rtorrent' 'initplugins.php'; do
    pkill -f "$pat" 2>/dev/null || true
done
sleep 2

# Entware autostart via QNAP @reboot cron or init script
INIT_D="/share/CACHEDEV1_DATA/.qpkg/Entware/etc/init.d"
mkdir -p "$INIT_D" 2>/dev/null || INIT_D="/opt/etc/init.d"

AUTOSTART="${ENTWARE_ROOT}/entware-rtorrent.sh"
cat > "$AUTOSTART" <<'ASHEOF'
#!/bin/sh
RTROOT="/share/Rdownload/entware"
RECOVERY="/share/Public/qnap-rtorrent-recovery/scripts"
[ -f /opt/etc/profile ] && . /opt/etc/profile
export PATH="/opt/bin:/opt/sbin:$PATH"

case "$1" in
  start)
    [ -x "$RECOVERY/04-minimal-native-test.sh" ] && sh "$RECOVERY/04-minimal-native-test.sh"
    [ -x "$RECOVERY/05-configure-rutorrent.sh" ] && sh "$RECOVERY/05-configure-rutorrent.sh"
    ;;
  stop)
    [ -f "$RTROOT/rtorrent.pid" ] && kill "$(cat "$RTROOT/rtorrent.pid")" 2>/dev/null
    [ -f "$RTROOT/lighttpd.pid" ] && kill "$(cat "$RTROOT/lighttpd.pid")" 2>/dev/null
    killall php-cgi 2>/dev/null || true
    ;;
  restart)
    $0 stop; sleep 2; $0 start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac
ASHEOF
chmod +x "$AUTOSTART"

# Link into Entware init if possible
if [ -d "$INIT_D" ]; then
    ln -sf "$AUTOSTART" "${INIT_D}/S99entware-rtorrent" 2>/dev/null || \
        cp "$AUTOSTART" "${INIT_D}/S99entware-rtorrent" && chmod +x "${INIT_D}/S99entware-rtorrent"
    log "Autostart script: ${INIT_D}/S99entware-rtorrent"
fi

# QNAP crontab @reboot fallback
CRON_MARKER="# entware-rtorrent-recovery"
if ! grep -q "$CRON_MARKER" /etc/config/crontab 2>/dev/null; then
    echo "@reboot $AUTOSTART start $CRON_MARKER" >> /etc/config/crontab 2>/dev/null && \
        crontab /etc/config/crontab 2>/dev/null && \
        log "Added @reboot cron entry" || log "WARN: could not update crontab (add manually)"
fi

log "Old QPKG disabled. New stack:"
log "  rtorrent SCGI: 127.0.0.1:${SCGI_PORT}"
log "  ruTorrent UI:  http://<nas-ip>:${WEB_PORT}/rutorrent/"
log "  Start/stop:    $AUTOSTART {start|stop|restart}"
log "Step 7 complete."
