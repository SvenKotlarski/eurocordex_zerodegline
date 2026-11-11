#!/usr/bin/env Rscript
# Seasonal ZDL time series for the model ensemble and E-OBS, one figure per region.
# Run with Rscript SCRIPTS/10_plot_ZDL_timeseries_perregion_fullensemble_eobs.R.

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
# Consistent model-family colours: models of the same family share a hue, variants get different lightness.
model_colours <- function(models) {
  family_of <- function(model) {
    if (grepl("REMO", model)) return("REMO")
    if (grepl("WRF451Q", model)) return("WRF451Q")
    if (grepl("ICON-CLM", model)) return("ICON-CLM")
    if (grepl("CCLM6", model)) return("CCLM6")
    if (grepl("ALADIN|ALARO", model)) return("ALADIN")
    model
  }

  models <- sort(unique(models))
  fam <- vapply(models, family_of, "")
  fam_levels <- sort(unique(fam))
  fam_hue <- setNames(seq(0, 360, length.out = length(fam_levels) + 1)[seq_along(fam_levels)], fam_levels)
  colours <- setNames(character(length(models)), models)
  for (f_name in fam_levels) {
    members <- models[fam == f_name]
    n <- length(members)
    lightness <- if (n == 1) 55 else seq(35, 80, length.out = n)
    colours[members] <- hcl(h = fam_hue[[f_name]], c = 70, l = lightness)
  }
  colours
}

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
  # a trailing "*" marks an extrapolated ZDL; the height is used as is
  extrap <- matrix(endsWith(raw_values, "*"), nrow = length(models),
                   dimnames = list(models, YEARS))
  raw_values <- sub("\\*$", "", raw_values)
  values <- suppressWarnings(matrix(as.numeric(raw_values), nrow = length(models)))
  if (any(!is.finite(values) & raw_values != "NA")) stop("Invalid ZDL value in ", path)
  rownames(values) <- models
  colnames(values) <- YEARS
  list(values = values, extrap = extrap)
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
    models <- sort(rownames(zdl[[region]][[season]]$values))
    if (is.null(all_models)) all_models <- models
    if (!identical(models, all_models)) stop("Inconsistent models in ", model_file)
    if (!identical(rownames(eobs[[region]][[season]]$values), "EOBS_v31.0e")) {
      stop("Expected one EOBS_v31.0e row in ", eobs_file)
    }
  }
}
model_col <- model_colours(all_models)
dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

# Consecutive years are joined by a solid line. Each year is a dot, or an x when it is extrapolated (*).
draw_series <- function(x, y, extrap, col, lwd = 1) {
  for (j in seq_len(length(x) - 1)) {
    if (is.finite(y[j]) && is.finite(y[j + 1])) {
      segments(x[j], y[j], x[j + 1], y[j + 1], col = col, lwd = lwd, lty = 1)
    }
  }
  ok <- is.finite(y)
  points(x[ok & !extrap], y[ok & !extrap], col = col, pch = 16, cex = 0.35)
  points(x[ok & extrap], y[ok & extrap], col = col, pch = 4, cex = 0.6, lwd = 1.2)
}

for (region in regions) {
  vals <- c(unlist(lapply(zdl[[region]], `[[`, "values")), unlist(lapply(eobs[[region]], `[[`, "values")))
  vals <- vals[is.finite(vals)]
  yl <- if (length(vals)) range(vals) else c(0, 1000)
  pad <- max(diff(yl) * 0.05, 50)
  yl <- yl + c(-pad, pad)

  png(file.path(PLOT_DIR, sprintf("ZDL_timeseries_%s.png", region)),
      width = 3600, height = 1800, res = 200, type = "cairo")
  layout(matrix(c(1, 2, 3, 4, 5, 5, 5, 5), nrow = 2, byrow = TRUE), heights = c(1, 0.6))
  par(oma = c(0, 0, 3, 0), las = 1)
  for (i in seq_along(SEASONS)) {
    season <- SEASONS[i]
    par(mar = if (i == 1) c(4, 4.5, 3, 0.5) else c(4, 0.5, 3, 0.5))
    plot(NA, xlim = range(YEARS), ylim = yl, xaxt = "n", yaxt = if (i == 1) "s" else "n",
         xlab = "Year", ylab = if (i == 1) "ZDL (m)" else "", main = season)
    axis(1, at = c(1981, 1990, 2000, 2010, 2020))
    d <- zdl[[region]][[season]]$values
    dx <- zdl[[region]][[season]]$extrap
    for (model in all_models) {
      draw_series(YEARS, d[model, ], dx[model, ], model_col[model])
    }
    e <- eobs[[region]][[season]]$values[1, ]
    draw_series(YEARS, e, eobs[[region]][[season]]$extrap[1, ], "black", lwd = 1.3)
    if (!any(is.finite(d)) && !any(is.finite(e))) {
      text(mean(range(YEARS)), mean(yl), "no ZDL (all missing)", col = "grey30")
    }
  }
  par(mar = c(0, 0, 0, 0))
  plot.new()
  n_mod <- length(all_models)
  legend("top",
         legend = c(all_models, "E-OBS", "x: extrapolated (*) year"),
         col = c(model_col[all_models], "black", "black"),
         lwd = c(rep(1, n_mod), 1.3, 1), lty = c(rep(1, n_mod), 1, 0),
         pch = c(rep(16, n_mod), 16, 4), pt.cex = c(rep(0.5, n_mod), 0.4, 0.6),
         ncol = 3, bty = "n", cex = 1.1, title = "Model")
  mtext(gsub("_", " ", region), outer = TRUE, line = 1.6, cex = 1.2, font = 2)
  mtext("Zero-degree line elevation, 1981-2020", outer = TRUE, line = 0.4, cex = 1, font = 1)
  dev.off()
}
cat("Done. Time-series figures written to", PLOT_DIR, "\n")
