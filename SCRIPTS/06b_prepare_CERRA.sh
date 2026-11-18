#!/usr/bin/env bash
# Prepare CERRA monthly tas, seasonal series and 1991-2020 seasonal means.
# CERRA starts in September 1984. DJF 2020 is excluded, as in scripts 02 and 06a.
# Outputs are written on both the native grid and the common EUR-12 grid.

set -euo pipefail

WORKDIR="/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
RESULTS="$WORKDIR/RESULTS"
OROG_DIR="$RESULTS/OROG"
LSM_DIR="$RESULTS/LSM"
WORK="$WORKDIR/WORK"
CERRA_DIR="/mnt/CORDEX_CMIP6_tmp/aux_data/cerra"
REF="$RESULTS/KNMI_RACMO23E_tas_mon_1980-2020.nc"
TAG="CERRA"

mkdir -p "$WORK" "$RESULTS" "$OROG_DIR" "$LSM_DIR"
TMPDIR_CERRA="$(mktemp -d "$WORK/06b-cerra.XXXXXXXX")"
cleanup() {
    rm -f -- "$TMPDIR_CERRA/eur12_griddes.txt" "$TMPDIR_CERRA/remap_tmp.nc"
    rmdir -- "$TMPDIR_CERRA"
}
trap cleanup EXIT
GRIDES="$TMPDIR_CERRA/eur12_griddes.txt"

files=()
for year in {1984..2020}; do
    file="$CERRA_DIR/mon/tas/tas_CERRA_mon_${year}.nc"
    if [[ ! -f "$file" ]]; then echo "Missing CERRA input: $file" >&2; exit 1; fi
    files+=("$file")
done
OROG="$CERRA_DIR/fx/orog_CERRA_fx_fixed.nc"
LSM="$CERRA_DIR/fx/sftlf_CERRA_fx_fixed.nc"

# Check month coverage, units and the source grid before combining the files.
python3 - "$OROG" "$LSM" "${files[@]}" <<'PY'
import sys

import numpy as np
import xarray as xr

orog, lsm, *files = sys.argv[1:]
with xr.open_dataset(files[0]) as ds:
    latitude = ds["latitude"].values
    longitude = ds["longitude"].values

for year, path in zip(range(1984, 2021), files):
    with xr.open_dataset(path) as ds:
        tas = ds["t2m"]
        if tas.dims != ("valid_time", "y", "x") or tas.attrs.get("units") != "K":
            raise ValueError(f"Unexpected temperature dimensions or units in {path}")
        dates = ds["valid_time"].values.astype("datetime64[M]")
        first = 9 if year == 1984 else 1
        expected = np.arange(f"{year}-{first:02d}", f"{year + 1}-01", dtype="datetime64[M]")
        if not np.array_equal(dates, expected):
            raise ValueError(f"Missing, duplicate or out-of-order months in {path}")
        if not (np.array_equal(ds["latitude"].values, latitude) and
                np.array_equal(ds["longitude"].values, longitude)):
            raise ValueError(f"CERRA grid mismatch in {path}")

for path, var, units in ((orog, "orog", "m"), (lsm, "sftlf", "(0 - 1)")):
    with xr.open_dataset(path) as ds:
        if ds[var].dims != ("y", "x") or ds[var].attrs.get("units") != units:
            raise ValueError(f"Unexpected {var} dimensions or units in {path}")
        if not (np.array_equal(ds["latitude"].values, latitude) and
                np.array_equal(ds["longitude"].values, longitude)):
            raise ValueError(f"CERRA grid mismatch in {path}")
        if var == "sftlf":
            values = ds[var].values
            if not np.isfinite(values).all() or values.min() < 0 or values.max() > 1:
                raise ValueError(f"Invalid land fraction in {path}")
PY

cdo -s griddes "$REF" > "$GRIDES"

mon_out="$RESULTS/${TAG}_tas_mon_1984-2020.nc"
# NCO can lose an unlimited coordinate's values when renaming it in NetCDF4.
cdo -O -s -f nc2 -chname,t2m,tas -mergetime "${files[@]}" "$mon_out"
ncrename -O -d valid_time,time -v valid_time,time "$mon_out"
python3 - "$mon_out" "${files[@]}" <<'PY'
import sys

import numpy as np
import xarray as xr

output, *files = sys.argv[1:]
dates = []
for path in files:
    with xr.open_dataset(path) as ds:
        dates.append(ds["valid_time"].values)
with xr.open_dataset(output) as ds:
    if ds["tas"].dims != ("time", "y", "x") or not np.array_equal(ds["time"].values, np.concatenate(dates)):
        raise ValueError(f"Monthly output time axis does not match the inputs: {output}")
PY
TAS_FILES=("$mon_out")

for season in DJF MAM JJA SON; do
    case "$season" in
        DJF) start="1984-12-01"; end="2019-02-28"; years="1985-2019" ;;
        MAM|JJA) start="1984-09-01"; end="2020-11-30"; years="1985-2020" ;;
        SON) start="1984-09-01"; end="2020-11-30"; years="1984-2020" ;;
    esac
    out="$RESULTS/${TAG}_tas_${season}_${years}.nc"
    cdo -O -s -f nc4 -seasmean -selseas,"$season" -seldate,"$start","$end" "$mon_out" "$out"
    TAS_FILES+=("$out")

    if [[ "$season" == DJF ]]; then
        mean_start="1990-12-01"; mean_end="2019-02-28"; mean_years="1991-2019"
    else
        mean_start="1991-01-01"; mean_end="2020-12-31"; mean_years="1991-2020"
    fi
    out="$RESULTS/${TAG}_tas_${season}_mean_${mean_years}.nc"
    cdo -O -s -f nc4 -yseasmean -selseas,"$season" -seldate,"$mean_start","$mean_end" "$mon_out" "$out"
    TAS_FILES+=("$out")
done

orog_out="$OROG_DIR/${TAG}_orog.nc"
sftlf_out="$LSM_DIR/${TAG}_sftlf.nc"
cdo -O -s -f nc4 -selname,orog "$OROG" "$orog_out"
cdo -O -s -f nc4 -mulc,100 -selname,sftlf "$LSM" "$sftlf_out"
ncatted -O -a units,sftlf,o,c,% -a standard_name,sftlf,o,c,land_area_fraction \
    -a long_name,sftlf,o,c,"Land area fraction" -a GRIB_units,sftlf,d,, "$sftlf_out"

python3 - "$REF" "$GRIDES" "$TMPDIR_CERRA" "$RESULTS" "$OROG_DIR" "$LSM_DIR" "$orog_out" "$sftlf_out" "${TAS_FILES[@]}" <<'PY'
import os
import subprocess
import sys

import numpy as np
import xarray as xr

ref_path, griddes, work, results, orog_dir, lsm_dir = sys.argv[1:7]
srcs = sys.argv[7:]
with xr.open_dataset(ref_path) as ref:
    ny_ref, nx_ref = ref["rlat"].size, ref["rlon"].size
    coords = [v for v in ("lon", "lat", "lon_bnds", "lat_bnds", "rlon", "rlat", "rlon_bnds", "rlat_bnds", "crs")
              if v in ref.variables]
    reference = ref[coords].load()
skip_attrs = ("_FillValue", "missing_value", "grid_mapping", "cell_measures", "scale_factor", "add_offset")

for src in srcs:
    tmp = os.path.join(work, "remap_tmp.nc")
    subprocess.run(["cdo", "-s", "-O", "-f", "nc", f"remapbil,{griddes}", src, tmp], check=True)
    with xr.open_dataset(src) as ds:
        variables = [v for v in ("tas", "orog", "sftlf") if v in ds.data_vars]
        if len(variables) != 1:
            raise ValueError(f"Expected one CERRA field in {src}, found {variables}")
        var = variables[0]
        attrs = {k: v for k, v in ds[var].attrs.items() if k not in skip_attrs}
        has_time = "time" in ds[var].dims
        times = ds["time"].load() if has_time else None
    with xr.open_dataset(tmp) as ds:
        vals = ds[var].values.astype(np.float32)
    os.remove(tmp)
    if vals.shape[-2:] != (ny_ref, nx_ref) or vals.ndim != (3 if has_time else 2):
        raise ValueError(f"Unexpected remapped shape for {src}: {vals.shape}")

    out = reference.copy()
    encoding = {var: {"dtype": "float32", "_FillValue": np.float32(np.nan)}}
    if has_time:
        time_coord = xr.Dataset(coords={"time": ("time", times.values, dict(times.attrs))})
        out = xr.merge([out, time_coord])
        out[var] = (("time", "rlat", "rlon"), vals, {**attrs, "grid_mapping": "crs"})
        encoding["time"] = {k: times.encoding[k] for k in ("units", "calendar", "dtype") if k in times.encoding}
    else:
        out[var] = (("rlat", "rlon"), vals, {**attrs, "grid_mapping": "crs"})
    out_dir = {"tas": results, "orog": orog_dir, "sftlf": lsm_dir}[var]
    out_path = os.path.join(out_dir, os.path.basename(src)[:-3] + "_EUR12.nc")
    out.to_netcdf(out_path, encoding=encoding)
    print(f"{os.path.basename(src)}: remapbil, missing {float(np.isnan(vals).mean()):.1%} -> {out_path}", flush=True)
PY

echo "Done. CERRA files written to $RESULTS"
