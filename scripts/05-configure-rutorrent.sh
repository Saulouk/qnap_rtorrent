#!/bin/sh
# Step 5: Configure ruTorrent web UI for Entware rtorrent

set -e
. "$(dirname "$0")/../lib/common.sh"

log "=== Step 5: Configure ruTorrent ==="

has_entware || die "Entware required"
ensure_entware_path
ensure_php_symlinks
[ -f "${BACKUP_ROOT}/entware-scgi-test.ok" ] || log "WARN: run 04-minimal-native-test.sh first"

# Locate ruTorrent web root
RUT_WEB=""
for candidate in \
    /opt/share/rutorrent \
    /opt/www/rutorrent \
    /opt/share/www/rutorrent \
    /opt/var/www/rutorrent \
    /opt/www/rutorrent \
    /share/CACHEDEV1_DATA/.qpkg/rtorrent/var/www/ui/rtorrent; do
    if [ -f "${candidate}/index.html" ]; then
        RUT_WEB="$candidate"
        break
    fi
done

if [ -z "$RUT_WEB" ]; then
    log "ruTorrent web files not in Entware - deploying from QPKG copy if available"
    QPKG_RUT="/share/CACHEDEV1_DATA/.qpkg/rtorrent/var/www/ui/rtorrent"
    if [ -d "$QPKG_RUT" ]; then
        ENTWARE_RUT_WEB="${ENTWARE_ROOT}/www/rutorrent"
        mkdir -p "$(dirname "$ENTWARE_RUT_WEB")"
        cp -a "$QPKG_RUT" "$ENTWARE_RUT_WEB"
        RUT_WEB="$ENTWARE_RUT_WEB"
        log "Copied ruTorrent UI from QPKG to $RUT_WEB"
    else
        die "ruTorrent web UI not found. Install rutorrent package or copy UI manually."
    fi
fi

ENTWARE_WWW="${ENTWARE_ROOT}/www"
mkdir -p "$ENTWARE_WWW"
if [ "$RUT_WEB" != "${ENTWARE_WWW}/rutorrent" ]; then
    ln -sfn "$RUT_WEB" "${ENTWARE_WWW}/rutorrent" 2>/dev/null || cp -a "$RUT_WEB" "${ENTWARE_WWW}/rutorrent"
    RUT_WEB="${ENTWARE_WWW}/rutorrent"
fi

# ruTorrent config
RUT_CONF_DIR="${RUT_WEB}/conf"
mkdir -p "$RUT_CONF_DIR"

if [ -f "${RUT_CONF_DIR}/config.php" ]; then
    cp "${RUT_CONF_DIR}/config.php" "${BACKUP_ROOT}/rutorrent-config.php.bak.$(date +%s)"
fi

cat > "${RUT_CONF_DIR}/config.php" <<PHPEOF
<?php
	\$log_file = '/share/Rdownload/entware/logs/ui-rtorrent-error.log';
	\$scgi_port = 0;
	\$scgi_host = "unix://${SCGI_SOCKET}";
	\$XMLRPCMountPoint = "/RPC2";
	\$localhosts = array("127.0.0.1", "::1", "localhost", "192.168.1.2");
	\$profilePath = '/share/Rdownload/entware/settings';
	\$profileMask = 0777;
	\$tempDirectory = '/share/Rdownload/entware/tmp/';
	\$canUseXSendFile = false;
	\$locale = "UTF8";
PHPEOF

mkdir -p /share/Rdownload/entware/settings /share/Rdownload/entware/tmp
chmod -R 777 /share/Rdownload/entware/settings /share/Rdownload/entware/tmp 2>/dev/null || true

# access.ini for getplugins (was missing in broken setup)
if [ ! -f "${RUT_CONF_DIR}/access.ini" ]; then
    cat > "${RUT_CONF_DIR}/access.ini" <<'INIEOF'
; ruTorrent access - allow local admin user
[admin]
INIEOF
    # Add current QNAP rtorrent username if known
    user=$(/sbin/getcfg rtorrent username -d admin -f /etc/config/qpkg.conf 2>/dev/null)
    if [ -n "$user" ]; then
        grep -q "^\[$user\]" "${RUT_CONF_DIR}/access.ini" 2>/dev/null || echo "[$user]" >> "${RUT_CONF_DIR}/access.ini"
    fi
fi

LIGHTTPD_BIN=""
for b in /opt/sbin/lighttpd /opt/bin/lighttpd; do
    [ -x "$b" ] && LIGHTTPD_BIN="$b" && break
done
PHP_CGI=""
for p in /opt/bin/php-cgi /opt/bin/php8-cgi /opt/bin/php; do
    [ -x "$p" ] && PHP_CGI="$p" && break
done
[ -n "$LIGHTTPD_BIN" ] || die "lighttpd not found under /opt"
[ -n "$PHP_CGI" ] || die "php-cgi not found under /opt"

# lighttpd config for Entware instance
LIGHTTPD_CONF="${ENTWARE_ROOT}/lighttpd.conf"
cat > "$LIGHTTPD_CONF" <<EOF
server.document-root = "${ENTWARE_WWW}"
server.port = ${WEB_PORT}
server.bind = "0.0.0.0"
index-file.names = ( "index.html", "index.php" )
mimetype.assign = (
  ".html" => "text/html",
  ".css"  => "text/css",
  ".js"   => "application/javascript",
  ".json" => "application/json",
  ".png"  => "image/png",
  ".ico"  => "image/x-icon",
  ".php"  => "application/x-httpd-php"
)
server.modules = ( "mod_access", "mod_fastcgi", "mod_rewrite", "mod_scgi" )
fastcgi.server = (
  ".php" => ((
    "bin-path" => "${PHP_CGI}",
    "socket" => "/tmp/entware-php.sock",
    "max-procs" => 2,
    "broken-scriptfilename" => "enable"
  ))
)
scgi.server = (
  "/RPC2" => ((
    "socket" => "${SCGI_SOCKET}",
    "check-local" => "disable"
  ))
)
url.redirect = ( "^/\$" => "/rutorrent/" )
EOF

LIGHTTPD_PID="${ENTWARE_ROOT}/lighttpd.pid"
if [ -f "$LIGHTTPD_PID" ]; then
    kill "$(cat "$LIGHTTPD_PID")" 2>/dev/null || true
    sleep 1
fi

# Start php-cgi + lighttpd
killall php-cgi 2>/dev/null || true
if [ -x /opt/bin/spawn-fcgi ]; then
    /opt/bin/spawn-fcgi -s /tmp/entware-php.sock -P /tmp/entware-php.pid -C 0 -n "$PHP_CGI" 2>/dev/null || \
        "$PHP_CGI" -b 127.0.0.1:9001 &
else
    "$PHP_CGI" -b 127.0.0.1:9001 &
fi

nohup "$LIGHTTPD_BIN" -f "$LIGHTTPD_CONF" -D > "${ENTWARE_LOGS}/lighttpd.out" 2>&1 &
echo $! > "$LIGHTTPD_PID"
sleep 3

if ! /bin/ps -ef | grep -v grep | grep -q "$LIGHTTPD_BIN"; then
    die "lighttpd failed to start - inspect ${LIGHTTPD_CONF}"
fi

log "Testing getplugins.php..."
curl -i --max-time 10 "http://127.0.0.1:${WEB_PORT}/rutorrent/php/getplugins.php" | head -20 || true

log "ruTorrent URL: http://$(hostname -i 2>/dev/null | awk '{print $1}'):${WEB_PORT}/rutorrent/"
log "Step 5 complete."
