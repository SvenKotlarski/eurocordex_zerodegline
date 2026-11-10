#!/usr/bin/env Rscript
# Overview figures of the zero-degree line (ZDL) per mountain region: one figure per region with four panels
# (one per season). Each model is a horizontal line at its ZDL. Model colours are fixed across all regions;
# variants of the same model family share a hue. The E-OBS ZDL is drawn as a black line where available.
# Input: RESULTS/ZDL/<Region>_<SEASON>_ZDL.csv (written by 07a_compute_ZDL_seasonal_indivmodels.R)
#        RESULTS/ZDL_EOBS/<Region>_<SEASON>_ZDL.csv (written by 07b_compute_ZDL_seasonal_eobs.R)
# Output: PLOTS/ZDL/ZDL_overview_<Region>.png
# Run with base R (no extra packages needed):
#   Rscript SCRIPTS/08_plot_ZDL_perregion_fullensemble_eobs.R

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
ZDL_DIR <- file.path(ROOT, "RESULTS", "ZDL")
EOBS_DIR <- file.path(ROOT, "RESULTS", "ZDL_EOBS")
PLOT_DIR <- file.path(ROOT, "PLOTS", "ZDL")
SEASONS <- c("DJF", "MAM", "JJA", "SON")

dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

files <- list.files(ZDL_DIR, pattern = "_(DJF|MAM|JJA|SON)_ZDL\\.csv$", full.names = TRUE)
stopifnot(length(files) > 0)

# Each file: header "MODEL<TAB>ZDL", a "========" line, then data rows.
read_zdl <- function(path) {
  lines <- readLines(path)
  rows <- strsplit(lines[-(1:2)], "\t", fixed = TRUE)
  data.frame(model = vapply(rows, `[`, "", 1),
             zdl = suppressWarnings(as.numeric(vapply(rows, `[`, "", 2))),
             stringsAsFactors = FALSE)
}

zdl <- list()  # zdl[[region]][[season]] = data.frame(model, zdl)
for (f in files) {
  base <- sub("_ZDL\\.csv$", "", basename(f))
  season <- sub(".*_", "", base)
  region <- sub("_(DJF|MAM|JJA|SON)$", "", base)
  zdl[[region]][[season]] <- read_zdl(f)
}
regions <- sort(names(zdl))

eobs <- list()  # eobs[[region]][[season]] = E-OBS ZDL (m), NA if missing
for (f in list.files(EOBS_DIR, pattern = "_(DJF|MAM|JJA|SON)_ZDL\\.csv$", full.names = TRUE)) {
  base <- sub("_ZDL\\.csv$", "", basename(f))
  eobs[[sub("_(DJF|MAM|JJA|SON)$", "", base)]][[sub(".*_", "", base)]] <- read_zdl(f)$zdl
}

all_models <- sort(unique(unlist(lapply(zdl, function(r) lapply(r, function(d) d$model)))))

# Model family: variants of the same model share a hue, members differ in lightness.
family_of <- function(model) {
  if (grepl("REMO", model)) return("REMO")
  if (grepl("WRF451Q", model)) return("WRF451Q")
  if (grepl("ICON-CLM", model)) return("ICON-CLM")
  if (grepl("CCLM6", model)) return("CCLM6")
  if (grepl("ALADIN|ALARO", model)) return("ALADIN")
  model
}

fam <- vapply(all_models, family_of, "")
fam_levels <- sort(unique(fam))
fam_hue <- setNames(seq(0, 360, length.out = length(fam_levels) + 1)[seq_along(fam_levels)], fam_levels)

model_col <- character(length(all_models))
names(model_col) <- all_models
for (f_name in fam_levels) {
  members <- all_models[fam == f_name]
  n <- length(members)
  lightness <- if (n == 1) 55 else seq(35, 80, length.out = n)
  model_col[members] <- hcl(h = fam_hue[[f_name]], c = 70, l = lightness)
}

for (region in regions) {
  label <- gsub("_", " ", region)
  vals <- c(unlist(lapply(zdl[[region]], function(d) d$zdl)), unlist(eobs[[region]]))
  vals <- vals[is.finite(vals)]
  yl <- if (length(vals) > 0) range(vals) else c(0, 1000)
  pad <- max(diff(yl) * 0.05, 50)
  yl <- yl + c(-pad, pad)

  png(file.path(PLOT_DIR, sprintf("ZDL_overview_%s.png", region)),
      width = 2400, height = 1350, res = 200, type = "cairo")
  layout(matrix(c(1, 2, 3, 4, 5, 5, 5, 5), nrow = 2, byrow = TRUE), heights = c(1, 0.6))
  par(oma = c(0, 0, 2, 0), las = 1)

  for (i in seq_along(SEASONS)) {
    s <- SEASONS[i]
    # common y-axis: labels on the first panel only, same range in all panels
    par(mar = if (i == 1) c(2, 4.5, 3, 0.5) else c(2, 0.5, 3, 0.5))
    d <- zdl[[region]][[s]]
    plot(NA, xlim = c(0, 1), ylim = yl, xaxt = "n", yaxt = if (i == 1) "s" else "n",
         xlab = "", ylab = if (i == 1) "ZDL (m)" else "", main = s)
    if (!is.null(d)) {
      ok <- is.finite(d$zdl)
      if (any(ok)) {
        segments(0, d$zdl[ok], 1, d$zdl[ok], col = model_col[d$model[ok]], lwd = 1)
      } else {
        text(0.5, mean(yl), "no ZDL (all missing)", col = "grey30")
      }
    }
    e <- eobs[[region]][[s]]
    if (!is.null(e) && is.finite(e)) segments(0, e, 1, e, col = "black", lty = 2, lwd = 1)
  }

  par(mar = c(0, 0, 0, 0))
  plot.new()
  legend("top", legend = c(all_models, "E-OBS"), col = c(model_col[all_models], "black"),
         lwd = 1, lty = c(rep(1, length(all_models)), 2),
         ncol = 3, bty = "n", cex = 1.1, title = "Model")
  mtext(label, outer = TRUE, cex = 1.2, font = 2)
  dev.off()
}

cat("Done. Overview figures written to", PLOT_DIR, "\n")
