#!/usr/bin/env bash
# For each model in RESULTS/models_tas_mon.txt: concatenate monthly tas time slices (WORK),
# then write the monthly series, seasonal-mean time series and multi-year seasonal means (1981-2020) to RESULTS.
# CDO labels DJF by the year of its January, so DJF 1981 (Jan-Feb 1981) and DJF 2020 (Dec 2019-Feb 2020)
# are excluded by the DJF window below. The DJF multi-year mean uses the same complete winters (1982-2019).

set -euo pipefail

WORKDIR="/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
MODELS_FILE="$WORKDIR/RESULTS/models_tas_mon.txt"
WORK="$WORKDIR/WORK"
RESULTS="$WORKDIR/RESULTS"
START="1981-03-01"
END="2020-11-30"
DJF_END="2019-11-30"
CLIM_START="1981-01-01"
CLIM_END="2020-12-31"

mkdir -p "$WORK" "$RESULTS"

# Skip the 3 header lines written by 01_screen_models_tas_mon.sh.
mapfile -t LINES < <(tail -n +4 "$MODELS_FILE" | awk 'NF >= 3')

for line in "${LINES[@]}"; do
    read -r model inst path _ <<< "$line"
    tag="${inst}_${model}"
    echo "== $tag"

    mapfile -t files < <(find "$path" -maxdepth 1 -name '*.nc' | sort)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No .nc files in $path" >&2
        exit 1
    fi

    mon_all="$WORK/${tag}_tas_mon_all.nc"
    cdo -O -s mergetime "${files[@]}" "$mon_all"
    years="$(cdo -s showyear "$mon_all")"
    y0="$(awk '{print $1}' <<< "$years")"
    y1="$(awk '{print $NF}' <<< "$years")"
    cp -f "$mon_all" "$RESULTS/${tag}_tas_mon_${y0}-${y1}.nc"

    for season in DJF MAM JJA SON; do
        if [[ $season == DJF ]]; then
            yrs="1982-2019"; stop="$DJF_END"; mean_start="$START"; mean_end="$DJF_END"; mean_yrs="$yrs"
        else
            yrs="1981-2020"; stop="$END"; mean_start="$CLIM_START"; mean_end="$CLIM_END"; mean_yrs="1981-2020"
        fi
        cdo -O -s -seasmean -selseas,"$season" -seldate,"$START","$stop" \
            "$mon_all" "$RESULTS/${tag}_tas_${season}_${yrs}.nc"
        cdo -O -s -yseasmean -selseas,"$season" -seldate,"$mean_start","$mean_end" \
            "$mon_all" "$RESULTS/${tag}_tas_${season}_mean_${mean_yrs}.nc"
    done
done

find "$WORK" -mindepth 1 -delete

echo "Done: ${#LINES[@]} models written to $RESULTS"
