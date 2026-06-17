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

for pkg in rtorrent lighttpd spawn-fcgi; do
    install_pkg "$pkg" || true
done

for pkg in php8 php83 php82 php81 php80 php7 php; do
    if /opt/bin/opkg list 2>/dev/null | grep -q "^${pkg} "; then
        install_pkg "$pkg" || true
        install_pkg "${pkg}-mod-cli" 2>/dev/null || true
        install_pkg "${pkg}-mod-cgi" 2>/dev/null || true
        install_pkg "${pkg}-mod-fastcgi" 2>/dev/null || true
        break
    fi
done

install_pkg rutorrent 2>/dev/null || log "rutorrent package not in feed (will use QPKG UI copy)"

[ -x /opt/bin/rtorrent ] || die "rtorrent binary not found after install"

mkdir -p "$ENTWARE_SESSION" "$ENTWARE_DOWNLOADS" "$ENTWARE_WATCH/load" "$ENTWARE_WATCH/start" "$ENTWARE_LOGS"
chmod -R 777 "$ENTWARE_ROOT" 2>/dev/null || true

log "Installed: $(/opt/bin/rtorrent -h 2>&1 | head -1 || /opt/bin/rtorrent --version 2>&1 | head -1)"
log "Step 3 complete."
