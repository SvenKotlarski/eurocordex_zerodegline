# Shared input and regression helpers for scripts 09a and 09b.

read_var <- function(file, var) {
  nc <- nc_open(file)
  on.exit(nc_close(nc))
  ncvar_get(nc, var)
}

# CDO interprets the NetCDF calendar, including non-Gregorian calendars.
read_dates <- function(file) {
  dates <- system2("cdo", c("-s", "showdate", shQuote(file)), stdout = TRUE)
  if (!is.null(attr(dates, "status"))) stop("Cannot read time axis: ", file)
  dates <- unlist(strsplit(trimws(paste(dates, collapse = " ")), "[[:space:]]+"))
  if (!length(dates) || any(!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dates))) {
    stop("Invalid time axis: ", file)
  }
  dates
}

open_tas <- function(file, grid_dim) {
  nc <- nc_open(file)
  dims <- nc$var$tas$dim
  if (length(dims) != 3 || !identical(vapply(dims, function(d) d$name, ""), c("rlon", "rlat", "time")) ||
      !identical(vapply(dims[1:2], function(d) d$len, integer(1)), as.integer(grid_dim))) {
    nc_close(nc)
    stop("Unexpected tas dimensions in ", file)
  }
  nc
}

read_tas_step <- function(nc, step) {
  x <- ncvar_get(nc, "tas", start = c(1, 1, step), count = c(-1, -1, 1))
  if (nc$var$tas$units == "K") x <- x - 273.15
  x
}

# ZDL is NA if b >= 0 or fewer than 3 values. Extrapolated ZDLs (outside the orography range of the cells)
# keep their height and are flagged with extrap = TRUE; they are written with a trailing "*".
fit_zdl <- function(tas, orog) {
  if (length(tas) < 3) return(list(z0 = NA_real_, extrap = FALSE))
  fit <- lm(tas ~ orog)
  a <- unname(coef(fit)[1])
  b <- unname(coef(fit)[2])
  z0 <- if (!is.na(b) && b < 0) -a / b else NA_real_
  extrap <- is.finite(z0) && (z0 < min(orog) || z0 > max(orog))
  list(z0 = z0, extrap = extrap)
}

format_zdl <- function(fit) {
  if (!is.finite(fit$z0)) return("NA")
  paste0(sprintf("%.0f", fit$z0), if (fit$extrap) "*" else "")
}
