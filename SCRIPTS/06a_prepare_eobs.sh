#!/usr/bin/env bash
# Prepare E-OBS v31.0e mean temperature (tg, daily, 0.1 deg) as a reference tas dataset in RESULTS.
#  - daily tg (degC) -> monthly means in K (variable tas), as the model files of script 02
#  - seasonal series for the full period and for 1981-2020, and multi-year seasonal means (1981-2020),
#    with the same season windows and names as script 02
#  - all tas files and the E-OBS elevation (elevation) remapped onto the common EUR-12 grid (424 x 412)
#  - per EEA mountain region, the highest land E-OBS grid cell on the EUR-12 grid (region mask, finite orography)
# Temperature outputs go to RESULTS; EUR-12 orography and the per-region maxima go to RESULTS/OROG.

set -euo pipefail

WORKDIR="/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
WORK_ROOT="$WORKDIR/WORK"
RESULTS="$WORKDIR/RESULTS"
OROG_DIR="$RESULTS/OROG"
EOBS_DIR="/mnt/CORDEX_CMIP6_tmp/aux_data/eobs"
TG="$EOBS_DIR/tg_ens_mean_0.1deg_reg_v31.0e.nc"
ELEV="$EOBS_DIR/elev_ens_0.1deg_reg_v31.0e.nc"
REGIONS="$WORKDIR/DATA/EEA_MOUNTAINS/eea_mountains_final_lonlat.gpkg"
MAXELEV_CSV="$OROG_DIR/EOBS_maxperregion.csv"
MASKS_EUR12="$RESULTS/EEA_mountain_masks_EUR12.nc"
TAG="EOBS_v31.0e"
REF="$RESULTS/KNMI_RACMO23E_tas_mon_1980-2020.nc"   # exact EUR-12 grid (424 x 412)

# Same window logic as script 02; the full-period windows end at the last complete season of the E-OBS record (Dec 2024).
FULL_START="1950-03-01"
FULL_END="2024-11-30"
FULL_DJF_END="2023-11-30"
START="1981-03-01"
END="2020-11-30"
DJF_END="2019-11-30"
CLIM_START="1981-01-01"
CLIM_END="2020-12-31"

mkdir -p "$WORK_ROOT" "$RESULTS" "$OROG_DIR"
WORK="$(mktemp -d "$WORK_ROOT/06a-eobs.XXXXXXXX")"
cleanup() {
    rm -f -- "$WORK/eur12_griddes.txt" "$WORK/${TAG}_tas_mon_all.nc" \
        "$WORK/${TAG}_orog.nc" "$WORK/remap_eobs_tmp.nc"
    rmdir -- "$WORK"
}
trap cleanup EXIT
GRIDES="$WORK/eur12_griddes.txt"
cdo -s griddes "$REF" > "$GRIDES"

mon_all="$WORK/${TAG}_tas_mon_all.nc"
cdo -O -s -monmean -addc,273.15 -chname,tg,tas "$TG" "$mon_all"
ncatted -O -a units,tas,o,c,K "$mon_all"

years="$(cdo -s showyear "$mon_all")"
y0="$(awk '{print $1}' <<< "$years")"
y1="$(awk '{print $NF}' <<< "$years")"
mon_out="$RESULTS/${TAG}_tas_mon_${y0}-${y1}.nc"
cp -f "$mon_all" "$mon_out"

TAS_FILES=("$mon_out")

# Seasonal series for one window: $1 start, $2 end, $3 DJF end, $4 label, $5 DJF label
write_seasonal_series() {
    local start="$1" end="$2" djf_end="$3" label="$4" djf_label="$5" season stop yrs out
    for season in DJF MAM JJA SON; do
        stop="$end"; yrs="$label"
        if [[ $season == DJF ]]; then stop="$djf_end"; yrs="$djf_label"; fi
        out="$RESULTS/${TAG}_tas_${season}_${yrs}.nc"
        cdo -O -s -seasmean -selseas,"$season" -seldate,"$start","$stop" "$mon_all" "$out"
        TAS_FILES+=("$out")
    done
}

write_seasonal_series "$FULL_START" "$FULL_END" "$FULL_DJF_END" "${y0}-${y1}" "1951-2023"
write_seasonal_series "$START" "$END" "$DJF_END" "1981-2020" "1982-2019"

for season in DJF MAM JJA SON; do
    if [[ $season == DJF ]]; then
        mean_start="$START"; mean_end="$DJF_END"; mean_yrs="1982-2019"
    else
        mean_start="$CLIM_START"; mean_end="$CLIM_END"; mean_yrs="1981-2020"
    fi
    out="$RESULTS/${TAG}_tas_${season}_mean_${mean_yrs}.nc"
    cdo -O -s -yseasmean -selseas,"$season" -seldate,"$mean_start","$mean_end" "$mon_all" "$out"
    TAS_FILES+=("$out")
done

orog_raw="$WORK/${TAG}_orog.nc"
cdo -O -s -chname,elevation,orog "$ELEV" "$orog_raw"

python3 - "$REF" "$GRIDES" "$WORK" "$RESULTS" "$OROG_DIR" "$orog_raw" "${TAS_FILES[@]}" <<'PY'
import os
import subprocess
import sys

import numpy as np
import xarray as xr

ref_path, griddes, work, results, orog_dir = sys.argv[1:6]
srcs = sys.argv[6:]

ref = xr.open_dataset(ref_path)
ny_ref, nx_ref = ref["rlat"].size, ref["rlon"].size
COORDS = [v for v in ["lon", "lat", "lon_bnds", "lat_bnds", "rlon", "rlat", "rlon_bnds", "rlat_bnds", "crs"]
          if v in ref.variables]
SKIP_ATTRS = ("_FillValue", "missing_value", "grid_mapping", "cell_measures", "scale_factor", "add_offset")

for src in srcs:
    tmp = os.path.join(work, "remap_eobs_tmp.nc")
    subprocess.run(["cdo", "-s", "-O", "-f", "nc", f"remapbil,{griddes}", src, tmp], check=True)

    with xr.open_dataset(src) as ds:
        var = "tas" if "tas" in ds.data_vars else "orog"
        attrs = {k: v for k, v in ds[var].attrs.items() if k not in SKIP_ATTRS}
        has_time = "time" in ds[var].dims
        times = ds["time"] if has_time else None

    with xr.open_dataset(tmp) as t:
        vals = t[var].values.astype(np.float32)
    os.remove(tmp)

    if vals.shape[-2:] != (ny_ref, nx_ref):
        raise RuntimeError(f"{src}: remapped grid {vals.shape[-2:]} != {(ny_ref, nx_ref)}")

    out = ref[COORDS].load()
    encoding = {var: {"dtype": "float32", "_FillValue": np.float32(np.nan)}}
    if has_time:
        time_coord = xr.Dataset(coords={"time": ("time", times.values, dict(times.attrs))})
        out = xr.merge([out, time_coord])
        out[var] = (("time", "rlat", "rlon"), vals, {**attrs, "grid_mapping": "crs"})
        encoding["time"] = {k: times.encoding[k] for k in ("units", "calendar", "dtype") if k in times.encoding}
    else:
        out[var] = (("rlat", "rlon"), vals, {**attrs, "grid_mapping": "crs"})

    out_dir = orog_dir if var == "orog" else results
    out_path = os.path.join(out_dir, os.path.basename(src)[:-3] + "_EUR12.nc")
    out.to_netcdf(out_path, encoding=encoding)
    print(f"{os.path.basename(src)}: remapbil, missing {float(np.isnan(vals).mean()):.1%} -> "
          f"{os.path.basename(out_path)}", flush=True)
PY

# Highest land E-OBS cell per region on the rotated EUR-12 grid: cells in the region mask (>50% area)
# with finite orography (E-OBS orography is NaN over sea).
orog_eur12="$OROG_DIR/$(basename "$orog_raw" .nc)_EUR12.nc"
python3 - "$orog_eur12" "$MASKS_EUR12" "$MAXELEV_CSV" <<'PY'
import sys

import numpy as np
import pandas as pd
import xarray as xr

orog_path, masks_path, out_csv = sys.argv[1:4]

with xr.open_dataset(orog_path) as ds:
    z = ds["orog"].values.astype(float)
    lon = ds["lon"].values
    lat = ds["lat"].values

with xr.open_dataset(masks_path) as ds:
    masks = {v[len("mask_"):]: ds[v].values.astype(bool) for v in ds.data_vars if v.startswith("mask_")}

rows = []
for key, mask in masks.items():
    flat = np.flatnonzero((mask & np.isfinite(z)).ravel())
    if flat.size == 0:
        raise RuntimeError(f"no land EUR-12 cells in region {key}")
    iy, ix = np.unravel_index(flat[np.argmax(z.ravel()[flat])], z.shape)
    rows.append({"region": key.replace("_", " "), "max_elevation_m": round(float(z[iy, ix]), 1),
                 "lon": round(float(lon[iy, ix]), 2), "lat": round(float(lat[iy, ix]), 2)})

out = pd.DataFrame(rows)
out.to_csv(out_csv, index=False)
print(out.to_string(index=False), flush=True)
print(f"written: {out_csv}", flush=True)
PY

echo "Done. E-OBS files written to $RESULTS; per-region maxima to $MAXELEV_CSV"
