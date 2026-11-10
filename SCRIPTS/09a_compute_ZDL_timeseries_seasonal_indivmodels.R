#!/usr/bin/env Rscript
# Annual seasonal ZDL by model and mountain region, 1981-2020.
# Run with /home/skotlarski/.conda/envs/zdl-r/bin/Rscript.

suppressPackageStartupMessages(library(ncdf4))

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
source(file.path(ROOT, "SCRIPTS", "09_zdl_timeseries_helpers.R"))
RESULTS <- file.path(ROOT, "RESULTS")
ZDL_DIR <- file.path(RESULTS, "ZDL")
SEASONS <- c("DJF", "MAM", "JJA", "SON")
YEARS <- 1981:2020
LAND_MIN <- 0.5

read_models <- function(path) {
  rows <- strsplit(trimws(readLines(path)), "[[:space:]]+")
  rows <- rows[lengths(rows) == 3 & startsWith(vapply(rows, `[`, "", 3), "/")]
  if (!length(rows)) stop("No models found in ", path)
  lapply(rows, function(r) list(model = r[1], inst = r[2]))
}

mask_nc <- nc_open(file.path(RESULTS, "EEA_mountain_masks_EUR12.nc"))
mask_names <- grep("^mask_", names(mask_nc$var), value = TRUE)
if (!length(mask_names)) stop("No region masks found")
masks <- setNames(lapply(mask_names, function(v) ncvar_get(mask_nc, v)), mask_names)
nc_close(mask_nc)
regions <- sub("^mask_", "", mask_names)
models <- read_models(file.path(RESULTS, "models_tas_mon.txt"))
rows <- setNames(lapply(regions, function(r) setNames(vector("list", length(SEASONS)), SEASONS)), regions)

for (m in models) {
  tag <- paste0(m$inst, "_", m$model)
  orog <- read_var(file.path(RESULTS, "OROG", paste0(tag, "_orog_EUR12.nc")), "orog")
  land <- read_var(file.path(RESULTS, "LSM", paste0(tag, "_sftlf_EUR12.nc")), "sftlf") / 100
  if (!identical(dim(orog), dim(land)) ||
      any(!vapply(masks, function(mask) identical(dim(mask), dim(orog)), logical(1)))) {
    stop("Grid dimension mismatch for ", tag)
  }
  base_ok <- lapply(masks, function(mask) {
    which(mask == 1 & is.finite(orog) & is.finite(land) & land > LAND_MIN)
  })

  for (season in SEASONS) {
    period <- if (season == "DJF") "1982-2019" else "1981-2020"
    file <- file.path(RESULTS, sprintf("%s_tas_%s_%s_EUR12.nc", tag, season, period))
    dates <- read_dates(file)
    file_years <- as.integer(substr(dates, 1, 4))
    expected <- if (season == "DJF") 1982:2019 else YEARS
    if (!identical(file_years, expected)) stop("Unexpected seasonal years in ", file)
    nc <- open_tas(file, dim(orog))
    if (nc$dim$time$len != length(dates)) stop("Time dimension mismatch in ", file)
    values <- matrix(NA_character_, nrow = length(regions), ncol = length(YEARS))

    record_step <- function(tas, year) {
      for (i in seq_along(regions)) {
        ok <- base_ok[[i]][is.finite(tas[base_ok[[i]]])]
        values[i, match(year, YEARS)] <<- format_zdl(fit_zdl(tas[ok], orog[ok]))
      }
    }

    for (i in seq_along(file_years)) record_step(read_tas_step(nc, i), file_years[i])
    nc_close(nc)

    for (i in seq_along(regions)) {
      vals <- values[i, ]
      vals[is.na(vals)] <- "NA"
      rows[[regions[i]]][[season]] <- c(rows[[regions[i]]][[season]],
                                        paste(c(tag, vals), collapse = "\t"))
    }
  }
  cat("Computed seasonal time series for", tag, "\n")
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
cat("ZDL time series written to", ZDL_DIR, "\n")
