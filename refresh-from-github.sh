#!/bin/sh
# Download latest recovery scripts without git credentials

set -e
DEST="/share/Public/qnap_rtorrent"
TMP="/share/Public/qnap_rtorrent-main.tar.gz"
URL="https://github.com/Saulouk/qnap_rtorrent/archive/refs/heads/main.tar.gz"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Downloading $URL ..."
wget -O "$TMP" "$URL" || curl -L -o "$TMP" "$URL"

BACKUP="${DEST}.bak.$(date +%s)"
[ -d "$DEST" ] && mv "$DEST" "$BACKUP" && log "Backed up old copy to $BACKUP"

mkdir -p /share/Public
tar -xzf "$TMP" -C /share/Public
mv /share/Public/qnap_rtorrent-main "$DEST"
rm -f "$TMP"

chmod +x "$DEST"/*.sh "$DEST"/scripts/*.sh
log "Updated $DEST from GitHub (no git required)"
log "Run: cd $DEST && ./00-run-all.sh"
