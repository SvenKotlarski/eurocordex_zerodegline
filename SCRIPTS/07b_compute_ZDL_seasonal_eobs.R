#!/usr/bin/env Rscript
# Zero-degree line (ZDL) from E-OBS per mountain region and season, same method as script 07a.
# Input: E-OBS multi-year seasonal mean tas (1981-2020, DJF 1982-2019) and E-OBS orography on EUR-12, from script 06.
# Cells are used where the region mask equals 1, tas and orography are finite (E-OBS has values over land only).
# Output goes to PLOTS/ZDL_EOBS and RESULTS/ZDL_EOBS, separate from the model results used by script 08.
# Run with the conda env that has ncdf4:
#   /home/skotlarski/.conda/envs/zdl-r/bin/Rscript SCRIPTS/07b_compute_ZDL_seasonal_eobs.R

suppressPackageStartupMessages(library(ncdf4))

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
RESULTS <- file.path(ROOT, "RESULTS")
PLOT_DIR <- file.path(ROOT, "PLOTS", "ZDL_EOBS")
ZDL_DIR <- file.path(RESULTS, "ZDL_EOBS")
MASK_FILE <- file.path(RESULTS, "EEA_mountain_masks_EUR12.nc")
OROG_FILE <- file.path(RESULTS, "EOBS_v31.0e_orog_EUR12.nc")
TAG <- "EOBS_v31.0e"
SEASONS <- c("DJF", "MAM", "JJA", "SON")
PERIOD <- "1981-2020"

dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

read_var <- function(file, var) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  ncvar_get(nc, var)
}

read_tas <- function(file) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  x <- ncvar_get(nc, "tas")
  if (nc$var$tas$units == "K") x <- x - 273.15
  x
}

mask_nc <- nc_open(MASK_FILE)
mask_names <- grep("^mask_", names(mask_nc$var), value = TRUE)
masks <- setNames(lapply(mask_names, function(v) ncvar_get(mask_nc, v)), mask_names)
nc_close(mask_nc)

# Fit tas = a + b * orog on the selected cells; ZDL = elevation where the fit gives 0 degC.
# ZDL is NA if b >= 0. If it lies outside the orography range of the cells it is extrapolated:
# the height is kept and flagged (extrap = TRUE), and written with a trailing "*".
fit_zdl <- function(tas, orog) {
  fit <- lm(tas ~ orog)
  a <- unname(coef(fit)[1])
  b <- unname(coef(fit)[2])
  z0 <- if (!is.na(b) && b < 0) -a / b else NA_real_
  extrap <- is.finite(z0) && (z0 < min(orog) || z0 > max(orog))
  list(a = a, b = b, z0 = z0, n = length(tas), r2 = summary(fit)$r.squared, extrap = extrap)
}

format_zdl <- function(z0, extrap) {
  if (!is.finite(z0)) return("NA")
  paste0(sprintf("%.0f", z0), if (extrap) "*" else "")
}

orog <- read_var(OROG_FILE, "orog")
tas <- lapply(SEASONS, function(s) {
  period <- if (s == "DJF") "1982-2019" else PERIOD
  x <- read_tas(file.path(RESULTS, sprintf("EOBS_v31.0e_tas_%s_mean_%s_EUR12.nc", s, period)))
  matrix(as.vector(x), nrow = nrow(orog), ncol = ncol(orog))
})
stopifnot(all(vapply(tas, function(x) all(dim(x) == dim(orog)), logical(1))))

zdl_rows <- list()
for (rg in mask_names) {
  region <- sub("^mask_", "", rg)
  label <- gsub("_", " ", region)
  base_ok <- which(masks[[rg]] == 1 & is.finite(orog))

  fits <- lapply(seq_along(SEASONS), function(i) {
    ok <- base_ok[is.finite(tas[[i]][base_ok])]
    fit_zdl(tas[[i]][ok], orog[ok])
  })
  if (all(vapply(fits, function(f) f$n < 3, logical(1)))) {
    message(sprintf("%s | %s: no usable cells, skipped", TAG, label))
    for (s in SEASONS) zdl_rows[[paste(region, s, sep = "|")]] <- c(zdl_rows[[paste(region, s, sep = "|")]], paste0(TAG, "\tNA"))
    next
  }

  xl <- range(unlist(lapply(seq_along(SEASONS), function(i) tas[[i]][base_ok])), na.rm = TRUE)
  yl <- range(orog[base_ok], na.rm = TRUE)
  # the y-axis covers the orography of the cells; extrapolated ZDLs may lie outside it and are shown as text
  for (i in seq_along(SEASONS)) {
    key <- paste(region, SEASONS[i], sep = "|")
    zdl_rows[[key]] <- c(zdl_rows[[key]], paste0(TAG, "\t", format_zdl(fits[[i]]$z0, fits[[i]]$extrap)))
  }
  yy <- seq(yl[1], yl[2], length.out = 100)

  png(file.path(PLOT_DIR, paste0(TAG, "_", region, "_ZDL.png")),
      width = 1800, height = 1600, res = 200, type = "cairo")
  par(mfrow = c(2, 2), mar = c(4.2, 4.4, 3, 1), oma = c(0, 0, 2.2, 0))
  for (i in seq_along(SEASONS)) {
    f <- fits[[i]]
    ok <- base_ok[is.finite(tas[[i]][base_ok])]
    x <- tas[[i]][ok]
    z <- orog[ok]
    plot(NA, xlim = xl, ylim = yl, xlab = "Mean seasonal temperature (\u00b0C; 1981-2020, DJF 1982-2019)",
         ylab = "Grid cell elevation (m)",
         main = sprintf("%s   n = %d, R2 = %.2f", SEASONS[i], f$n, f$r2))
    abline(v = 0, col = "grey40", lty = 3)
    if (f$n >= 3) {
      points(x, z, pch = 16, cex = 0.4, col = rgb(0, 0, 0, 0.3))
      lines(f$a + f$b * yy, yy, col = "red", lwd = 2)
    }
    if (is.finite(f$z0) && !f$extrap) {
      abline(h = f$z0, col = "blue", lty = 2, lwd = 2)
      text(xl[1], f$z0, labels = sprintf("ZDL = %.0f m", f$z0), pos = 3, col = "blue", font = 2)
    } else if (f$extrap) {
      text(mean(xl), mean(yl), labels = sprintf("ZDL = %.0f m* (extrapolated, outside data range)", f$z0),
           col = "blue")
    } else {
      text(mean(xl), mean(yl), labels = "no ZDL (slope >= 0)", col = "blue")
    }
  }
  mtext(sprintf("%s | %s", TAG, label), outer = TRUE, cex = 1.1, font = 2)
  dev.off()

  cat(sprintf("%s | %s: %s\n", TAG, label,
              paste(sprintf("%s %s m", SEASONS, vapply(fits, function(f) format_zdl(f$z0, f$extrap), "")),
                    collapse = ", ")))
}

dir.create(ZDL_DIR, recursive = TRUE, showWarnings = FALSE)
for (key in names(zdl_rows)) {
  parts <- strsplit(key, "|", fixed = TRUE)[[1]]
  writeLines(c("MODEL\tZDL", "========", zdl_rows[[key]]),
             file.path(ZDL_DIR, sprintf("%s_%s_ZDL.csv", parts[1], parts[2])))
}

cat("Done. Figures written to", PLOT_DIR, "\n")
cat("ZDL tables written to", ZDL_DIR, "\n")
