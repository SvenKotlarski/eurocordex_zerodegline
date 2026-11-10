# EURO-CORDEX zero-degree line: processing scripts

Working folder for the CORDEX CMIP6 near-surface air temperature (`tas`) analysis.

Folders:
- `SCRIPTS/`: processing scripts (run in the order below)
- `RESULTS/`: model outputs (monthly, seasonal, multi-year means, and EUR-12 harmonised files)
- `WORK/`: temporary files (emptied by the scripts)
- `DATA/`: input data (e.g. `DATA/EEA_MOUNTAINS`)
- `PLOTS/`: figures

## Scripts

### `SCRIPTS/01_screen_models_tas_mon.sh`
Screens the CORDEX CMIP6 archive for models that provide monthly `tas` and writes the list to `RESULTS/models_tas_mon.txt` (3 header lines, then one line per model: model, institute, path). Run with `bash SCRIPTS/01_screen_models_tas_mon.sh`.

### `SCRIPTS/02_compite_seasonal_means.sh`
For each model in `RESULTS/models_tas_mon.txt`:
1. Concatenates the time slices into one monthly file (in `WORK/`) and copies it to `RESULTS/`.
2. Writes seasonal mean time series (DJF, MAM, JJA, SON) to `RESULTS/`.
3. Writes multi-year seasonal means for 1981–2020 (one file per season, including incomplete winters) to `RESULTS/`.
4. Empties `WORK/`.

`WORKDIR` is set at the top of the script.

### `SCRIPTS/03_cut_domain_to_EUR12.sh`
Puts every `.nc` file in `RESULTS/` onto the common EUR-12 grid (424 × 412 cells, rotated pole at −162°E / 39.25°N, 0.11° spacing; definition from the WCRP CORDEX domain table). Output files are named `<original name>_EUR12.nc` and are written to `RESULTS/`. The reference grid is taken from `RESULTS/KNMI_RACMO23E_tas_mon_1980-2020.nc`, which matches EUR-12 exactly. Official grid definition: https://wcrp-cordex.github.io/cordex-tutorials/domains.html. 

Method per model (grid offsets measured against EUR-12):

| Treatment | Models | Details |
|---|---|---|
| Index cut, no shift (offset 0) | GERICS REMO2020-2-2 (base, MR2, TEB, iMOVE, iMOVE-LUC), CLMcom-Hereon CCLM6-0-1, CLMcom-Hereon ICON-CLM-202407-1-1, CLMcom-FZJ TSMP1-140-E, CLMcom-KUL CCLM6-0-1-URB-ESG, DWD-BSH ROAM-NBS, KNMI RACMO23E | Already on the EUR-12 grid; values copied unchanged. |
| Index cut, shifted by whole cells | AUTH WRF451Q, IDL-FCUL WRF451Q, CESAM-UA WRF451Q (424 × 412, offset −5 cells in x and y) | Cells are taken from the model by index. EUR-12 cells outside the model domain (eastern and northern edges, about 5 cells) are set to missing (NaN). |
| Index cut, different size | CLMcom-CMCC CCLM6-0-1-URB (418 × 406, offset +3 cells) | Padded to 424 × 412; cells outside the CMCC domain are missing (NaN). |
| Index cut, different size | CLMcom-Hereon GCOAST-AHOIB1-1 (450 × 438, offset −13 cells) | Cropped to the EUR-12 domain (the 13 outer cells on the western and southern sides are dropped). |
| `cdo remapbil` (bilinear interpolation) | MOHC HadREM3-GA7-05 (same grid, but coordinates are named `grid_longitude`/`grid_latitude`, so the script does not find `rlon`/`rlat` and remaps; about 0.5% of cells end up missing) | Interpolated onto the EUR-12 grid. |
| `cdo remapbil` (bilinear interpolation) | ICTP RegCM5-0 (fractional offset, about −3.7 and −15.2 cells, different pole representation) | Interpolated onto the EUR-12 grid. Cells outside the model domain are missing (about 5%). |
| `cdo remapbil` (bilinear interpolation) | CNRM-MF CNRM-ALADIN64E1 (453 × 453), HCLIMcom-SMHI HCLIM43-ALADIN (453 × 453), RMIB-UGent ALARO1-SFX (483 × 483) | Lambert conformal grids with 2-D coordinates, interpolated onto the EUR-12 grid. Cells outside the model domain are missing. |

Notes:
- Index cut keeps the original model values. Bilinear remapping changes values slightly (interpolation) and is used only where the grids are not aligned with EUR-12.
- Every output has the same grid (424 × 412), the same coordinates (`rlat`, `rlon`, 2-D `lon`/`lat`, `crs`) and the same time axis as its input file.
- The script prints the treatment and fraction of missing cells for each file; check this log against the table above.
- Temporary files are written to `WORK/`, which is emptied at the end of the script.

### `SCRIPTS/04_prep_regions_EEA.sh`
Maps the EEA mountain regions (`DATA/EEA_MOUNTAINS/eea_mountains_final_lonlat.gpkg`) onto the EUR-12 grid. For each EUR-12 cell, the overlap with each region is computed as area fraction (in EPSG:3035, using the cell corners from `lon_bnds`/`lat_bnds` of the EUR-12 reference file). A cell is 1 in the region mask if more than 50% of its area lies in the region, otherwise 0.

Output: `RESULTS/EEA_mountain_masks_EUR12.nc` on `rlat` (412) × `rlon` (424). There is one variable per region (CDO cannot read a `region` dimension):
- `mask_<region>`: int8 binary mask (1 = more than 50% of the cell in the region, 0 otherwise)
- `frac_<region>`: area fraction of each cell inside the region (for checking the threshold)

Regions: Alps, Apennines, Balkans, British Isles, Carpathians, Central European mountains, French Swiss mountains, Iberian mountains, Iceland, Pyrenees, Scandes, Turkey.

### `SCRIPTS/05_prepare_orog_lsm.sh`
For each model in `RESULTS/models_tas_mon.txt`, takes the static fields `orog` (orography, m) and `sftlf` (land area fraction, %) from the model's `fx` folder (`<run>/fx/orog/<version>/` and `<run>/fx/sftlf/<version>/`, same run as the `tas` data, newest version folder) and puts them onto the EUR-12 grid with the same method as script 03 (index cut for aligned grids, `cdo remapbil` otherwise; cells outside the model domain are NaN).

Output:
- `RESULTS/OROG/<INST>_<MODEL>_orog_EUR12.nc`
- `RESULTS/LSM/<INST>_<MODEL>_sftlf_EUR12.nc`

Both are 412 × 424 on the EUR-12 `rlat`/`rlon` axes. The `sftlaf` folders (land area fraction, other name) are not used.

Method per model (same grouping as script 03):
- Index cut, offset 0: GERICS (base, MR2, TEB, iMOVE, iMOVE-LUC), CLMcom-Hereon CCLM6-0-1 and ICON-CLM-202407-1-1, CLMcom-FZJ TSMP1-140-E, CLMcom-KUL CCLM6-0-1-URB-ESG, DWD-BSH ROAM-NBS, KNMI RACMO23E.
- Index cut, shifted by −5 cells: AUTH WRF451Q, IDL-FCUL WRF451Q, CESAM-UA WRF451Q (2.4% of EUR-12 cells missing).
- Index cut, +3 cells: CLMcom-CMCC CCLM6-0-1-URB (2.9% missing).
- Index cut, −13 cells: CLMcom-Hereon GCOAST-AHOIB1-1.
- `remapbil`: MOHC HadREM3-GA7-05 (0.5% missing), ICTP RegCM5-0 (5% missing), CNRM-MF CNRM-ALADIN64E1, HCLIMcom-SMHI HCLIM43-ALADIN, RMIB-UGent ALARO1-SFX.

Notes:
- Missing values are written as NaN. `sftlf` is in percent (0–100), and `orog` is in metres.

Open items:
- **MOHC fx files:** the `fx` files for MOHC HadREM3 are in the `v20260219` folder and are labelled `MOHC_HadREM3-GA7-01`, while the `tas` data is GA7-05. They are used as they are; confirm they are the intended files.
- **`sftlaf` folders:** script 05 uses only `fx/sftlf`. Some models also provide `fx/sftlaf`, which has not been checked or used. Decide whether it should be a fallback.
- **Script 04 threshold (related):** the "--> 0" in the request for cells outside a region was read as 1 for in-region cells (more than 50% of the cell area) and 0 otherwise. Confirm this interpretation.

### `SCRIPTS/06_prepare_eobs.sh`
Prepares the E-OBS v31.0e mean temperature (`tg`, daily, 0.1°) as a reference dataset, following the same steps and file names as script 02. Run with `bash SCRIPTS/06_prepare_eobs.sh`.

Inputs (in `/mnt/CORDEX_CMIP6_tmp/aux_data/eobs/`): `tg_ens_mean_0.1deg_reg_v31.0e.nc` and `elev_ens_0.1deg_reg_v31.0e.nc`.

Steps:
1. Daily `tg` (°C) is converted to monthly means in K (variable `tas`, 1950–2024).
2. Seasonal series for the full period (`EOBS_v31.0e_tas_<SEASON>_1950-2024.nc`; DJF `1951-2023`) and for 1981–2020 (`EOBS_v31.0e_tas_<SEASON>_1981-2020.nc`; DJF `1982-2019`), using the windows of script 02.
3. Multi-year seasonal means over 1981–2020 (`EOBS_v31.0e_tas_<SEASON>_mean_1981-2020.nc`; DJF `..._mean_1982-2019.nc`).
4. Every tas file is remapped (`cdo remapbil`) onto the EUR-12 grid, giving `<name>_EUR12.nc`. E-OBS covers land only and a smaller domain than EUR-12, so about 63–65% of the EUR-12 cells are missing.
5. The E-OBS elevation (`elevation`, m) is renamed to `orog` and remapped onto EUR-12 as `RESULTS/EOBS_v31.0e_orog_EUR12.nc`.

Output: `RESULTS/EOBS_v31.0e_*.nc` (native grid) and `RESULTS/EOBS_v31.0e_*_EUR12.nc` (EUR-12 grid).

### `SCRIPTS/07a_compute_ZDL_seasonal_indivmodels.R`
R script that estimates the zero-degree line (ZDL) for each model, mountain region and season. It runs with the conda env `zdl-r`, which provides R and `ncdf4` (the system R has no usable netCDF support):

```bash
/home/skotlarski/.conda/envs/zdl-r/bin/Rscript SCRIPTS/07a_compute_ZDL_seasonal_indivmodels.R
```

Inputs:
- `RESULTS/<INST>_<MODEL>_tas_<SEASON>_mean_1981-2020_EUR12.nc` (multi-year seasonal mean tas, K converted to °C; for DJF `..._DJF_mean_1982-2019_EUR12.nc`, excluding the incomplete winters DJF 1981 and DJF 2020)
- `RESULTS/OROG/<INST>_<MODEL>_orog_EUR12.nc` (orography, m)
- `RESULTS/LSM/<INST>_<MODEL>_sftlf_EUR12.nc` (land fraction, % converted to 0–1)
- `RESULTS/EEA_mountain_masks_EUR12.nc` (`mask_<region>`)

Method per model, region and season:
- Grid cells are used if the region mask equals 1, orography is finite, and the land fraction is greater than 0.5.
- Linear regression `tas ~ orog`.
- ZDL = elevation where the fit equals 0 °C, i.e. −a/b. It is reported only if the slope b is negative and the elevation lies within the orography range of the selected cells. Otherwise it is NA (pure extrapolation is treated as missing).

Output: `PLOTS/ZDL/<INST>_<MODEL>_<Region>_ZDL.png`, one figure per model and region (252 files = 21 models × 12 regions). Each figure has four panels (DJF, MAM, JJA, SON) showing tas (°C, x-axis) against orography (m, y-axis), the fitted line, the ZDL (blue dashed line with its elevation), a dotted 0 °C reference, and n and R² in the title. A summary line per model and region is printed to stdout.

Tables: `RESULTS/ZDL/<Region>_<SEASON>_ZDL.csv` (48 files = 12 regions × 4 seasons). Each is tab-separated with the header `MODEL<TAB>ZDL`, a line of `========`, then one row per model, where MODEL is `<INST>_<MODEL>` and ZDL is the zero-degree elevation in m (rounded), or `NA` if missing.

Caveats:
- A ZDL outside the elevation range of the selected cells is an extrapolation and is set to missing; the panel then shows "ZDL outside data range (missing)". Many JJA and some DJF/MAM values are missing for this reason, especially in the Iberian mountains, Scandes and Iceland.
- The land threshold "> 0.5 sftlf" is implemented as land fraction > 0.5 (sftlf > 50 %). Read ZDL values with the R² in each panel.

### `SCRIPTS/07b_compute_ZDL_seasonal_eobs.R`
Same ZDL calculation as script 07a, for E-OBS (`EOBS_v31.0e`) instead of the models, using the E-OBS orography. Run with the same conda env:

```bash
/home/skotlarski/.conda/envs/zdl-r/bin/Rscript SCRIPTS/07b_compute_ZDL_seasonal_eobs.R
```

Inputs:
- `RESULTS/EOBS_v31.0e_tas_<SEASON>_mean_1981-2020_EUR12.nc` (DJF `..._mean_1982-2019_EUR12.nc`), from script 06
- `RESULTS/EOBS_v31.0e_orog_EUR12.nc` (orography, m), from script 06
- `RESULTS/EEA_mountain_masks_EUR12.nc` (`mask_<region>`)

Method per region and season: same as script 07a, with two differences. E-OBS has no land-fraction field, so the cells are those with the region mask equal to 1 and finite tas and orography (E-OBS has values over land only). The land threshold is not applied.

Output:
- `PLOTS/ZDL_EOBS/EOBS_v31.0e_<Region>_ZDL.png` (12 figures, same layout as script 07a)
- `RESULTS/ZDL_EOBS/<Region>_<SEASON>_ZDL.csv` (48 files, same format as `RESULTS/ZDL`, with the single row `EOBS_v31.0e`)

These are kept apart from `RESULTS/ZDL` so that script 08 does not include E-OBS in the model ensemble overview.

Caveat: many regions and seasons have no E-OBS ZDL, because the fit has no negative slope or the zero-degree elevation lies outside the orography range of the selected cells. The region label "mm" in the output names comes from the mask variable names in `EEA_mountain_masks_EUR12.nc` (for example `Central_European_mm`), which is also the case for script 07a.

### `SCRIPTS/08_plot_ZDL_perregion_fullensemble_eobs.R`
Overview figures of the ZDL tables from script 07a (models) and script 07b (E-OBS). Reads `RESULTS/ZDL/<Region>_<SEASON>_ZDL.csv` and `RESULTS/ZDL_EOBS/<Region>_<SEASON>_ZDL.csv` (tab-separated, header `MODEL<TAB>ZDL`, then a `========` line). Runs with base R; use the same Rscript as for script 07a or any R installation.

```bash
Rscript SCRIPTS/08_plot_ZDL_perregion_fullensemble_eobs.R
```

Output: `PLOTS/ZDL/ZDL_overview_<Region>.png`, one figure per region (12 files). Each has four panels (DJF, MAM, JJA, SON) placed side by side in one row, with a common y-axis (ZDL in m) shared by all panels of a region and no x-axis. Every model is a horizontal line at its ZDL; missing ZDL values are skipped. The E-OBS ZDL is a black line in each panel where it is available (legend entry "E-OBS"). The legend sits below the panels.

Colours are fixed per model across all regions. Variants of the same model family share a hue and differ in lightness (families: REMO2020, WRF451Q, CCLM6, ICON-CLM, ALADIN/ALARO; other models have their own hue). The legend below the panels lists all models.
