# Shared plotting and input helpers for ZDL climatology overviews.

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

# Each file: header "MODEL<TAB>ZDL", a "========" line, then data rows.
read_zdl <- function(path) {
  lines <- readLines(path)
  rows <- strsplit(lines[-(1:2)], "\t", fixed = TRUE)
  raw <- vapply(rows, `[`, "", 2)
  data.frame(model = vapply(rows, `[`, "", 1),
             zdl = suppressWarnings(as.numeric(sub("\\*$", "", raw))),
             extrap = endsWith(raw, "*"),
             stringsAsFactors = FALSE)
}

zdl_ylim <- function(model, eobs, cerra) {
  vals <- c(unlist(lapply(model, function(d) d$zdl)),
            unlist(lapply(eobs, function(d) d$zdl)),
            unlist(lapply(cerra, function(d) d$zdl)))
  vals <- vals[is.finite(vals)]
  yl <- if (length(vals) > 0) range(vals) else c(0, 1000)
  pad <- max(diff(yl) * 0.05, 50)
  yl + c(-pad, pad)
}

plot_zdl_season <- function(season, model, eobs, cerra, yl, model_col, first, shade_below_zero = FALSE) {
  par(mar = if (first) c(2, 6, 3, 0.5) else c(2, 0.5, 3, 0.5))
  plot(NA, xlim = c(-0.1, 1.08), xaxs = "i", ylim = yl, xaxt = "n", yaxt = if (first) "s" else "n",
       xlab = "", ylab = if (first) "ZDL (m)" else "", main = season)
  if (shade_below_zero) {
    usr <- par("usr")
    if (usr[3] < 0) {
      rect(usr[1], usr[3], usr[2], min(0, usr[4]), col = "grey95", border = NA)
      box()
    }
  }
  abline(h = axTicks(2), col = "grey75", lty = 2)
  if (!is.null(model)) {
    ok <- is.finite(model$zdl)
    if (any(ok)) {
      segments(0, model$zdl[ok], 1, model$zdl[ok], col = model_col[model$model[ok]],
               lty = ifelse(model$extrap[ok], 2, 1), lwd = 0.6)
    } else {
      text(0.5, mean(yl), "no ZDL (all missing)", col = "grey30")
    }
  }
  if (!is.null(eobs) && nrow(eobs) > 0 && is.finite(eobs$zdl[1])) {
    segments(0, eobs$zdl[1], 1, eobs$zdl[1], col = "black", lty = if (eobs$extrap[1]) 2 else 1, lwd = 2)
    points(-0.045, eobs$zdl[1], col = "black", pch = 8, cex = 0.7)
  }
  if (!is.null(cerra) && nrow(cerra) > 0 && is.finite(cerra$zdl[1])) {
    segments(0, cerra$zdl[1], 1, cerra$zdl[1], col = "grey60", lty = if (cerra$extrap[1]) 2 else 1, lwd = 2)
    points(-0.045, cerra$zdl[1], col = "grey60", pch = 8, cex = 0.7)
  }
}

plot_zdl_legend <- function(all_models, model_col, has_cerra) {
  par(mar = c(0, 0, 0, 0))
  plot.new()
  n_mod <- length(all_models)
  leg <- legend("top", legend = c(all_models, "E-OBS", if (has_cerra) "CERRA",
                                  "solid: ZDL within data range", "dashed: extrapolated (*)"),
                col = c(model_col[all_models], "black", if (has_cerra) "grey60", "black", "black"),
                lwd = c(rep(0.6, n_mod), 2, if (has_cerra) 2, 1, 1),
                lty = c(rep(1, n_mod), NA, if (has_cerra) NA, 1, 2),
                ncol = 3, bty = "n", cex = 1.1, title = "Model")
  # Draw shorter reference samples with the star to the left of the line.
  ref_idx <- n_mod + seq_len(if (has_cerra) 2 else 1)
  ref_col <- c("black", if (has_cerra) "grey60")
  xchar <- 1.1 * par("cex") * (grconvertX(par("cin")[1], "inches", "user") -
                                  grconvertX(0, "inches", "user"))
  sample_start <- leg$text$x[ref_idx] - 3 * xchar
  points(sample_start + 0.2 * xchar, leg$text$y[ref_idx], pch = 8, col = ref_col, cex = 0.7)
  segments(sample_start + 0.6 * xchar, leg$text$y[ref_idx],
           sample_start + 2 * xchar, leg$text$y[ref_idx], col = ref_col, lwd = 2)
}
