#!/usr/bin/env Rscript
# Annual seasonal CERRA ZDL by mountain region, 1984-2020.
# Run with /home/skotlarski/.conda/envs/zdl-r/bin/Rscript.

suppressPackageStartupMessages(library(ncdf4))

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
source(file.path(ROOT, "SCRIPTS", "09_zdl_timeseries_helpers.R"))
RESULTS <- file.path(ROOT, "RESULTS")
ZDL_DIR <- file.path(RESULTS, "ZDL_CERRA")
TAG <- "CERRA"
SEASONS <- c("DJF", "MAM", "JJA", "SON")
YEARS <- 1984:2020
LAND_MIN <- 0.5

mask_nc <- nc_open(file.path(RESULTS, "EEA_mountain_masks_EUR12.nc"))
mask_names <- grep("^mask_", names(mask_nc$var), value = TRUE)
if (!length(mask_names)) stop("No region masks found")
masks <- setNames(lapply(mask_names, function(v) ncvar_get(mask_nc, v)), mask_names)
nc_close(mask_nc)
regions <- sub("^mask_", "", mask_names)
orog <- read_var(file.path(RESULTS, "OROG", paste0(TAG, "_orog_EUR12.nc")), "orog")
land <- read_var(file.path(RESULTS, "LSM", paste0(TAG, "_sftlf_EUR12.nc")), "sftlf") / 100
if (!identical(dim(land), dim(orog)) ||
    any(!vapply(masks, function(mask) identical(dim(mask), dim(orog)), logical(1)))) {
  stop("Grid dimension mismatch for ", TAG)
}
base_ok <- lapply(masks, function(mask) {
  which(mask == 1 & is.finite(orog) & is.finite(land) & land > LAND_MIN)
})

rows <- setNames(lapply(regions, function(r) setNames(vector("list", length(SEASONS)), SEASONS)), regions)
for (season in SEASONS) {
  period <- switch(season, DJF = "1985-2019", MAM = "1985-2020",
                   JJA = "1985-2020", SON = "1984-2020")
  expected <- switch(season, DJF = 1985:2019, MAM = 1985:2020,
                     JJA = 1985:2020, SON = YEARS)
  file <- file.path(RESULTS, sprintf("%s_tas_%s_%s_EUR12.nc", TAG, season, period))
  dates <- read_dates(file)
  file_years <- as.integer(substr(dates, 1, 4))
  if (!identical(file_years, expected)) stop("Unexpected seasonal years in ", file)
  nc <- open_tas(file, dim(orog))
  if (nc$dim$time$len != length(dates)) stop("Time dimension mismatch in ", file)
  if (nc$var$tas$units != "K") stop("Expected tas in K: ", file)
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
  cat("Computed CERRA seasonal time series for", season, "\n")
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
cat("CERRA ZDL time series written to", ZDL_DIR, "\n")
