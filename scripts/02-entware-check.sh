#!/bin/sh
# Step 2: Verify Entware/opkg and rtorrent package availability

set -e
. "$(dirname "$0")/../lib/common.sh"

REPORT="${BACKUP_ROOT}/entware-check-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$BACKUP_ROOT"

log "=== Step 2: Entware check ==="

{
    echo "Entware availability report"
    echo "Date: $(date)"
    echo "Arch: $(uname -m)"
    echo ""

    if has_entware; then
        echo "Entware: INSTALLED at /opt"
        ensure_entware_path
        echo "opkg version: $(/opt/bin/opkg --version 2>/dev/null || echo unknown)"
        echo ""
        echo "Searching packages..."
        /opt/bin/opkg update 2>&1 | tail -5
        echo ""
        for pkg in rtorrent rtorrent-easy-install rutorrent lighttpd php8 php83 php82 php81 php80 spawn-fcgi; do
            found=$(/opt/bin/opkg list 2>/dev/null | grep -i "^${pkg} " | head -1)
            if [ -n "$found" ]; then
                echo "FOUND: $found"
            else
                echo "MISSING: $pkg"
            fi
        done
        echo ""
        echo "Installed rtorrent-related:"
        /opt/bin/opkg list-installed 2>/dev/null | grep -iE 'rtorrent|rutorrent|lighttpd|php' || echo "(none)"
    else
        echo "Entware: NOT INSTALLED"
        echo ""
        echo "Install Entware QPKG from App Center (Install Manually) or:"
        echo "  https://github.com/Entware/Entware/wiki/Install-on-QNAP-NAS"
        echo ""
        if [ -d /share/CACHEDEV1_DATA/.qpkg/Entware ]; then
            echo "Entware QPKG folder exists but /opt/bin/opkg missing - may need Entware start/reinstall"
        fi
    fi

    echo ""
    echo "Broken QPKG rtorrent:"
    if [ -x /share/CACHEDEV1_DATA/.qpkg/rtorrent/bin/rtorrent ]; then
        echo "  Present at /share/CACHEDEV1_DATA/.qpkg/rtorrent/bin/rtorrent"
        /share/CACHEDEV1_DATA/.qpkg/rtorrent/bin/rtorrent -h 2>&1 | head -3 || true
    else
        echo "  Not found or not executable"
    fi
} | tee "$REPORT"

log "Report saved: $REPORT"
log "Step 2 complete."
