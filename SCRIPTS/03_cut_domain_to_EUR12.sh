#!/usr/bin/env bash
# Cut/regrid all model files in RESULTS onto the EUR-12 grid (424 x 412).
#  - rotated grids offset by whole cells: index cut, cells outside the model domain set to NaN
#  - other grids (fractional offset, Lambert conformal): cdo remapbil onto the EUR-12 grid
# Output: RESULTS/<name>_EUR12.nc

set -euo pipefail

WORKDIR="/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
RESULTS="$WORKDIR/RESULTS"
WORK="$WORKDIR/WORK"
REF="$RESULTS/KNMI_RACMO23E_tas_mon_1980-2020.nc"   # exact EUR-12 grid (424 x 412)
GRIDES="$WORK/eur12_griddes.txt"

mkdir -p "$WORK"
cdo -s griddes "$REF" > "$GRIDES"

python3 - "$RESULTS" "$WORK" "$GRIDES" "$REF" <<'PY'
import glob
import os
import subprocess
import sys

import numpy as np
import xarray as xr

results, work, griddes, ref_path = sys.argv[1:5]

ref = xr.open_dataset(ref_path)
rlon_ref = ref["rlon"].values
rlat_ref = ref["rlat"].values
nx_ref, ny_ref = rlon_ref.size, rlat_ref.size
step = rlon_ref[1] - rlon_ref[0]
base = ref.drop_dims("time")   # EUR-12 grid definition: rlat/rlon, lon/lat, crs


def cut_to_eur(vals, rlon, rlat):
    """Index-cut a (time, y, x) array onto the EUR-12 grid; None if offset is not whole cells."""
    if not (np.allclose(np.diff(rlon), step, atol=1e-4) and np.allclose(np.diff(rlat), step, atol=1e-4)):
        return None
    ox = (rlon[0] - rlon_ref[0]) / step
    oy = (rlat[0] - rlat_ref[0]) / step
    if abs(ox - round(ox)) > 1e-3 or abs(oy - round(oy)) > 1e-3:
        return None
    ox, oy = int(round(ox)), int(round(oy))
    ny, nx = rlat.size, rlon.size
    out = np.full((vals.shape[0], ny_ref, nx_ref), np.nan, dtype=np.float32)
    # EUR-12 index j corresponds to model index j - ox (same for y)
    j0, j1 = max(0, ox), min(nx_ref, ox + nx)
    i0, i1 = max(0, oy), min(ny_ref, oy + ny)
    if j1 > j0 and i1 > i0:
        out[:, i0:i1, j0:j1] = vals[:, i0 - oy:i1 - oy, j0 - ox:j1 - ox]
    return out, ox, oy


def remap_to_eur(src):
    tmp = os.path.join(work, "remap_tmp.nc")
    subprocess.run(["cdo", "-s", "-O", "-f", "nc", f"remapbil,{griddes}", src, tmp], check=True)
    with xr.open_dataset(tmp) as t:
        vals = t["tas"].transpose("time", *t["tas"].dims[1:]).values.astype(np.float32)
    os.remove(tmp)
    if vals.shape[1:] != (ny_ref, nx_ref):
        raise RuntimeError(f"{src}: remapped grid {vals.shape[1:]} != {(ny_ref, nx_ref)}")
    return vals


files = sorted(f for f in glob.glob(os.path.join(results, "*.nc")) if not f.endswith("_EUR12.nc"))

for src in files:
    name = os.path.basename(src)[:-3]
    out_path = os.path.join(results, f"{name}_EUR12.nc")

    with xr.open_dataset(src) as ds:
        ydim, xdim = ds["tas"].dims[1], ds["tas"].dims[2]
        rlat = ds[ydim].values if ydim in ds.variables and ds[ydim].ndim == 1 else None
        rlon = ds[xdim].values if xdim in ds.variables and ds[xdim].ndim == 1 else None

        cut = cut_to_eur(ds["tas"].transpose("time", ydim, xdim).values.astype(np.float32), rlon, rlat) \
            if rlat is not None and rlon is not None else None
        if cut is not None:
            vals, ox, oy = cut
            info = f"index cut (offset x={ox}, y={oy})"
        else:
            vals = remap_to_eur(src)
            info = "remapbil"

        tas_attrs = {k: v for k, v in ds["tas"].attrs.items() if k != "cell_measures"}
        tas_attrs["grid_mapping"] = "crs"
        times = ds["time"]
        out = base.assign(tas=(("time", "rlat", "rlon"), vals, tas_attrs))
        out = out.assign_coords(time=("time", times.values, dict(times.attrs)))
        if "time_bnds" in ds.variables:
            out = out.assign(time_bnds=(("time", "bnds"), ds["time_bnds"].values, dict(ds["time_bnds"].attrs)))

        enc = {"time": {k: times.encoding[k] for k in ("units", "calendar", "dtype") if k in times.encoding}}
        out.to_netcdf(out_path, encoding=enc)

    missing = float(np.isnan(vals).mean())
    print(f"{name}: {info}, missing {missing:.1%} -> {os.path.basename(out_path)}", flush=True)
PY

find "$WORK" -mindepth 1 -delete
echo "Done. EUR-12 files written to $RESULTS"
