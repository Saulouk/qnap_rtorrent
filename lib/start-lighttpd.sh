#!/bin/sh
# Start lighttpd + php-cgi for ruTorrent (shared by single and multi-user configs).

start_lighttpd_stack() {
    lighttpd_conf="$1"
    lighttpd_bin="$2"
    php_cgi="$3"
    lighttpd_pidfile="${ENTWARE_ROOT}/lighttpd.pid"

    stop_lighttpd_stack

    if [ -x "$lighttpd_bin" ] && "$lighttpd_bin" -tt -f "$lighttpd_conf" >/dev/null 2>&1; then
        :
    elif [ -x "$lighttpd_bin" ]; then
        log "WARN: lighttpd config test failed:"
        "$lighttpd_bin" -tt -f "$lighttpd_conf" 2>&1 | tail -20 | while read -r line; do log "  $line"; done
    fi

    if [ -x /opt/bin/spawn-fcgi ]; then
        /opt/bin/spawn-fcgi -s /tmp/entware-php.sock -P /tmp/entware-php.pid -C 0 -n "$php_cgi" 2>/dev/null || \
            "$php_cgi" -b 127.0.0.1:9001 &
    else
        "$php_cgi" -b 127.0.0.1:9001 &
    fi
    sleep 1

    nohup "$lighttpd_bin" -f "$lighttpd_conf" -D > "${ENTWARE_LOGS}/lighttpd.out" 2>&1 &
    echo $! > "$lighttpd_pidfile"
    sleep 3

    if [ -f "$lighttpd_pidfile" ] && kill -0 "$(cat "$lighttpd_pidfile")" 2>/dev/null; then
        log "lighttpd running (pid $(cat "$lighttpd_pidfile"))"
        return 0
    fi

    if netstat -lntp 2>/dev/null | grep -q ":${WEB_PORT} "; then
        log "lighttpd appears to be listening on port ${WEB_PORT}"
        return 0
    fi

    log "lighttpd failed to start"
    tail -30 "${ENTWARE_LOGS}/lighttpd.out" 2>/dev/null | while read -r line; do log "  $line"; done
    return 1
}

stop_lighttpd_stack() {
    if [ -f "${ENTWARE_ROOT}/lighttpd.pid" ]; then
        kill "$(cat "${ENTWARE_ROOT}/lighttpd.pid")" 2>/dev/null || true
    fi
    killall lighttpd 2>/dev/null || true
    killall php-cgi 2>/dev/null || true
    killall php8-cgi 2>/dev/null || true
    rm -f /tmp/entware-php.sock /tmp/entware-php.pid
    sleep 1
}
