#!/bin/sh
# Historic path recovery runner (plan steps 12-16).
#
# Usage:
#   sh 12-run-historic-recovery.sh
#   sh 12-run-historic-recovery.sh extract-only
#   sh 12-run-historic-recovery.sh apply-batch 5
#   sh 12-run-historic-recovery.sh apply-all cleanup

set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/scripts"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

MODE="${1:-full}"

run() {
  s="$1"
  log "========== Running $s =========="
  sh "./$s" || {
    log "FAILED at $s"
    exit 1
  }
}

case "$MODE" in
  full)
    run 12-freeze-current.sh
    run 13-find-path-sources.sh
    run 14-extract-historic-paths.sh
    run 15-validate-historic-paths.sh
    log "========== Historic recovery prepared =========="
    log "Review: /share/Public/rtorrent-debug-backup/historic-path-map-validated-latest.tsv"
    log "Then apply a small batch:"
    log "  sh scripts/16-apply-historic-paths.sh apply 5"
    ;;
  extract-only)
    run 13-find-path-sources.sh
    sh ./14-extract-historic-paths.sh \
      /share/CACHEDEV1_DATA/Rdownload/session.bak.relocate-restored.1778458720 \
      /share/SN fallback
    run 15-validate-historic-paths.sh
    ;;
  apply-batch)
  run 16-apply-historic-paths.sh apply "${2:-5}"
    ;;
  apply-all)
    run 16-apply-historic-paths.sh apply-all "${2:-}"
    ;;
  *)
    echo "Usage: sh 12-run-historic-recovery.sh [full|extract-only|apply-batch [N]|apply-all [cleanup]]"
    exit 2
    ;;
esac
