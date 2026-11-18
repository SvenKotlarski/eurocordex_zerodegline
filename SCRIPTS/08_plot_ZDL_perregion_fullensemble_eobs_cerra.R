#!/usr/bin/env Rscript
# Overview figures of the zero-degree line (ZDL) per mountain region: one figure per region with four panels
# (one per season). Each model is a horizontal line at its ZDL. Model colours are fixed across all regions;
# variants of the same model family share a hue. E-OBS is black and CERRA is light grey; both have star markers.
# Extrapolated ZDLs (marked with * in the input tables) are drawn dashed, all others solid.
# Input: RESULTS/ZDL/<Region>_<SEASON>_ZDL_<PERIOD>.csv (written by 07a_compute_ZDL_seasonal_indivmodels.R)
#        RESULTS/ZDL_EOBS/<Region>_<SEASON>_ZDL_<PERIOD>.csv (written by 07b_compute_ZDL_seasonal_eobs.R)
#        RESULTS/ZDL_CERRA/<Region>_<SEASON>_ZDL_1991-2020.csv (written by 07c_compute_ZDL_seasonal_CERRA.R)
# Output: PLOTS/ZDL_OVERVIEW/ZDL_overview_<Region>_<PERIOD>.png
# Run with base R (no extra packages needed):
#   Rscript SCRIPTS/08_plot_ZDL_perregion_fullensemble_eobs_cerra.R

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
source(file.path(ROOT, "SCRIPTS", "08_zdl_overview_helpers.R"))

ZDL_DIR <- file.path(ROOT, "RESULTS", "ZDL")
EOBS_DIR <- file.path(ROOT, "RESULTS", "ZDL_EOBS")
CERRA_DIR <- file.path(ROOT, "RESULTS", "ZDL_CERRA")
PLOT_DIR <- file.path(ROOT, "PLOTS", "ZDL_OVERVIEW")
SEASONS <- c("DJF", "MAM", "JJA", "SON")
PERIODS <- c("1981-2020", "1991-2020")

dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

files <- list.files(ZDL_DIR, pattern = "_(DJF|MAM|JJA|SON)_ZDL_(1981|1991)-2020\\.csv$", full.names = TRUE)
if (!length(files)) stop("No model climatology tables found in ", ZDL_DIR)
regions <- sort(unique(sub("_(DJF|MAM|JJA|SON)_ZDL_(1981|1991)-2020\\.csv$", "", basename(files))))

zdl <- eobs <- cerra <- list()  # [[period]][[region]][[season]] = data.frame(model, zdl)
for (period in PERIODS) {
  for (region in regions) {
    for (season in SEASONS) {
      name <- sprintf("%s_%s_ZDL_%s.csv", region, season, period)
      model_file <- file.path(ZDL_DIR, name)
      eobs_file <- file.path(EOBS_DIR, name)
      if (!file.exists(model_file) || !file.exists(eobs_file)) {
        stop("Missing model or E-OBS table for ", region, " ", season, " ", period)
      }
      zdl[[period]][[region]][[season]] <- read_zdl(model_file)
      eobs[[period]][[region]][[season]] <- read_zdl(eobs_file)
      if (period == "1991-2020") {
        cerra_file <- file.path(CERRA_DIR, name)
        if (!file.exists(cerra_file)) {
          stop("Missing CERRA table for ", region, " ", season, " ", period)
        }
        cerra[[period]][[region]][[season]] <- read_zdl(cerra_file)
      }
    }
  }

}

all_models <- sort(unique(unlist(lapply(zdl, function(p) {
  lapply(p, function(r) lapply(r, function(d) d$model))
}))))

model_col <- model_colours(all_models)

plot_region <- function(region, period) {
  label <- gsub("_", " ", region)
  yl <- zdl_ylim(zdl[[period]][[region]], eobs[[period]][[region]], cerra[[period]][[region]])

  png(file.path(PLOT_DIR, sprintf("ZDL_overview_%s_%s.png", region, period)),
      width = 2400, height = 1350, res = 200, type = "cairo")
  layout(matrix(c(1, 2, 3, 4, 5, 5, 5, 5), nrow = 2, byrow = TRUE),
         widths = c(1.25, 1, 1, 1), heights = c(1, 0.6))
  par(oma = c(0, 0, 4.5, 0), las = 1, mgp = c(3.5, 1, 0))

  for (i in seq_along(SEASONS)) {
    s <- SEASONS[i]
    plot_zdl_season(s, zdl[[period]][[region]][[s]], eobs[[period]][[region]][[s]],
                    cerra[[period]][[region]][[s]], yl, model_col, i == 1)
  }

  plot_zdl_legend(all_models, model_col, period == "1991-2020")
  mtext(label, outer = TRUE, line = 2.2, cex = 1.2, font = 2)
  djf_period <- if (period == "1981-2020") "1982-2019" else "1991-2019"
  mtext(sprintf("Zero-degree line elevation, %s (DJF %s)", period, djf_period),
        outer = TRUE, line = 0.8, cex = 1, font = 1)
  dev.off()
}

for (period in PERIODS) {
  for (region in regions) plot_region(region, period)
}

cat("Done. Overview figures written to", PLOT_DIR, "\n")
