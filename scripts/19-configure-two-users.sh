#!/bin/sh
# Step 19: Two-user rtorrent/ruTorrent setup (Saulouk + josh).
#
# Saulouk keeps the existing recovered torrents.
# Josh gets a separate empty rtorrent session.
# Both use download root /share/SN and one WebUI port with HTTP login.
#
# Usage:
#   sh scripts/19-configure-two-users.sh
#   sh scripts/19-configure-two-users.sh /path/to/users.credentials
#
# users.credentials format (one per line):
#   Saulouk=YourPassword
#   josh=JoshPassword

set -e
. "$(dirname "$0")/../lib/common.sh"

CRED_FILE="${1:-${RECOVERY_ROOT}/users.credentials}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/multiuser-backup-${STAMP}"

log "=== Step 19: Configure two-user rtorrent ==="

has_entware || die "Entware required"
ensure_entware_path
ensure_php_xml
[ -x /opt/bin/rtorrent ] || die "Run 03-install-entware-rtorrent.sh first"
[ -x /opt/bin/dtach ] || die "dtach required"

/opt/bin/opkg install lighttpd-mod-auth 2>/dev/null || true

mkdir -p "$BACKUP_DIR"
for f in \
    "${ENTWARE_ROOT}/lighttpd.conf" \
    "${ENTWARE_ROOT}/rtorrent.conf" \
    "${ENTWARE_ROOT}/www/rutorrent/conf/config.php" \
    "${ENTWARE_ROOT}/www/rutorrent/conf/access.ini"; do
    [ -f "$f" ] && cp "$f" "$BACKUP_DIR/" 2>/dev/null || true
done
log "Backup: $BACKUP_DIR"

read_credentials() {
    user="$1"
    if [ -f "$CRED_FILE" ]; then
        line="$(grep -E "^${user}=" "$CRED_FILE" 2>/dev/null | head -1)"
        if [ -n "$line" ]; then
            echo "${line#*=}"
            return 0
        fi
    fi
    openssl rand -base64 12 2>/dev/null | tr -d '/+=' | head -c 14
}

add_htpasswd_user() {
    user="$1"
    pass="$2"
    if command -v htpasswd >/dev/null 2>&1; then
        if [ ! -f "$HTPASSWD_FILE" ]; then
            htpasswd -bc "$HTPASSWD_FILE" "$user" "$pass" >/dev/null
        else
            htpasswd -b "$HTPASSWD_FILE" "$user" "$pass" >/dev/null
        fi
        return 0
    fi
    hash="$(openssl passwd -apr1 "$pass" 2>/dev/null)"
    if [ -z "$hash" ]; then
        die "Cannot create htpasswd entry for $user (install htpasswd or openssl)"
    fi
    echo "${user}:${hash}" >> "$HTPASSWD_FILE"
}

SAULOUK_PASS="$(read_credentials "$USER_SAULOUK")"
JOSH_PASS="$(read_credentials "$USER_JOSH")"

rm -f "$HTPASSWD_FILE"
add_htpasswd_user "$USER_SAULOUK" "$SAULOUK_PASS"
add_htpasswd_user "$USER_JOSH" "$JOSH_PASS"
chmod 600 "$HTPASSWD_FILE" 2>/dev/null || true

{
    echo "# ruTorrent login credentials — $(date)"
    echo "${USER_SAULOUK}=${SAULOUK_PASS}"
    echo "${USER_JOSH}=${JOSH_PASS}"
    echo ""
    echo "WebUI: http://$(hostname -i 2>/dev/null | awk '{print $1}'):${WEB_PORT}/rutorrent/"
} > "$MULTIUSER_CREDENTIALS"
chmod 600 "$MULTIUSER_CREDENTIALS" 2>/dev/null || true
log "Credentials saved: $MULTIUSER_CREDENTIALS"

mkdir -p "$JOSH_ROOT" "$JOSH_SESSION" "$JOSH_WATCH/load" "$JOSH_WATCH/start" "$JOSH_LOGS" "$JOSH_SETTINGS"
mkdir -p "$RUT_PROFILE_ROOT" "$SAULOUK_PROFILE" "$JOSH_PROFILE"
chmod -R 777 "$JOSH_ROOT" "$RUT_PROFILE_ROOT" 2>/dev/null || true

# Start both rtorrent daemons
export RECOVERY_ROOT
. "${RECOVERY_ROOT}/lib/start-multiuser-rtorrent.sh"

# Configure WebUI + HTTP auth
. "${RECOVERY_ROOT}/lib/configure-rutorrent-multiuser.sh"

date > "$MULTIUSER_MARKER"

saulouk_count="$(rpc_torrent_count "$SAULOUK_SOCKET")"
josh_count="$(rpc_torrent_count "$JOSH_SOCKET")"

log "=== Two-user setup complete ==="
log "${USER_SAULOUK}: ${saulouk_count} torrents (socket ${SAULOUK_SOCKET})"
log "${USER_JOSH}: ${josh_count} torrents (socket ${JOSH_SOCKET})"
log "Download root for both: ${DATA_ROOT}"
log "WebUI: http://$(hostname -i 2>/dev/null | awk '{print $1}'):${WEB_PORT}/rutorrent/"
log "Credentials: $MULTIUSER_CREDENTIALS"
log "Restart later with: sh scripts/18-restart-stack.sh"
