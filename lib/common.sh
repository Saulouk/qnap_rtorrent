#!/bin/sh
# Shared helpers for QNAP rtorrent recovery scripts

set -e

# When sourced from scripts/*.sh, $0 is the calling script path
if [ -z "$RECOVERY_ROOT" ]; then
    _caller="${0:-}"
    if [ -n "$_caller" ]; then
        RECOVERY_ROOT="$(cd "$(dirname "$_caller")/.." && pwd)"
    else
        RECOVERY_ROOT="/share/Public/qnap-rtorrent-recovery"
    fi
fi
BACKUP_ROOT="/share/Public/rtorrent-debug-backup"
RDLINK="/share/Rdownload"
OLD_SESSION="${RDLINK}/session.disabled-debug"
ENTWARE_ROOT="${RDLINK}/entware"
ENTWARE_SESSION="${ENTWARE_ROOT}/session"
ENTWARE_DOWNLOADS="${ENTWARE_ROOT}/downloads"
ENTWARE_WATCH="${ENTWARE_ROOT}/watch"
ENTWARE_LOGS="${ENTWARE_ROOT}/logs"
ENTWARE_RUT_CONF="${ENTWARE_ROOT}/rtorrent.conf"
SCGI_SOCKET="${ENTWARE_ROOT}/rtorrent.sock"
DTACH_SOCKET="${ENTWARE_ROOT}/rtorrent.dtach"
SCGI_PORT=19010
WEB_PORT=6010
PATH_MAP="${RECOVERY_ROOT}/path-map.conf"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }

ensure_entware_path() {
    if [ -f /opt/etc/profile ]; then
        # shellcheck disable=SC1091
        . /opt/etc/profile
    fi
    export PATH="/opt/bin:/opt/sbin:${PATH}"
}

has_entware() {
    [ -x /opt/bin/opkg ]
}

rtorrent_bin() {
    if [ -x /opt/bin/rtorrent ]; then
        echo /opt/bin/rtorrent
    elif [ -x /share/CACHEDEV1_DATA/.qpkg/rtorrent/bin/rtorrent ]; then
        echo /share/CACHEDEV1_DATA/.qpkg/rtorrent/bin/rtorrent
    else
        return 1
    fi
}

scgi_test() {
    target="${1:-$SCGI_SOCKET}"
    php_bin="/opt/bin/php8-cli"
    [ -x "$php_bin" ] || php_bin="/opt/bin/php"
    [ -x "$php_bin" ] || php_bin="/share/CACHEDEV1_DATA/.qpkg/rtorrent/bin/php"
    [ -x "$php_bin" ] || die "php not found for SCGI test"

    "$php_bin" -r "
\$target = '${target}';
\$body = '<?xml version=\"1.0\"?><methodCall><methodName>system.client_version</methodName><params></params></methodCall>';
\$headers = 'CONTENT_LENGTH\0'.strlen(\$body).'\0SCGI\01\0REQUEST_METHOD\0POST\0REQUEST_URI\0/RPC2\0';
\$req = strlen(\$headers).':'.\$headers.','.\$body;
if (strpos(\$target, '/') !== false) {
    \$s = @stream_socket_client('unix://'.\$target, \$errno, \$errstr, 5);
} else {
    \$s = @fsockopen('127.0.0.1', intval(\$target), \$errno, \$errstr, 5);
}
if (!\$s) { echo \"CONNECT_FAILED:\$errno:\$errstr\n\"; exit(1); }
stream_set_timeout(\$s, 5);
fwrite(\$s, \$req);
\$out = '';
while (!feof(\$s)) {
    \$chunk = fread(\$s, 8192);
    if (\$chunk !== false) \$out .= \$chunk;
    \$meta = stream_get_meta_data(\$s);
    if (!empty(\$meta['timed_out'])) { echo \"READ_TIMEOUT\n\"; break; }
}
echo \$out ? \$out : \"NO_RESPONSE\n\";
" 2>/dev/null
}

ensure_php_symlinks() {
    [ -x /opt/bin/php8-cgi ] && ln -sfn php8-cgi /opt/bin/php-cgi 2>/dev/null || true
    [ -x /opt/bin/php8-cgi ] && ln -sfn php8-cgi /opt/bin/php-fcgi 2>/dev/null || true
    [ -x /opt/bin/php8-cli ] && ln -sfn php8-cli /opt/bin/php 2>/dev/null || true
}
