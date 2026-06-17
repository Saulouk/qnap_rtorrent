#!/bin/sh
# Step 3: Install Entware rtorrent + web stack

set -e
. "$(dirname "$0")/../lib/common.sh"

log "=== Step 3: Install Entware rtorrent stack ==="

has_entware || die "Entware not installed. Run 02-entware-check.sh and install Entware QPKG first."
ensure_entware_path

log "Updating opkg..."
/opt/bin/opkg update

install_pkg() {
    pkg="$1"
    if /opt/bin/opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
        log "Already installed: $pkg"
    else
        log "Installing: $pkg"
        /opt/bin/opkg install "$pkg" || log "WARN: failed to install $pkg"
    fi
}

# Core torrent + RPC (SCGI/XMLRPC). dtach provides the pty rtorrent expects.
for pkg in rtorrent rtorrent-rpc xmlrpc-c-server dtach; do
    install_pkg "$pkg" || true
done

# Web stack
for pkg in lighttpd lighttpd-mod-fastcgi lighttpd-mod-scgi spawn-fcgi; do
    install_pkg "$pkg" || true
done

# PHP 8 for ruTorrent (Entware naming: php8-cli, php8-cgi, not php8-mod-cli)
for pkg in php8 php8-cli php8-cgi php8-fastcgi \
    php8-mod-xml php8-mod-mbstring php8-mod-json php8-mod-session php8-mod-ctype; do
    if /opt/bin/opkg list 2>/dev/null | grep -q "^${pkg} "; then
        install_pkg "$pkg" || true
    fi
done

ensure_php_symlinks

# ruTorrent web UI
if /opt/bin/opkg list-installed 2>/dev/null | grep -q '^rutorrent '; then
    log "Already installed: rutorrent"
else
    log "Installing: rutorrent"
    /opt/bin/opkg install rutorrent || log "WARN: rutorrent install had errors (may still be usable)"
fi

[ -x /opt/bin/rtorrent ] || die "rtorrent binary not found after install"

mkdir -p "$ENTWARE_SESSION" "$ENTWARE_DOWNLOADS" "$ENTWARE_WATCH/load" "$ENTWARE_WATCH/start" "$ENTWARE_LOGS"
chmod -R 777 "$ENTWARE_ROOT" 2>/dev/null || true

log "Installed: $(/opt/bin/rtorrent -h 2>&1 | head -1 || true)"
log "Step 3 complete."
