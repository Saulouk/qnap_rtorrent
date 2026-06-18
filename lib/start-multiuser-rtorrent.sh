#!/bin/sh
# Start both rtorrent instances (multi-user mode).

set -e
: "${RECOVERY_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
. "${RECOVERY_ROOT}/lib/common.sh"
. "${RECOVERY_ROOT}/lib/rtorrent-instance.sh"

ensure_entware_path
ensure_php_xml
[ -x /opt/bin/rtorrent ] || die "rtorrent not installed"
[ -x /opt/bin/dtach ] || die "dtach not installed"

# Saulouk — existing recovered session
instance_name="$USER_SAULOUK"
instance_root="$SAULOUK_ROOT"
instance_session="$SAULOUK_SESSION"
instance_downloads="$DATA_ROOT"
instance_socket="$SAULOUK_SOCKET"
instance_dtach="$SAULOUK_DTACH"
instance_rut_conf="$SAULOUK_RUT_CONF"
instance_watch="$SAULOUK_WATCH"
instance_logs="$SAULOUK_LOGS"
instance_pidfile="$SAULOUK_PIDFILE"
start_rtorrent_instance || {
    log "ERROR: Failed to start ${USER_SAULOUK} rtorrent"
    log "Try: sh scripts/18-restart-stack.sh"
    log "Or inspect: ${SAULOUK_LOGS}/rtorrent.err"
    exit 1
}

# Josh — empty isolated session
instance_name="$USER_JOSH"
instance_root="$JOSH_ROOT"
instance_session="$JOSH_SESSION"
instance_downloads="$DATA_ROOT"
instance_socket="$JOSH_SOCKET"
instance_dtach="$JOSH_DTACH"
instance_rut_conf="$JOSH_RUT_CONF"
instance_watch="$JOSH_WATCH"
instance_logs="$JOSH_LOGS"
instance_pidfile="$JOSH_PIDFILE"
start_rtorrent_instance || die "Failed to start ${USER_JOSH} rtorrent"

saulouk_count="$(rpc_torrent_count "$SAULOUK_SOCKET")"
josh_count="$(rpc_torrent_count "$JOSH_SOCKET")"
log "${USER_SAULOUK} torrents: ${saulouk_count}"
log "${USER_JOSH} torrents: ${josh_count}"
