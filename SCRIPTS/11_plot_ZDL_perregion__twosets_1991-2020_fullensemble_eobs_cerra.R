#!/usr/bin/env Rscript
# Two six-region overviews of 1991-2020 ZDL climatologies (DJF 1991-2019).
# Each region has four seasonal subpanels, using the same styles as script 08.
# Panels shade elevations below 0 m (darker grey) and elevations above the region's highest E-OBS cell (lightest grey).
# Run with: Rscript SCRIPTS/11_plot_ZDL_perregion__twosets_1991-2020_fullensemble_eobs_cerra.R

ROOT <- "/mnt/CORDEX_CMIP6_tmp/user_tmp/skotlarski/eurocordex_zerodegline"
source(file.path(ROOT, "SCRIPTS", "08_zdl_overview_helpers.R"))

RESULTS <- file.path(ROOT, "RESULTS")
PLOT_DIR <- file.path(ROOT, "PLOTS", "ZDL_OVERVIEW")
SEASONS <- c("DJF", "MAM", "JJA", "SON")
PERIOD <- "1991-2020"
first_set <- c("Alps", "Carpathians", "Iberian_mountains", "Pyrenees", "Scandes", "Balkans")

files <- list.files(file.path(RESULTS, "ZDL"), pattern = "_DJF_ZDL_1991-2020\\.csv$")
regions <- sort(sub("_DJF_ZDL_1991-2020\\.csv$", "", files))
if (!all(first_set %in% regions) || length(regions) != 12) {
  stop("Expected 12 regions including: ", paste(first_set, collapse = ", "))
}
region_sets <- list(first_set, setdiff(regions, first_set))

zdl <- eobs <- cerra <- list()
for (region in regions) {
  for (season in SEASONS) {
    name <- sprintf("%s_%s_ZDL_%s.csv", region, season, PERIOD)
    paths <- file.path(RESULTS, c("ZDL", "ZDL_EOBS", "ZDL_CERRA"), name)
    if (any(!file.exists(paths))) {
      stop("Missing climatology table(s): ", paste(paths[!file.exists(paths)], collapse = ", "))
    }
    zdl[[region]][[season]] <- read_zdl(paths[1])
    eobs[[region]][[season]] <- read_zdl(paths[2])
    cerra[[region]][[season]] <- read_zdl(paths[3])
  }
}

all_models <- sort(unique(unlist(lapply(zdl, function(r) lapply(r, function(d) d$model)))))
model_col <- model_colours(all_models)
dir.create(PLOT_DIR, recursive = TRUE, showWarnings = FALSE)

plot_set <- function(regions, number) {
  png(file.path(PLOT_DIR, sprintf("ZDL_overview_twosets_set%d_%s.png", number, PERIOD)),
      width = 3800, height = 3500, res = 200, type = "cairo")
  on.exit(dev.off())
  panels <- matrix(0, nrow = 7, ncol = 8)
  for (row in 1:3) {
    offset <- (row - 1) * 10
    panels[2 * row - 1, ] <- c(rep(offset + 1, 4), rep(offset + 2, 4))
    panels[2 * row, ] <- offset + 3:10
  }
  panels[7, ] <- 31
  layout(panels, widths = rep(c(1.25, 1, 1, 1), 2),
         heights = c(0.1, 1, 0.1, 1, 0.1, 1, 0.8))
  par(oma = c(0, 0, 3, 0), las = 1, mgp = c(3.5, 1, 0))

  for (row in 1:3) {
    row_regions <- regions[(2 * row - 1):(2 * row)]
    for (region in row_regions) {
      par(mar = c(0, 0, 0, 0))
      plot.new()
      text(0.5, 0.25, gsub("_", " ", region), cex = 1.5, font = 1)
    }
    for (region in row_regions) {
      yl <- zdl_ylim(zdl[[region]], eobs[[region]], cerra[[region]])
      for (i in seq_along(SEASONS)) {
        s <- SEASONS[i]
        plot_zdl_season(s, zdl[[region]][[s]], eobs[[region]][[s]],
                        cerra[[region]][[s]], yl, model_col, i == 1,
                        shade_below_zero = TRUE)
      }
    }
  }
  plot_zdl_legend(all_models, model_col, TRUE)
  mtext("Zero-degree line elevation, 1991-2020 (DJF 1991-2019)",
        outer = TRUE, line = 1, cex = 1.2)
}

for (i in seq_along(region_sets)) plot_set(region_sets[[i]], i)
cat("Done. Two six-region overview figures written to", PLOT_DIR, "\n")
