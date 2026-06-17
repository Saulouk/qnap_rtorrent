#!/bin/sh
# Master runner - executes recovery steps in order

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/scripts"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

for s in 01-backup-inventory.sh 02-entware-check.sh 03-install-entware-rtorrent.sh \
         04-minimal-native-test.sh 05-configure-rutorrent.sh 06-batch-import.sh 07-disable-old-qpkg.sh; do
    log "========== Running $s =========="
    sh "./$s" || {
        log "FAILED at $s"
        exit 1
    }
done

log "========== All steps completed =========="
log "Open: http://<your-nas-ip>:6010/rutorrent/"
log "Import more torrents: sh scripts/06-batch-import.sh 50"
