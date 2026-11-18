#!/usr/bin/env Rscript
# CERRA zero-degree line per mountain region and season, from 1991-2020 mean tas.
# DJF uses 1991-2019, matching the CERRA climatology prepared by script 06b.
# Run with /home/skotlarski/.conda/envs/zdl-r/bin/Rscript.

suppressPackageStartupMessages(library(ncdf4))

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
RESULTS <- file.path(ROOT, "RESULTS")
PLOT_DIR <- file.path(ROOT, "PLOTS", "ZDL_CERRA")
ZDL_DIR <- file.path(RESULTS, "ZDL_CERRA")
MASK_FILE <- file.path(RESULTS, "EEA_mountain_masks_EUR12.nc")
OROG_FILE <- file.path(RESULTS, "OROG", "CERRA_orog_EUR12.nc")
LSM_FILE <- file.path(RESULTS, "LSM", "CERRA_sftlf_EUR12.nc")
TAG <- "CERRA"
SEASONS <- c("DJF", "MAM", "JJA", "SON")
PERIOD <- "1991-2020"
LAND_MIN <- 0.5

read_var <- function(file, var) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  ncvar_get(nc, var)
}

read_tas <- function(file) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  if (nc$var$tas$units != "K") stop("Expected tas in K: ", file)
  ncvar_get(nc, "tas") - 273.15
}

fit_zdl <- function(tas, orog) {
  n <- length(tas)
  if (n < 3) return(list(a = NA_real_, b = NA_real_, z0 = NA_real_,
                         n = n, r2 = NA_real_, extrap = FALSE))
  fit <- lm(tas ~ orog)
  a <- unname(coef(fit)[1])
  b <- unname(coef(fit)[2])
  z0 <- if (!is.na(b) && b < 0) -a / b else NA_real_
  extrap <- is.finite(z0) && (z0 < min(orog) || z0 > max(orog))
  list(a = a, b = b, z0 = z0, n = n, r2 = summary(fit)$r.squared, extrap = extrap)
}

format_zdl <- function(z0, extrap) {
  if (!is.finite(z0)) return("NA")
  paste0(sprintf("%.0f", z0), if (extrap) "*" else "")
}

mask_nc <- nc_open(MASK_FILE)
mask_names <- grep("^mask_", names(mask_nc$var), value = TRUE)
if (!length(mask_names)) stop("No region masks found in ", MASK_FILE)
masks <- setNames(lapply(mask_names, function(v) ncvar_get(mask_nc, v)), mask_names)
nc_close(mask_nc)

orog <- read_var(OROG_FILE, "orog")
land <- read_var(LSM_FILE, "sftlf") / 100
tas <- lapply(SEASONS, function(s) {
  years <- if (s == "DJF") "1991-2019" else PERIOD
  read_tas(file.path(RESULTS, sprintf("%s_tas_%s_mean_%s_EUR12.nc", TAG, s, years)))
})
if (!identical(dim(land), dim(orog)) ||
    any(!vapply(masks, function(x) identical(dim(x), dim(orog)), logical(1))) ||
    any(!vapply(tas, function(x) identical(dim(x), dim(orog)), logical(1)))) {
  stop("CERRA orography, land fraction, temperature and masks must have matching grid dimensions")
}

dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(ZDL_DIR, recursive = TRUE, showWarnings = FALSE)

for (rg in mask_names) {
  region <- sub("^mask_", "", rg)
  label <- gsub("_", " ", region)
  base_ok <- which(masks[[rg]] == 1 & is.finite(orog) & is.finite(land) & land > LAND_MIN)
  fits <- lapply(seq_along(SEASONS), function(i) {
    ok <- base_ok[is.finite(tas[[i]][base_ok])]
    fit_zdl(tas[[i]][ok], orog[ok])
  })

  for (i in seq_along(SEASONS)) {
    f <- fits[[i]]
    file <- file.path(ZDL_DIR, sprintf("%s_%s_ZDL_%s.csv", region, SEASONS[i], PERIOD))
    writeLines(c("MODEL\tZDL", "========", paste0(TAG, "\t", format_zdl(f$z0, f$extrap))), file)
  }
  if (all(vapply(fits, function(f) f$n < 3, logical(1)))) {
    message(sprintf("%s | %s: fewer than three usable cells in every season, figure skipped", TAG, label))
    next
  }

  xl <- range(unlist(lapply(tas, function(x) x[base_ok])), na.rm = TRUE)
  yl <- range(orog[base_ok], na.rm = TRUE)
  yy <- seq(yl[1], yl[2], length.out = 100)

  png(file.path(PLOT_DIR, paste0(TAG, "_", region, "_ZDL.png")),
      width = 1800, height = 1600, res = 200, type = "cairo")
  par(mfrow = c(2, 2), mar = c(4.2, 4.4, 3, 1), oma = c(0, 0, 2.2, 0))
  for (i in seq_along(SEASONS)) {
    f <- fits[[i]]
    ok <- base_ok[is.finite(tas[[i]][base_ok])]
    x <- tas[[i]][ok]
    z <- orog[ok]
    plot(NA, xlim = xl, ylim = yl, xlab = "Mean seasonal temperature (\u00b0C)",
         ylab = "Grid cell elevation (m)",
         main = sprintf("%s   n = %d, R2 = %.2f", SEASONS[i], f$n, f$r2))
    abline(v = 0, col = "grey40", lty = 3)
    if (f$n >= 3) {
      points(x, z, pch = 16, cex = 0.4, col = rgb(0, 0, 0, 0.3))
      lines(f$a + f$b * yy, yy, col = "red", lwd = 2)
    }
    if (is.finite(f$z0) && !f$extrap) {
      abline(h = f$z0, col = "blue", lty = 2, lwd = 2)
      text(xl[1], f$z0, labels = sprintf("ZDL = %.0f m", f$z0), adj = c(0, -0.5), col = "blue", font = 2)
    } else if (f$extrap) {
      text(mean(xl), mean(yl), labels = sprintf("ZDL = %.0f m* (extrapolated)", f$z0),
           col = "blue")
    } else {
      why <- if (f$n < 3) "no ZDL (fewer than three cells)" else "no ZDL (non-negative or undefined slope)"
      text(mean(xl), mean(yl), labels = why, col = "blue")
    }
  }
  mtext(sprintf("%s | %s (1991-2020; DJF 1991-2019)", TAG, label), outer = TRUE, cex = 1.1, font = 2)
  dev.off()

  cat(sprintf("%s | %s: %s\n", TAG, label,
              paste(sprintf("%s %s m", SEASONS, vapply(fits, function(f) format_zdl(f$z0, f$extrap), "")),
                    collapse = ", ")))
}

cat("Done. Figures written to", PLOT_DIR, "\n")
cat("ZDL tables written to", ZDL_DIR, "\n")
