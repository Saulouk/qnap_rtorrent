#!/bin/sh
# Start/stop helpers for one rtorrent instance (sourced by recovery scripts).

# shellcheck disable=SC2034
# Variables expected from caller: instance_name, instance_root, instance_session,
# instance_downloads, instance_socket, instance_dtach, instance_rut_conf,
# instance_watch, instance_logs, instance_pidfile

write_rtorrent_instance_conf() {
    cat > "$instance_rut_conf" <<EOF
# rtorrent 0.15 - ${instance_name}
session.path.set = ${instance_session}
directory.default.set = ${instance_downloads}
network.scgi.open_local = ${instance_socket}
schedule2 = scgi_permission, 0, 0, "execute=chmod,\"a+w\",${instance_socket}"
schedule2 = watch_load, 10, 10, "load.normal=${instance_watch}/load/*.torrent"
schedule2 = watch_start, 10, 10, "load.start=${instance_watch}/start/*.torrent"
EOF
}

prepare_rtorrent_instance_dirs() {
    mkdir -p "$instance_session" "$instance_downloads" "$instance_logs"
    mkdir -p "$instance_watch/load" "$instance_watch/start"
    chmod -R 777 "$instance_root" 2>/dev/null || true
}

stop_rtorrent_instance() {
    if [ -f "$instance_pidfile" ]; then
        oldpid="$(cat "$instance_pidfile" 2>/dev/null)"
        [ -n "$oldpid" ] && kill "$oldpid" 2>/dev/null || true
    fi
    /bin/ps -ef 2>/dev/null | awk -v conf="$instance_rut_conf" '
        /\/opt\/bin\/rtorrent/ && index($0, conf) { print $1 }' | while read -r p; do
        [ -n "$p" ] && kill "$p" 2>/dev/null || true
    done
    rm -f "$instance_socket" "$instance_pidfile"
    sleep 1
}

start_rtorrent_instance() {
    prepare_rtorrent_instance_dirs
    write_rtorrent_instance_conf
    stop_rtorrent_instance

    : > "${instance_logs}/rtorrent.out"
    : > "${instance_logs}/rtorrent.err"

    export TERM="${TERM:-vt100}"
    log "Starting rtorrent [${instance_name}] socket=${instance_socket}"
    /opt/bin/dtach -n "$instance_dtach" /opt/bin/rtorrent -n -o "import=${instance_rut_conf}" \
        >> "${instance_logs}/rtorrent.out" 2>> "${instance_logs}/rtorrent.err" || true

    sleep 6
    pid="$(/bin/ps -ef 2>/dev/null | awk -v conf="$instance_rut_conf" '
        /\/opt\/bin\/rtorrent/ && index($0, conf) { print $1; exit }')"
    if [ -n "$pid" ]; then
        echo "$pid" > "$instance_pidfile"
    fi

    if [ ! -S "$instance_socket" ]; then
        log "WARN: [${instance_name}] socket missing: $instance_socket"
        tail -20 "${instance_logs}/rtorrent.err" 2>/dev/null || true
        return 1
    fi

    result="$(scgi_test "$instance_socket")"
    if echo "$result" | grep -qiE 'version|rtorrent|methodResponse|client'; then
        log "SUCCESS: [${instance_name}] SCGI responding"
        return 0
    fi

    log "FAILED: [${instance_name}] SCGI test"
    tail -20 "${instance_logs}/rtorrent.err" 2>/dev/null || true
    return 1
}
