# Consistent model-family colours for the ZDL overview and time-series plots.
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
