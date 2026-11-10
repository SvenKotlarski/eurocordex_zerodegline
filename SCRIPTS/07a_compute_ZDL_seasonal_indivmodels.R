#!/usr/bin/env Rscript
# Zero-degree line (ZDL) per model, mountain region and season.
# For each model, region and season: scatter of multi-year mean tas (1981-2020, degC) against orography,
# linear regression tas ~ orog, and the elevation where the fit gives 0 degC. One figure per model and region
# with the four seasons, written to PLOTS/ZDL.
# Run with the conda env that has ncdf4:
#   /home/skotlarski/.conda/envs/zdl-r/bin/Rscript SCRIPTS/07a_compute_ZDL_seasonal_indivmodels.R

suppressPackageStartupMessages(library(ncdf4))

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
RESULTS <- file.path(ROOT, "RESULTS")
OROG_DIR <- file.path(RESULTS, "OROG")
LSM_DIR <- file.path(RESULTS, "LSM")
PLOT_DIR <- file.path(ROOT, "PLOTS", "ZDL")
ZDL_DIR <- file.path(RESULTS, "ZDL")
MODELS_FILE <- file.path(RESULTS, "models_tas_mon.txt")
MASK_FILE <- file.path(RESULTS, "EEA_mountain_masks_EUR12.nc")
SEASONS <- c("DJF", "MAM", "JJA", "SON")
PERIOD <- "1981-2020"
LAND_MIN <- 0.5  # land area fraction (sftlf in % divided by 100)

dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

read_var <- function(file, var) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  ncvar_get(nc, var)
}

read_models <- function(path) {
  rows <- strsplit(trimws(readLines(path)), "[[:space:]]+")
  rows <- rows[lengths(rows) == 3 & startsWith(vapply(rows, `[`, "", 3), "/")]
  lapply(rows, function(r) list(model = r[1], inst = r[2]))
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
# ZDL is NA if b >= 0 or if it lies outside the orography range of the cells (extrapolation).
fit_zdl <- function(tas, orog) {
  fit <- lm(tas ~ orog)
  a <- unname(coef(fit)[1])
  b <- unname(coef(fit)[2])
  z0 <- if (!is.na(b) && b < 0) -a / b else NA_real_
  extrap <- !is.na(z0) && (z0 < min(orog) || z0 > max(orog))
  if (extrap) z0 <- NA_real_
  list(a = a, b = b, z0 = z0, n = length(tas), r2 = summary(fit)$r.squared, extrap = extrap)
}

# ZDL rows per region and season, key "region|season", written to RESULTS/ZDL after the loop
zdl_rows <- list()
record_zdl <- function(region, season, tag, z0) {
  val <- if (is.finite(z0)) sprintf("%.0f", z0) else "NA"
  key <- paste(region, season, sep = "|")
  zdl_rows[[key]] <<- c(zdl_rows[[key]], paste0(tag, "\t", val))
}

for (m in read_models(MODELS_FILE)) {
  tag <- paste0(m$inst, "_", m$model)
  orog <- read_var(file.path(OROG_DIR, paste0(tag, "_orog_EUR12.nc")), "orog")
  land <- read_var(file.path(LSM_DIR, paste0(tag, "_sftlf_EUR12.nc")), "sftlf") / 100
  tas <- lapply(SEASONS, function(s) {
    period <- if (s == "DJF") "1982-2019" else PERIOD
    x <- read_tas(file.path(RESULTS, sprintf("%s_tas_%s_mean_%s_EUR12.nc", tag, s, period)))
    matrix(as.vector(x), nrow = nrow(orog), ncol = ncol(orog))
  })
  stopifnot(all(vapply(tas, function(x) all(dim(x) == dim(orog)), logical(1))))

  for (rg in mask_names) {
    region <- sub("^mask_", "", rg)
    label <- gsub("_", " ", region)
    base_ok <- which(masks[[rg]] == 1 & is.finite(orog) & is.finite(land) & land > LAND_MIN)

    fits <- lapply(seq_along(SEASONS), function(i) {
      ok <- base_ok[is.finite(tas[[i]][base_ok])]
      fit_zdl(tas[[i]][ok], orog[ok])
    })
    if (all(vapply(fits, function(f) f$n < 3, logical(1)))) {
      message(sprintf("%s | %s: no usable cells, skipped", tag, label))
      for (s in SEASONS) record_zdl(region, s, tag, NA_real_)
      next
    }

    xl <- range(unlist(lapply(seq_along(SEASONS), function(i) tas[[i]][base_ok])), na.rm = TRUE)
    yl <- range(orog[base_ok], na.rm = TRUE)
    # ZDL (if reported) lies within this range, so the y-axis already covers it
    z0s <- vapply(fits, function(f) f$z0, numeric(1))
    for (i in seq_along(SEASONS)) record_zdl(region, SEASONS[i], tag, z0s[i])
    yy <- seq(yl[1], yl[2], length.out = 100)

    png(file.path(PLOT_DIR, paste0(tag, "_", region, "_ZDL.png")),
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
      if (is.finite(f$z0)) {
        abline(h = f$z0, col = "blue", lty = 2, lwd = 2)
        text(xl[1], f$z0, labels = sprintf("ZDL = %.0f m", f$z0), pos = 3, col = "blue", font = 2)
      } else {
        why <- if (f$extrap) "ZDL outside data range (missing)" else "no ZDL (slope >= 0)"
        text(mean(xl), mean(yl), labels = why, col = "blue")
      }
    }
    mtext(sprintf("%s | %s", tag, label), outer = TRUE, cex = 1.1, font = 2)
    dev.off()

    cat(sprintf("%s | %s: %s\n", tag, label,
                paste(sprintf("%s %s m", SEASONS, ifelse(is.finite(z0s), round(z0s), "NA")), collapse = ", ")))
  }
}

dir.create(ZDL_DIR, recursive = TRUE, showWarnings = FALSE)
for (key in names(zdl_rows)) {
  parts <- strsplit(key, "|", fixed = TRUE)[[1]]
  writeLines(c("MODEL\tZDL", "========", zdl_rows[[key]]),
             file.path(ZDL_DIR, sprintf("%s_%s_ZDL.csv", parts[1], parts[2])))
}

cat("Done. Figures written to", PLOT_DIR, "\n")
cat("ZDL tables written to", ZDL_DIR, "\n")
