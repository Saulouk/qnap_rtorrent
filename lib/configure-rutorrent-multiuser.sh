#!/bin/sh
# Configure ruTorrent WebUI + lighttpd for two users (HTTP auth + per-user SCGI).

set -e
. "$(dirname "$0")/common.sh"

ensure_entware_path
ensure_php_symlinks
ensure_php_xml

ENTWARE_WWW="${ENTWARE_ROOT}/www"

# Locate ruTorrent web root
RUT_WEB=""
for candidate in \
    "${ENTWARE_WWW}/rutorrent" \
    /opt/share/rutorrent \
    /opt/www/rutorrent \
    /opt/share/www/rutorrent \
    /share/CACHEDEV1_DATA/.qpkg/rtorrent/var/www/ui/rtorrent; do
    if [ -f "${candidate}/index.html" ]; then
        RUT_WEB="$candidate"
        break
    fi
done

ENTWARE_WWW="${ENTWARE_ROOT}/www"
[ -n "$RUT_WEB" ] || die "ruTorrent web UI not found"

RUT_CONF_DIR="${RUT_WEB}/conf"
mkdir -p "$RUT_CONF_DIR" "$RUT_PROFILE_ROOT" "$SAULOUK_PROFILE" "$JOSH_PROFILE" "${ENTWARE_ROOT}/tmp"

# Migrate legacy single-user settings into Saulouk profile once
if [ -d "$SAULOUK_SETTINGS" ] && [ ! -f "${SAULOUK_PROFILE}/.migrated" ]; then
    log "Migrating settings -> ${SAULOUK_PROFILE}"
    cp -a "$SAULOUK_SETTINGS/." "$SAULOUK_PROFILE/" 2>/dev/null || true
    touch "${SAULOUK_PROFILE}/.migrated"
fi
mkdir -p "$JOSH_PROFILE"
chmod -R 777 "$RUT_PROFILE_ROOT" "${ENTWARE_ROOT}/tmp" 2>/dev/null || true

NAS_IP="$(hostname -i 2>/dev/null | awk '{print $1}')"
[ -n "$NAS_IP" ] || NAS_IP="192.168.1.2"

cat > "${RUT_CONF_DIR}/config.php" <<PHPEOF
<?php
	\$log_file = '${ENTWARE_LOGS}/ui-rtorrent-error.log';
	\$scgi_port = 0;
	\$scgi_host = "unix://${SAULOUK_SOCKET}";
	\$XMLRPCMountPoint = "/RPC2";
	\$localhosts = array("127.0.0.1", "::1", "localhost", "${NAS_IP}");
	\$profilePath = '${RUT_PROFILE_ROOT}';
	\$profileMask = 0777;
	\$tempDirectory = '${ENTWARE_ROOT}/tmp/';
	\$canUseXSendFile = false;
	\$locale = "UTF8";
PHPEOF

cat > "${RUT_CONF_DIR}/access.ini" <<INIEOF
; Multi-user access
[${USER_SAULOUK}]
[${USER_JOSH}]
INIEOF

mkdir -p "${RUT_CONF_DIR}/users/${USER_SAULOUK}" "${RUT_CONF_DIR}/users/${USER_JOSH}"

cat > "${RUT_CONF_DIR}/users/${USER_SAULOUK}/config.php" <<PHPEOF
<?php
	\$scgi_port = 0;
	\$scgi_host = "unix://${SAULOUK_SOCKET}";
	\$profilePath = '${RUT_PROFILE_ROOT}';
PHPEOF

cat > "${RUT_CONF_DIR}/users/${USER_JOSH}/config.php" <<PHPEOF
<?php
	\$scgi_port = 0;
	\$scgi_host = "unix://${JOSH_SOCKET}";
	\$profilePath = '${RUT_PROFILE_ROOT}';
PHPEOF

LIGHTTPD_BIN=""
for b in /opt/sbin/lighttpd /opt/bin/lighttpd; do
    [ -x "$b" ] && LIGHTTPD_BIN="$b" && break
done
PHP_CGI=""
for p in /opt/bin/php-cgi /opt/bin/php8-cgi /opt/bin/php; do
    [ -x "$p" ] && PHP_CGI="$p" && break
done
[ -n "$LIGHTTPD_BIN" ] || die "lighttpd not found"
[ -n "$PHP_CGI" ] || die "php-cgi not found"
[ -f "$HTPASSWD_FILE" ] || die "Missing ${HTPASSWD_FILE} — run 19-configure-two-users.sh first"

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
server.modules = ( "mod_access", "mod_auth", "mod_fastcgi", "mod_rewrite", "mod_scgi" )
auth.backend = "htpasswd"
auth.backend.htpasswd.userfile = "${HTPASSWD_FILE}"
auth.require = (
  "/rutorrent/" => "valid-user"
)
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
    "socket" => "${SAULOUK_SOCKET}",
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

log "ruTorrent multi-user URL: http://${NAS_IP}:${WEB_PORT}/rutorrent/"
