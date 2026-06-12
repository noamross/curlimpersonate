# Activate the private (rebuilt) curl library --------------------------------

.curl_loaded_from <- function() {
  if (!"curl" %in% loadedNamespaces()) {
    return(NA_character_)
  }
  p <- getNamespaceInfo("curl", "path")
  normalizePath(dirname(p), winslash = "/", mustWork = FALSE)
}

#' Put the rebuilt curl package first on the library search path
#'
#' Prepends the private library (where [build_impersonate_curl()] installed the
#' impersonate-linked `curl`) to [.libPaths()], so it loads ahead of the system
#' `curl`. All downstream users of the `curl` package (`curl` itself, `httr`,
#' `httr2`, ...) then use libcurl-impersonate.
#'
#' This only does the obvious thing — it edits `.libPaths()` for the current
#' session. It must run **before `curl` is loaded**; once `curl` is loaded its
#' compiled object cannot be swapped. So either call it at the very top of your
#' script before any package that uses `curl`, or arrange it at startup
#' yourself, e.g. in `.Rprofile`:
#'
#' ```r
#' if (requireNamespace("curlimpersonate", quietly = TRUE)) curlimpersonate::activate()
#' ```
#'
#' or, equivalently and without loading the package, prepend the library via
#' `R_LIBS` in `.Renviron` (run `cat(curlimpersonate:::.rlib_dir())` to get the
#' path):
#'
#' ```
#' R_LIBS=/path/to/curlimpersonate/rlib
#' ```
#'
#' @return The activated library path (invisibly).
#' @examples
#' \dontrun{
#'   # Call activate() before any library() that loads the curl package:
#'   activate()
#'   library(httr2)
#'   impersonate_set("chrome131")
#'   chk <- impersonate_check()  # JA4 should now match Chrome's fingerprint
#'   chk$ja4
#' }
#' @export
activate <- function() {
  rlib <- .rlib_dir()
  if (!dir.exists(file.path(rlib, "curl"))) {
    stop(
      "Impersonate 'curl' is not installed. Run ",
      "curlimpersonate::install_impersonate() (or build_impersonate_curl()) first.",
      call. = FALSE
    )
  }
  rlib_norm <- normalizePath(rlib, winslash = "/", mustWork = FALSE)
  loaded <- .curl_loaded_from()
  if (!is.na(loaded) && !identical(loaded, rlib_norm)) {
    warning(
      "The 'curl' namespace is already loaded from ", loaded, ". activate() ",
      "cannot swap an already-loaded package; do this before curl loads ",
      "(top of script, .Rprofile, or R_LIBS in .Renviron), then restart R.",
      call. = FALSE
    )
  }
  .libPaths(c(rlib, .libPaths()))
  invisible(rlib)
}

#' Remove the rebuilt curl package from the library search path
#'
#' Reverses [activate()] for the current session. Does not unload an
#' already-loaded `curl`; restart R for a clean revert.
#' @return `TRUE` invisibly.
#' @examples
#' \dontrun{
#'   activate()
#'   library(curl)
#'   # ... make impersonated requests ...
#'   deactivate()  # remove the private library; restart R for a fully clean state
#' }
#' @export
deactivate <- function() {
  rlib <- normalizePath(.rlib_dir(), winslash = "/", mustWork = FALSE)
  .libPaths(setdiff(normalizePath(.libPaths(), winslash = "/", mustWork = FALSE), rlib))
  invisible(TRUE)
}
