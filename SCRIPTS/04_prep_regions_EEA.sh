#!/usr/bin/env bash
# Map the EEA mountain regions onto the EUR-12 grid as binary masks.
# A grid cell is 1 if more than 50% of its area lies in the region, otherwise 0.
# Output: RESULTS/EEA_mountain_masks_EUR12.nc
#   mask_<region> (int8, rlat x rlon) and frac_<region> (area fraction), one pair per region

set -euo pipefail

WORKDIR="/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
REGIONS="$WORKDIR/DATA/EEA_MOUNTAINS/eea_mountains_final_lonlat.gpkg"
REF="$WORKDIR/RESULTS/KNMI_RACMO23E_tas_mon_1980-2020.nc"   # exact EUR-12 grid (424 x 412)
OUT="$WORKDIR/RESULTS/EEA_mountain_masks_EUR12.nc"

python3 - "$REGIONS" "$REF" "$OUT" <<'PY'
import re
import sys

import geopandas as gpd
import numpy as np
import xarray as xr
from pyproj import Transformer
from shapely import STRtree, make_valid
from shapely.geometry import Polygon
from shapely.ops import transform

regions_path, ref_path, out_path = sys.argv[1:4]
THRESHOLD = 0.5

ref = xr.open_dataset(ref_path)
lon_b = ref["lon_bnds"].values      # (rlat, rlon, 4)
lat_b = ref["lat_bnds"].values
ny, nx = lon_b.shape[:2]

to_eq = Transformer.from_crs("EPSG:4326", "EPSG:3035", always_xy=True).transform

regions = gpd.read_file(regions_path).to_crs("EPSG:3035")
names = regions["names"].tolist()
var_names = [re.sub(r"\W+", "_", n).strip("_") for n in names]
region_geoms = [make_valid(g) for g in regions.geometry]
tree = STRtree(region_geoms)

cell_area = np.zeros((ny, nx))
frac = np.zeros((len(names), ny, nx))

for j in range(ny):
    for i in range(nx):
        lons, lats = lon_b[j, i], lat_b[j, i]
        x, y = to_eq(lons, lats)
        cell = Polygon(zip(x, y))
        if not cell.is_valid:
            cell = make_valid(cell)
        a = cell.area
        cell_area[j, i] = a
        for k in tree.query(cell, predicate="intersects"):
            inter = cell.intersection(region_geoms[k]).area
            frac[k, j, i] = inter / a

mask = (frac > THRESHOLD).astype(np.int8)

for k, n in enumerate(names):
    print(f"{n}: {int(mask[k].sum())} cells", flush=True)

coords = ["lon", "lat", "lon_bnds", "lat_bnds", "rlon", "rlat", "rlon_bnds", "rlat_bnds", "crs"]
out = ref[coords].load()
encoding = {}
for k, (vname, name) in enumerate(zip(var_names, names)):
    mname, fname = f"mask_{vname}", f"frac_{vname}"
    out[mname] = (("rlat", "rlon"), mask[k], {
        "long_name": f"EEA mountain region mask: {name}",
        "description": "1 if more than 50% of the EUR-12 grid cell area lies in the region, else 0",
        "grid_mapping": "crs",
    })
    out[fname] = (("rlat", "rlon"), frac[k].astype(np.float32), {
        "long_name": f"area fraction of EUR-12 cell inside {name}",
        "grid_mapping": "crs",
    })
    encoding[mname] = {"dtype": "int8", "zlib": True}
    encoding[fname] = {"zlib": True}
out.to_netcdf(out_path, encoding=encoding)
print(f"written: {out_path}", flush=True)
PY
