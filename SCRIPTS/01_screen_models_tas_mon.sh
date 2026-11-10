#!/usr/bin/env bash
# Screen EUR-12 for models providing monthly tas from the ERA5-driven evaluation run.
# Writes ../RESULTS/models_tas_mon.txt (relative to this script).

set -euo pipefail

BASE="/mnt/CORDEX_CMIP6_tmp/sim_data/CORDEX-CMIP6/DD/EUR-12"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/../RESULTS/models_tas_mon.txt"

# Permission-denied errors on some subtrees are expected; ignore them.
# Keep one line per institute/RCM; if several versions exist, the latest (last sorted) wins.
{
    echo "Available models: tas mon"
    echo
    printf '%-28s %-16s %s\n' "MODEL" "INSTITUTE" "PATH"
    { find "$BASE" -path '*/ERA5/evaluation/*/mon/tas/*' -name '*.nc' 2>/dev/null || true; } \
        | sed "s|^$BASE/||" \
        | awk -F/ 'NF >= 10 && $2 == "ERA5" && $3 == "evaluation" && $7 == "mon" && $8 == "tas" {
            print $1, $5, $1"/"$2"/"$3"/"$4"/"$5"/"$6"/"$7"/"$8"/"$9 }' \
        | sort -k1,1 -k2,2 -k3,3 -u \
        | awk -v base="$BASE" '{ k = $1 SUBSEP $2; if (!(k in line)) order[++n] = k; line[k] = $0 }
            END { for (i = 1; i <= n; i++) { split(line[order[i]], f, " "); printf "%-28s %-16s %s/%s\n", f[2], f[1], base, f[3] } }'
} > "$OUT"

echo "Wrote $(($(wc -l < "$OUT") - 3)) models to: $OUT"
