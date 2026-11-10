#!/usr/bin/env bash
# Cut/remap orography (orog) and land-sea mask (sftlf) of every model in RESULTS/models_tas_mon.txt
# onto the common EUR-12 grid (424 x 412), using the static fields from each model's fx folder.
#  - grids aligned with EUR-12 (whole-cell offset): index cut, cells outside the model domain set to NaN
#  - other grids (fractional offset, Lambert conformal): cdo remapbil onto the EUR-12 grid
# Output: RESULTS/OROG/<INST>_<MODEL>_orog_EUR12.nc and RESULTS/LSM/<INST>_<MODEL>_sftlf_EUR12.nc

set -euo pipefail

WORKDIR="/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
RESULTS="$WORKDIR/RESULTS"
WORK="$WORKDIR/WORK"
MODELS_FILE="$RESULTS/models_tas_mon.txt"
REF="$RESULTS/KNMI_RACMO23E_tas_mon_1980-2020.nc"   # exact EUR-12 grid (424 x 412)
GRIDES="$WORK/eur12_griddes.txt"
OROG_DIR="$RESULTS/OROG"
LSM_DIR="$RESULTS/LSM"

mkdir -p "$WORK" "$OROG_DIR" "$LSM_DIR"
cdo -s griddes "$REF" > "$GRIDES"

python3 - "$MODELS_FILE" "$REF" "$GRIDES" "$WORK" "$OROG_DIR" "$LSM_DIR" <<'PY'
import glob
import os
import subprocess
import sys

import numpy as np
import xarray as xr

models_file, ref_path, griddes, work, orog_dir, lsm_dir = sys.argv[1:7]
STEP_TOL = 1e-4

ref = xr.open_dataset(ref_path)
rlon_ref = ref["rlon"].values
rlat_ref = ref["rlat"].values
nx_ref, ny_ref = rlon_ref.size, rlat_ref.size
step = rlon_ref[1] - rlon_ref[0]
COORDS = ["lon", "lat", "lon_bnds", "lat_bnds", "rlon", "rlat", "rlon_bnds", "rlat_bnds", "crs"]


def index_cut(vals, rlon, rlat):
    """Place model cells on the EUR-12 grid by index; None if the grid is not aligned with it."""
    if rlon.size < 2 or rlat.size < 2:
        return None
    if not (np.allclose(np.diff(rlon), step, atol=STEP_TOL) and np.allclose(np.diff(rlat), step, atol=STEP_TOL)):
        return None
    ox = (rlon[0] - rlon_ref[0]) / step
    oy = (rlat[0] - rlat_ref[0]) / step
    if abs(ox - round(ox)) > 1e-3 or abs(oy - round(oy)) > 1e-3:
        return None
    ox, oy = int(round(ox)), int(round(oy))
    ny, nx = rlat.size, rlon.size
    out = np.full((ny_ref, nx_ref), np.nan, dtype=np.float32)
    j0, j1 = max(0, ox), min(nx_ref, ox + nx)
    i0, i1 = max(0, oy), min(ny_ref, oy + ny)
    if j1 > j0 and i1 > i0:
        out[i0:i1, j0:j1] = vals[i0 - oy:i1 - oy, j0 - ox:j1 - ox]
    return out, ox, oy


def remap_to_eur(src, var):
    tmp = os.path.join(work, "remap_static_tmp.nc")
    subprocess.run(["cdo", "-s", "-O", "-f", "nc", f"remapbil,{griddes}", src, tmp], check=True)
    with xr.open_dataset(tmp) as t:
        vals = t[var].values.astype(np.float32)
    os.remove(tmp)
    if vals.shape != (ny_ref, nx_ref):
        raise RuntimeError(f"{src}: remapped grid {vals.shape} != {(ny_ref, nx_ref)}")
    return vals


def latest_fx_file(fx_dir, var):
    """Newest version folder of fx/<var>, file <var>_*.nc inside it."""
    vdir = os.path.join(fx_dir, var)
    versions = sorted(d for d in os.listdir(vdir) if d.startswith("v") and os.path.isdir(os.path.join(vdir, d)))
    if not versions:
        raise FileNotFoundError(f"no version folder in {vdir}")
    files = glob.glob(os.path.join(vdir, versions[-1], f"{var}_*.nc"))
    if len(files) != 1:
        raise FileNotFoundError(f"expected one {var} file in {vdir}/{versions[-1]}, found {len(files)}")
    return files[0]


def process(src, var, out_dir, tag):
    with xr.open_dataset(src) as ds:
        field = ds[var]
        attrs = {k: v for k, v in field.attrs.items() if k not in ("_FillValue", "missing_value", "grid_mapping", "cell_measures")}
        ydim, xdim = field.dims[-2], field.dims[-1]
        rlat = ds[ydim].values if ydim in ds.coords and ds[ydim].ndim == 1 else None
        rlon = ds[xdim].values if xdim in ds.coords and ds[xdim].ndim == 1 else None
        vals = field.values.astype(np.float32)

        cut = index_cut(vals, rlon, rlat) if rlat is not None and rlon is not None else None
        if cut is not None:
            out_vals, ox, oy = cut
            info = f"index cut (offset x={ox}, y={oy})"
        else:
            out_vals = remap_to_eur(src, var)
            info = "remapbil"

    out = ref[COORDS].load()
    out[var] = (("rlat", "rlon"), out_vals, {**attrs, "grid_mapping": "crs"})
    out_path = os.path.join(out_dir, f"{tag}_{var}_EUR12.nc")
    out.to_netcdf(out_path, encoding={var: {"dtype": "float32", "_FillValue": np.float32(np.nan), "zlib": True}})
    missing = float(np.isnan(out_vals).mean())
    print(f"{tag} {var}: {info}, missing {missing:.1%} -> {out_path}", flush=True)


with open(models_file) as fh:
    rows = [line.split() for line in fh if line.strip()]
models = [r for r in rows if len(r) == 3 and r[2].startswith("/")]

for model, inst, path in models:
    tag = f"{inst}_{model}"
    fx_dir = path.split("/mon/tas/")[0] + "/fx"
    for var, out_dir in (("orog", orog_dir), ("sftlf", lsm_dir)):
        src = latest_fx_file(fx_dir, var)
        process(src, var, out_dir, tag)
PY

find "$WORK" -mindepth 1 -delete
echo "Done. Orography written to $OROG_DIR, land-sea masks to $LSM_DIR"
