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
PATH_ROOTS="${RECOVERY_ROOT}/path-roots.conf"
HISTORIC_TORRENT_DIR="${HISTORIC_TORRENT_DIR:-/share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720}"
HISTORIC_MAP="${BACKUP_ROOT}/historic-path-map-latest.tsv"
HISTORIC_MAP_VALIDATED="${BACKUP_ROOT}/historic-path-map-validated-latest.tsv"

# Shared download root for all users
DATA_ROOT="${DATA_ROOT:-/share/SN}"

# Multi-user rtorrent (Saulouk = existing recovered instance, josh = new empty instance)
USER_SAULOUK="Saulouk"
USER_JOSH="josh"
MULTIUSER_MARKER="${ENTWARE_ROOT}/.multiuser-enabled"
HTPASSWD_FILE="${ENTWARE_ROOT}/htpasswd"
MULTIUSER_CREDENTIALS="${BACKUP_ROOT}/multiuser-credentials-latest.txt"

# Saulouk instance (default / recovered)
SAULOUK_ROOT="${ENTWARE_ROOT}"
SAULOUK_SESSION="${ENTWARE_SESSION}"
SAULOUK_SOCKET="${SCGI_SOCKET}"
SAULOUK_DTACH="${DTACH_SOCKET}"
SAULOUK_RUT_CONF="${ENTWARE_RUT_CONF}"
SAULOUK_WATCH="${ENTWARE_WATCH}"
SAULOUK_LOGS="${ENTWARE_LOGS}"
SAULOUK_PIDFILE="${ENTWARE_ROOT}/rtorrent.pid"
SAULOUK_SETTINGS="${ENTWARE_ROOT}/settings"
SAULOUK_PROFILE="${ENTWARE_ROOT}/users/${USER_SAULOUK}/settings"

# Josh instance (isolated session, same DATA_ROOT)
JOSH_ROOT="${ENTWARE_ROOT}/users/josh"
JOSH_SESSION="${JOSH_ROOT}/session"
JOSH_SOCKET="${JOSH_ROOT}/rtorrent.sock"
JOSH_DTACH="${JOSH_ROOT}/rtorrent.dtach"
JOSH_RUT_CONF="${JOSH_ROOT}/rtorrent.conf"
JOSH_WATCH="${JOSH_ROOT}/watch"
JOSH_LOGS="${JOSH_ROOT}/logs"
JOSH_PIDFILE="${JOSH_ROOT}/rtorrent.pid"
JOSH_SETTINGS="${JOSH_ROOT}/settings"
JOSH_PROFILE="${ENTWARE_ROOT}/users/${USER_JOSH}/settings"

# ruTorrent profile root (multi-user data under users/USERNAME/settings)
RUT_PROFILE_ROOT="${ENTWARE_ROOT}"

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
\$headers = \"CONTENT_LENGTH\\0\".strlen(\$body).\"\\0SCGI\\0\".\"1\\0REQUEST_METHOD\\0POST\\0REQUEST_URI\\0/RPC2\\0\";
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

ensure_php_xml() {
    php_bin="/opt/bin/php8-cli"
    [ -x "$php_bin" ] || php_bin="/opt/bin/php"
    [ -x "$php_bin" ] || die "php8-cli not found"

    if "$php_bin" -r 'exit(function_exists("simplexml_load_string") ? 0 : 1);' 2>/dev/null; then
        return 0
    fi

    log "PHP simplexml missing — installing XML modules..."
    /opt/bin/opkg update >/dev/null 2>&1 || true
    for pkg in php8-mod-simplexml php8-mod-xml php8-xml; do
        /opt/bin/opkg install "$pkg" 2>/dev/null || true
    done

    if ! "$php_bin" -r 'exit(function_exists("simplexml_load_string") ? 0 : 1);' 2>/dev/null; then
        die "PHP XML extension required for rtorrent RPC. Run: /opt/bin/opkg install php8-mod-xml"
    fi
}

find_torrent_by_hash() {
    hash="$1"
    dir="$2"
    [ -n "$hash" ] && [ -d "$dir" ] || return 1

    upper="$(printf '%s' "$hash" | tr 'a-f' 'A-F')"
    lower="$(printf '%s' "$hash" | tr 'A-F' 'a-f')"
    for variant in "$hash" "$upper" "$lower"; do
        candidate="${dir}/${variant}.torrent"
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    find "$dir" -maxdepth 2 -type f -iname "${hash}.torrent" 2>/dev/null | head -1
}

multiuser_enabled() {
    [ -f "$MULTIUSER_MARKER" ] || [ -f "$HTPASSWD_FILE" ]
}

rpc_torrent_count() {
    socket="$1"
    php_bin="/opt/bin/php8-cli"
    [ -x "$php_bin" ] || php_bin="/opt/bin/php"
    RTORRENT_SCGI_SOCKET="$socket" "$php_bin" "${RECOVERY_ROOT:-/share/Public/qnap_rtorrent}/lib/rtorrent-rpc.php" download_list 2>/dev/null \
        | tr -d '[]" ' | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' '
}
