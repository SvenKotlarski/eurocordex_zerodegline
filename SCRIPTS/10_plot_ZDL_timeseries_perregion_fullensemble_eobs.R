#!/usr/bin/env Rscript
# Seasonal ZDL time series for the model ensemble and E-OBS, one figure per region.
# Run with Rscript SCRIPTS/10_plot_ZDL_timeseries_perregion_fullensemble_eobs.R.

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
source(file.path(ROOT, "SCRIPTS", "08_10_model_colours.R"))
ZDL_DIR <- file.path(ROOT, "RESULTS", "ZDL")
EOBS_DIR <- file.path(ROOT, "RESULTS", "ZDL_EOBS")
PLOT_DIR <- file.path(ROOT, "PLOTS", "ZDL")
SEASONS <- c("DJF", "MAM", "JJA", "SON")
YEARS <- 1981:2020

read_series <- function(path) {
  lines <- readLines(path)
  header <- paste(c("MODEL", YEARS), collapse = "\t")
  if (length(lines) < 3 || lines[1] != header ||
      lines[2] != paste(rep("=", nchar(header)), collapse = "")) {
    stop("Invalid time-series header in ", path)
  }
  fields <- strsplit(lines[-(1:2)], "\t", fixed = TRUE)
  if (any(lengths(fields) != length(YEARS) + 1L)) stop("Invalid row length in ", path)
  models <- vapply(fields, `[`, "", 1)
  if (any(!nzchar(models)) || anyDuplicated(models)) stop("Invalid or duplicate model name in ", path)
  raw_values <- do.call(rbind, lapply(fields, function(row) row[-1]))
  values <- suppressWarnings(matrix(as.numeric(raw_values), nrow = length(models)))
  if (any(!is.finite(values) & raw_values != "NA")) stop("Invalid ZDL value in ", path)
  rownames(values) <- models
  values
}

files <- list.files(ZDL_DIR, pattern = "_(DJF|MAM|JJA|SON)_ZDL_timeseries\\.csv$", full.names = TRUE)
if (!length(files)) stop("No model time-series files found in ", ZDL_DIR)
regions <- sort(unique(sub("_(DJF|MAM|JJA|SON)_ZDL_timeseries\\.csv$", "", basename(files))))
zdl <- eobs <- setNames(vector("list", length(regions)), regions)
all_models <- NULL
for (region in regions) {
  for (season in SEASONS) {
    name <- sprintf("%s_%s_ZDL_timeseries.csv", region, season)
    model_file <- file.path(ZDL_DIR, name)
    eobs_file <- file.path(EOBS_DIR, name)
    if (!file.exists(model_file) || !file.exists(eobs_file)) {
      stop("Missing model or E-OBS time-series table for ", region, " ", season)
    }
    zdl[[region]][[season]] <- read_series(model_file)
    eobs[[region]][[season]] <- read_series(eobs_file)
    models <- sort(rownames(zdl[[region]][[season]]))
    if (is.null(all_models)) all_models <- models
    if (!identical(models, all_models)) stop("Inconsistent models in ", model_file)
    if (!identical(rownames(eobs[[region]][[season]]), "EOBS_v31.0e")) {
      stop("Expected one EOBS_v31.0e row in ", eobs_file)
    }
  }
}
model_col <- model_colours(all_models)
dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

for (region in regions) {
  vals <- c(unlist(zdl[[region]]), unlist(eobs[[region]]))
  vals <- vals[is.finite(vals)]
  yl <- if (length(vals)) range(vals) else c(0, 1000)
  pad <- max(diff(yl) * 0.05, 50)
  yl <- yl + c(-pad, pad)

  png(file.path(PLOT_DIR, sprintf("ZDL_timeseries_%s.png", region)),
      width = 3600, height = 1800, res = 200, type = "cairo")
  layout(matrix(c(1, 2, 3, 4, 5, 5, 5, 5), nrow = 2, byrow = TRUE), heights = c(1, 0.6))
  par(oma = c(0, 0, 2, 0), las = 1)
  for (i in seq_along(SEASONS)) {
    season <- SEASONS[i]
    par(mar = if (i == 1) c(4, 4.5, 3, 0.5) else c(4, 0.5, 3, 0.5))
    plot(NA, xlim = range(YEARS), ylim = yl, xaxt = "n", yaxt = if (i == 1) "s" else "n",
         xlab = "Year", ylab = if (i == 1) "ZDL (m)" else "", main = season)
    axis(1, at = c(1981, 1990, 2000, 2010, 2020))
    d <- zdl[[region]][[season]]
    for (model in all_models) {
      lines(YEARS, d[model, ], col = model_col[model], lwd = 1)
      points(YEARS, d[model, ], col = model_col[model], pch = 16, cex = 0.35)
    }
    e <- eobs[[region]][[season]][1, ]
    lines(YEARS, e, col = "black", lty = 2, lwd = 1.3)
    points(YEARS, e, col = "black", pch = 16, cex = 0.4)
    if (!any(is.finite(d)) && !any(is.finite(e))) {
      text(mean(range(YEARS)), mean(yl), "no ZDL (all missing)", col = "grey30")
    }
  }
  par(mar = c(0, 0, 0, 0))
  plot.new()
  legend("top", legend = c(all_models, "E-OBS"), col = c(model_col[all_models], "black"),
         lwd = 1, lty = c(rep(1, length(all_models)), 2), pch = 16, pt.cex = 0.5,
         ncol = 3, bty = "n", cex = 1.1, title = "Model")
  mtext(gsub("_", " ", region), outer = TRUE, cex = 1.2, font = 2)
  dev.off()
}
cat("Done. Time-series figures written to", PLOT_DIR, "\n")
