#!/usr/bin/env Rscript
# Annual seasonal E-OBS ZDL by mountain region, 1981-2020.
# Run with /home/skotlarski/.conda/envs/zdl-r/bin/Rscript.

suppressPackageStartupMessages(library(ncdf4))

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
source(file.path(ROOT, "SCRIPTS", "09_zdl_timeseries_helpers.R"))
RESULTS <- file.path(ROOT, "RESULTS")
ZDL_DIR <- file.path(RESULTS, "ZDL_EOBS")
TAG <- "EOBS_v31.0e"
SEASONS <- c("DJF", "MAM", "JJA", "SON")
YEARS <- 1981:2020

mask_nc <- nc_open(file.path(RESULTS, "EEA_mountain_masks_EUR12.nc"))
mask_names <- grep("^mask_", names(mask_nc$var), value = TRUE)
if (!length(mask_names)) stop("No region masks found")
masks <- setNames(lapply(mask_names, function(v) ncvar_get(mask_nc, v)), mask_names)
nc_close(mask_nc)
regions <- sub("^mask_", "", mask_names)
orog <- read_var(file.path(RESULTS, paste0(TAG, "_orog_EUR12.nc")), "orog")
if (any(!vapply(masks, function(mask) identical(dim(mask), dim(orog)), logical(1)))) {
  stop("Grid dimension mismatch for ", TAG)
}
base_ok <- lapply(masks, function(mask) which(mask == 1 & is.finite(orog)))

rows <- setNames(lapply(regions, function(r) setNames(vector("list", length(SEASONS)), SEASONS)), regions)
for (season in SEASONS) {
  period <- if (season == "DJF") "1982-2019" else "1981-2020"
  file <- file.path(RESULTS, sprintf("%s_tas_%s_%s_EUR12.nc", TAG, season, period))
  dates <- read_dates(file)
  file_years <- as.integer(substr(dates, 1, 4))
  expected <- if (season == "DJF") 1982:2019 else YEARS
  if (!identical(file_years, expected)) stop("Unexpected seasonal years in ", file)
  nc <- open_tas(file, dim(orog))
  if (nc$dim$time$len != length(dates)) stop("Time dimension mismatch in ", file)
  values <- matrix(NA_character_, nrow = length(regions), ncol = length(YEARS))
  for (j in seq_along(file_years)) {
    tas <- read_tas_step(nc, j)
    for (i in seq_along(regions)) {
      ok <- base_ok[[i]][is.finite(tas[base_ok[[i]]])]
      values[i, match(file_years[j], YEARS)] <- format_zdl(fit_zdl(tas[ok], orog[ok]))
    }
  }
  nc_close(nc)
  for (i in seq_along(regions)) {
    vals <- values[i, ]
    vals[is.na(vals)] <- "NA"
    rows[[regions[i]]][[season]] <- paste(c(TAG, vals), collapse = "\t")
  }
  cat("Computed E-OBS seasonal time series for", season, "\n")
}

dir.create(ZDL_DIR, recursive = TRUE, showWarnings = FALSE)
header <- paste(c("MODEL", YEARS), collapse = "\t")
separator <- paste(rep("=", nchar(header)), collapse = "")
for (region in regions) {
  for (season in SEASONS) {
    file <- file.path(ZDL_DIR, sprintf("%s_%s_ZDL_timeseries.csv", region, season))
    writeLines(c(header, separator, rows[[region]][[season]]), file)
  }
}
cat("E-OBS ZDL time series written to", ZDL_DIR, "\n")
