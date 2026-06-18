#!/bin/sh
# Download latest toolkit from GitHub (no git required on NAS).

set -e
DEST="/share/Public/qnap_rtorrent"
TMP="/share/Public/qnap_rtorrent-main.tar.gz"
URL="https://github.com/Saulouk/qnap_rtorrent/archive/refs/heads/main.tar.gz"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

cd /share/Public
rm -f "$TMP"
rm -rf /share/Public/qnap_rtorrent-main

log "Downloading $URL ..."
wget -O "$TMP" "$URL" || curl -L -o "$TMP" "$URL"

if [ -d "$DEST" ]; then
    BACKUP="${DEST}.old.$(date +%s)"
    mv "$DEST" "$BACKUP"
    log "Backed up old copy to $BACKUP"
fi

tar -xzf "$TMP" -C /share/Public
mv /share/Public/qnap_rtorrent-main "$DEST"
rm -f "$TMP"

chmod +x "$DEST"/scripts/*.sh "$DEST"/lib/*.sh 2>/dev/null || true
log "Updated $DEST"
