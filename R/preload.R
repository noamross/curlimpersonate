# Inspection and the no-rebuild "preload" mechanism --------------------------

#' Path to the libcurl-impersonate shared library
#'
#' Returns the libcurl-impersonate library found under [impersonate_home()]
#' (either downloaded by [download_impersonate()] or supplied via
#' `CURLIMPERSONATE_HOME`).
#'
#' @return A file path, or `NULL` if none is present.
#' @export
impersonate_lib <- function() {
  .find_impersonate_lib(.lib_dir())
}

#' Inspect how the `curl` package links libcurl
#'
#' Examines the compiled object of the `curl` *package* that would currently be
#' loaded and reports whether it links libcurl **statically** or **dynamically**
#' — which determines whether you can use the preload mechanism
#' ([impersonate_env()]) or must rebuild ([build_impersonate_curl()]).
#'
#' @param so Path to a `curl.so`/`curl.dll` to inspect. Defaults to the `curl`
#'   package on the current search path.
#' @return An `impersonate_linkage` object: the inspected object, `linkage`
#'   (`"dynamic"`, `"static"`, or `NA` on Windows), the dynamic libcurl
#'   dependency if any, and whether it already points at libcurl-impersonate.
#' @export
impersonate_linkage <- function(so = .active_curl_so()) {
  os <- .detect_os()
  if (is.null(so)) {
    return(structure(
      list(object = NA_character_, linkage = NA_character_, libcurl = NA_character_, impersonate = NA, os = os),
      class = "impersonate_linkage"
    ))
  }
  deps <- .so_deps(so)
  libcurl_dep <- grep("libcurl", deps, value = TRUE, ignore.case = TRUE)
  has_dyn_libcurl <- length(libcurl_dep) > 0
  linkage <- if (os == "windows") NA_character_ else if (has_dyn_libcurl) "dynamic" else "static"
  structure(
    list(
      object = so,
      linkage = linkage,
      libcurl = if (has_dyn_libcurl) trimws(libcurl_dep[1]) else NA_character_,
      impersonate = any(grepl("libcurl-impersonate", deps, ignore.case = TRUE)),
      os = os
    ),
    class = "impersonate_linkage"
  )
}

#' @export
print.impersonate_linkage <- function(x, ...) {
  cat("<impersonate_linkage>\n")
  cat("  curl package object:", x$object, "\n")
  cat("  libcurl linkage    :", x$linkage, "\n")
  cat("  dynamic libcurl dep:", x$libcurl %||% NA, "\n")
  cat("  already impersonate:", if (isTRUE(x$impersonate)) "yes" else "no", "\n")
  if (isTRUE(x$impersonate)) {
    cat("  -> Already linked to libcurl-impersonate. Just set a profile with impersonate_set().\n")
  } else if (identical(x$linkage, "dynamic")) {
    cat("  -> Dynamically linked: you can use the preload mechanism, no rebuild. See impersonate_env().\n")
  } else if (identical(x$linkage, "static")) {
    cat("  -> Statically linked: preload cannot work; rebuild with build_impersonate_curl().\n")
  }
  invisible(x)
}

#' Environment variables for the preload (no-rebuild) mechanism
#'
#' When the `curl` package links libcurl **dynamically**, you can make the
#' *existing* `curl` package use libcurl-impersonate by preloading it — no
#' rebuild needed. These loader variables must be present **before R starts**,
#' because the dynamic linker reads them at process launch. Putting them in
#' `.Renviron` is generally **too late**; set them in your shell, a launcher
#' script, or a wrapper.
#'
#' @details
#' On macOS the CRAN `curl` package is statically linked, so preloading cannot
#' redirect it (it *can* affect [download.file()] with `method = "libcurl"`,
#' which uses a dynamically linked libcurl). [impersonate_env()] warns when it
#' detects this.
#'
#' @param profile Optional impersonation target to include as `CURL_IMPERSONATE`.
#'   Unlike the loader variables, `CURL_IMPERSONATE` can also be set at runtime
#'   with [impersonate_set()].
#' @param lib Path to the libcurl-impersonate library. Defaults to
#'   [impersonate_lib()].
#' @return A named character vector of environment variables, with class
#'   `impersonate_env` for pretty printing.
#' @export
impersonate_env <- function(profile = NULL, lib = impersonate_lib()) {
  if (is.null(lib)) {
    stop("No libcurl-impersonate found. Run download_impersonate() or set CURLIMPERSONATE_HOME.", call. = FALSE)
  }
  os <- .detect_os()
  vars <- character()
  if (os == "linux") {
    vars["LD_PRELOAD"] <- lib
  } else if (os == "macos") {
    vars["DYLD_INSERT_LIBRARIES"] <- lib
    vars["DYLD_FORCE_FLAT_NAMESPACE"] <- "1"
  }
  if (!is.null(profile)) {
    vars["CURL_IMPERSONATE"] <- profile
  }
  attr(vars, "os") <- os
  structure(vars, class = "impersonate_env")
}

#' @export
print.impersonate_env <- function(x, ...) {
  os <- attr(x, "os")
  cat("# Set these BEFORE launching R (shell / launcher, not .Renviron):\n")
  for (nm in names(x)) {
    cat(sprintf("export %s=%s\n", nm, shQuote(x[[nm]])))
  }
  link <- tryCatch(impersonate_linkage(), error = function(e) NULL)
  if (!is.null(link) && identical(link$linkage, "static")) {
    cat("\n# WARNING: your `curl` package is statically linked; preload will NOT\n")
    cat("# redirect it. Use build_impersonate_curl() instead.\n")
  }
  invisible(x)
}
