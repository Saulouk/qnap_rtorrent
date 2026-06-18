#!/bin/sh
# Step 15: Transform old roots to /share/SN and verify data exists on disk.
#
# Usage:
#   sh scripts/15-validate-historic-paths.sh
#   sh scripts/15-validate-historic-paths.sh /path/to/historic-path-map.tsv

set -e
. "$(dirname "$0")/../lib/common.sh"

ensure_entware_path

IN_MAP="${1:-${BACKUP_ROOT}/historic-path-map-latest.tsv}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_MAP="${BACKUP_ROOT}/historic-path-map-validated-${STAMP}.tsv"
ROOTS="${RECOVERY_ROOT}/path-roots.conf"
VALIDATE="${RECOVERY_ROOT}/lib/validate-historic-paths.php"

php_bin="/opt/bin/php8-cli"
[ -x "$php_bin" ] || php_bin="/opt/bin/php"
[ -x "$php_bin" ] || die "php8-cli not found"
[ -f "$IN_MAP" ] || die "Input map not found: $IN_MAP (run step 14 first)"
[ -f "$VALIDATE" ] || die "Missing validator: $VALIDATE"

log "=== Step 15: Validate historic path map ==="
log "Input: $IN_MAP"
log "Roots: $ROOTS"
log "Output: $OUT_MAP"

"$php_bin" "$VALIDATE" "$IN_MAP" "$OUT_MAP" "$ROOTS"

ln -sfn "$(basename "$OUT_MAP")" "${BACKUP_ROOT}/historic-path-map-validated-latest.tsv"

echo ""
echo "Summary:"
awk -F'\t' 'NR>1 {c[$6]++} END {for (k in c) print "  " k ": " c[k]}' "$OUT_MAP" | sort

echo ""
echo "Sample OK rows:"
awk -F'\t' 'NR>1 && $6=="OK" {print; if (++n>=10) exit}' "$OUT_MAP"

log "Validated map: $OUT_MAP"
log "Latest symlink: ${BACKUP_ROOT}/historic-path-map-validated-latest.tsv"
