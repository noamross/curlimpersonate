# Status and verification ----------------------------------------------------

#' Report curlimpersonate's state
#'
#' @return An `impersonate_status` object (a list) with the cache location, the
#'   detected library, whether the private curl is installed and currently
#'   active, how the active `curl` package links libcurl, the SSL backend
#'   `curl` reports, and the active profile.
#' @export
impersonate_status <- function() {
  rlib <- .rlib_dir()
  loaded <- .curl_loaded_from()
  rlib_norm <- normalizePath(rlib, winslash = "/", mustWork = FALSE)
  ssl <- if (requireNamespace("curl", quietly = TRUE)) {
    tryCatch(curl::curl_version()$ssl_version, error = function(e) NA_character_)
  } else {
    NA_character_
  }
  link <- tryCatch(impersonate_linkage(), error = function(e) NULL)
  out <- list(
    home = impersonate_home(),
    library = .find_impersonate_lib(.lib_dir()),
    rlib = rlib,
    installed = dir.exists(file.path(rlib, "curl")),
    curl_loaded_from = loaded,
    active = !is.na(loaded) && identical(loaded, rlib_norm),
    linkage = if (is.null(link)) NA_character_ else link$linkage,
    impersonate_linked = if (is.null(link)) NA else isTRUE(link$impersonate),
    ssl_backend = ssl,
    profile = impersonate_profile()
  )
  structure(out, class = "impersonate_status")
}

#' @export
print.impersonate_status <- function(x, ...) {
  yn <- function(v) if (isTRUE(v)) "yes" else "no"
  cat("<curlimpersonate status>\n")
  cat("  cache home      :", x$home, "\n")
  cat("  impersonate lib :", x$library %||% "<none — run download_impersonate()>", "\n")
  cat("  private curl    :", yn(x$installed), "(", x$rlib, ")\n")
  cat("  active now      :", yn(x$active),
    if (!is.na(x$curl_loaded_from)) paste0("(curl loaded from ", x$curl_loaded_from, ")") else "", "\n")
  cat("  curl linkage    :", x$linkage %||% NA,
    if (isTRUE(x$impersonate_linked)) "(already libcurl-impersonate)" else "", "\n")
  cat("  ssl backend     :", x$ssl_backend %||% NA, "\n")
  cat("  profile         :", x$profile %||% "off", "\n")
  if (isTRUE(x$impersonate_linked)) {
    if (is.na(x$profile)) cat("  -> linked; pick a profile with impersonate_set()\n")
  } else if (!isTRUE(x$installed) && identical(x$linkage, "dynamic")) {
    cat("  -> dynamic linkage: use the preload mechanism (impersonate_env()), no rebuild needed\n")
  } else if (!isTRUE(x$installed)) {
    cat("  -> run install_impersonate() (static linkage needs a rebuild)\n")
  } else if (!isTRUE(x$active)) {
    cat("  -> built but not active: call activate() before curl loads (see ?activate)\n")
  }
  invisible(x)
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

#' Verify the live TLS/HTTP2 fingerprint
#'
#' Makes a request through `curl` to a fingerprint-reflecting endpoint and
#' returns the JA3/JA4 and HTTP/2 fingerprints the server observed. Compare
#' with impersonation on vs. off to confirm it is working.
#'
#' @param url A reflector returning JSON. Defaults to `https://tls.peet.ws/api/all`.
#' @return An `impersonate_check` object (a list of fingerprints).
#' @export
impersonate_check <- function(url = "https://tls.peet.ws/api/all") {
  if (!requireNamespace("curl", quietly = TRUE)) {
    stop("The 'curl' package is required.", call. = FALSE)
  }
  res <- curl::curl_fetch_memory(url)
  fp <- jsonlite::fromJSON(rawToChar(res$content))
  out <- list(
    profile = impersonate_profile(),
    ja3_hash = tryCatch(fp$tls$ja3_hash, error = function(e) NA),
    ja4 = tryCatch(fp$tls$ja4, error = function(e) NA),
    http2_akamai = tryCatch(fp$http2$akamai_fingerprint_hash, error = function(e) NA),
    user_agent = tryCatch(fp$user_agent, error = function(e) NA)
  )
  structure(out, class = "impersonate_check")
}

#' @export
print.impersonate_check <- function(x, ...) {
  cat("<impersonate_check>\n")
  cat("  profile      :", x$profile %||% "off", "\n")
  cat("  JA3 hash     :", x$ja3_hash %||% NA, "\n")
  cat("  JA4          :", x$ja4 %||% NA, "\n")
  cat("  HTTP/2 akamai:", x$http2_akamai %||% NA, "\n")
  invisible(x)
}
