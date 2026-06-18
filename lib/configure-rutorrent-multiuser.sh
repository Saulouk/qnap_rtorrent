#!/bin/sh
# Configure ruTorrent WebUI + lighttpd for two users (HTTP auth + per-user SCGI).

set -e
: "${RECOVERY_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
. "${RECOVERY_ROOT}/lib/common.sh"

ensure_entware_path
ensure_php_symlinks
ensure_php_xml
ensure_lighttpd_auth_modules

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

# ruTorrent lowercases login names; migrate legacy mixed-case folders
for pair in "${USER_SAULOUK}:${USER_SAULOUK_RPC}" "${USER_JOSH}:${USER_JOSH_RPC}"; do
    old_name="${pair%%:*}"
    new_name="${pair#*:}"
    for base in "${RUT_CONF_DIR}/users" "${ENTWARE_ROOT}/users"; do
        if [ -d "${base}/${old_name}" ] && [ ! -e "${base}/${new_name}" ]; then
            log "Migrating ${base}/${old_name} -> ${base}/${new_name}"
            mv "${base}/${old_name}" "${base}/${new_name}"
        fi
    done
done

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

. "${RECOVERY_ROOT}/lib/configure-rutorrent-downloads.sh"
DOWNLOAD_UI_BLOCK="$(rutorrent_php_externals_block | sed "s|DATA_ROOT_SLASH_PLACEHOLDER|${DATA_ROOT_SLASH}|g")"

cat > "${RUT_CONF_DIR}/config.php" <<PHPEOF
<?php
	\$log_file = '${ENTWARE_LOGS}/ui-rtorrent-error.log';
	\$scgi_port = 0;
	\$scgi_host = "unix://${SAULOUK_SOCKET}";
	\$XMLRPCMountPoint = "${SAULOUK_RPC_MOUNT}";
	\$localhosts = array("127.0.0.1", "::1", "localhost", "${NAS_IP}");
	\$profilePath = '${RUT_PROFILE_ROOT}';
	\$profileMask = 0777;
	\$tempDirectory = '${ENTWARE_ROOT}/tmp/';
	\$canUseXSendFile = false;
	\$locale = "UTF8";
	\$localHostedMode = true;
${DOWNLOAD_UI_BLOCK}
PHPEOF

cat > "${RUT_CONF_DIR}/access.ini" <<INIEOF
; Multi-user access (lowercase = ruTorrent REMOTE_USER)
[${USER_SAULOUK_RPC}]
[${USER_JOSH_RPC}]
INIEOF

mkdir -p "${RUT_CONF_DIR}/users/${USER_SAULOUK_RPC}" "${RUT_CONF_DIR}/users/${USER_JOSH_RPC}"

cat > "${RUT_CONF_DIR}/users/${USER_SAULOUK_RPC}/config.php" <<PHPEOF
<?php
	\$scgi_port = 0;
	\$scgi_host = "unix://${SAULOUK_SOCKET}";
	\$XMLRPCMountPoint = "${SAULOUK_RPC_MOUNT}";
	\$profilePath = '${RUT_PROFILE_ROOT}';
${DOWNLOAD_UI_BLOCK}
PHPEOF

cat > "${RUT_CONF_DIR}/users/${USER_JOSH_RPC}/config.php" <<PHPEOF
<?php
	\$scgi_port = 0;
	\$scgi_host = "unix://${JOSH_SOCKET}";
	\$XMLRPCMountPoint = "${JOSH_RPC_MOUNT}";
	\$profilePath = '${RUT_PROFILE_ROOT}';
${DOWNLOAD_UI_BLOCK}
PHPEOF

. "${RECOVERY_ROOT}/lib/configure-rutorrent-ui.sh"
apply_rutorrent_ui_config "$RUT_WEB"
restart_lighttpd_if_configured

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
server.modules = ( "mod_access", "mod_auth", "mod_authn_file", "mod_fastcgi", "mod_rewrite", "mod_scgi", "mod_setenv" )
auth.backend = "htpasswd"
auth.backend.htpasswd.userfile = "${HTPASSWD_FILE}"
setenv.add-response-header = (
  "X-Frame-Options" => "SAMEORIGIN"
)
auth.require = (
  "/rutorrent/" => (
    "method" => "basic",
    "realm" => "ruTorrent",
    "require" => "valid-user"
  ),
  "${SAULOUK_RPC_MOUNT}" => (
    "method" => "basic",
    "realm" => "ruTorrent",
    "require" => "user=${USER_SAULOUK}"
  ),
  "${JOSH_RPC_MOUNT}" => (
    "method" => "basic",
    "realm" => "ruTorrent",
    "require" => "user=${USER_JOSH}"
  )
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
  "${SAULOUK_RPC_MOUNT}" => ((
    "socket" => "${SAULOUK_SOCKET}",
    "check-local" => "disable"
  )),
  "${JOSH_RPC_MOUNT}" => ((
    "socket" => "${JOSH_SOCKET}",
    "check-local" => "disable"
  ))
)
url.redirect = ( "^/\$" => "/rutorrent/" )
EOF

. "${RECOVERY_ROOT}/lib/start-lighttpd.sh"
start_lighttpd_stack "$LIGHTTPD_CONF" "$LIGHTTPD_BIN" "$PHP_CGI" || \
    die "lighttpd failed to start - inspect ${ENTWARE_LOGS}/lighttpd.out"

log "ruTorrent multi-user URL: http://${NAS_IP}:${WEB_PORT}/rutorrent/"
log "${USER_SAULOUK} -> ${SAULOUK_RPC_MOUNT} (${SAULOUK_SOCKET})"
log "${USER_JOSH} -> ${JOSH_RPC_MOUNT} (${JOSH_SOCKET})"
