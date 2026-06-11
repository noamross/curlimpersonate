# Runtime impersonation profile control (pure env-var management) ------------

# A non-exhaustive list of impersonation targets commonly available in
# libcurl-impersonate builds. This is informational only: impersonate_set()
# does NOT validate against it, so newer/other targets your build supports will
# still work. The authoritative list is defined by your installed build (and
# the upstream project's documentation).
.known_profiles <- c(
  "chrome99", "chrome100", "chrome101", "chrome104", "chrome107", "chrome110",
  "chrome116", "chrome119", "chrome120", "chrome123", "chrome124", "chrome131",
  "chrome99_android", "edge99", "edge101",
  "safari15_3", "safari15_5", "safari17_0", "safari17_2_ios", "safari18_0",
  "firefox133", "firefox135"
)

#' List impersonation profiles
#'
#' @param source Where to read profiles from:
#'   * `"auto"` (default): profiles parsed from wrapper binaries in your install
#'     (if any), unioned with the bundled list.
#'   * `"installed"`: only profiles parsed from wrapper binaries under
#'     [impersonate_home()]`/bin` (e.g. `curl_chrome116`). May be empty if your
#'     download contained only the library.
#'   * `"bundled"`: only the static list shipped with this package.
#' @return A character vector of profile names.
#' @export
impersonate_profiles <- function(source = c("auto", "installed", "bundled")) {
  source <- match.arg(source)
  installed <- character()
  bindir <- file.path(impersonate_home(), "bin")
  if (dir.exists(bindir)) {
    wrappers <- list.files(bindir, pattern = "^curl[_-]")
    installed <- sub("^curl[_-]impersonate[_-]?", "", sub("^curl_", "", wrappers))
    installed <- installed[nzchar(installed)]
  }
  out <- switch(source,
    installed = installed,
    bundled = .known_profiles,
    auto = union(installed, .known_profiles)
  )
  sort(unique(out))
}

#' Set the active impersonation profile
#'
#' libcurl-impersonate reads the `CURL_IMPERSONATE` environment variable each
#' time a request handle is initialised, so this changes the TLS/HTTP2
#' fingerprint for all subsequent requests made through the `curl` package
#' (and `httr`/`httr2`) in this session. It takes effect only when
#' libcurl-impersonate is actually in use (via [activate()] or the preload
#' mechanism); on a stock `curl` package it does nothing.
#'
#' Profiles available in this package's bundled list:
#' `r paste(curlimpersonate::impersonate_profiles(source = "bundled"), collapse = ", ")`.
#' This list is informational and not exhaustive — any target your
#' libcurl-impersonate build supports will work even if it is not listed.
#'
#' @section Headers:
#' libcurl-impersonate can do two things: match the browser's **TLS/HTTP2
#' fingerprint**, and (optionally) send the browser's **default request headers**
#' in the browser's order. The `headers` argument maps to the
#' `CURL_IMPERSONATE_HEADERS` environment variable:
#'
#' * `headers = TRUE` (default): the library installs the browser's default
#'   headers (e.g. `User-Agent`, `Accept`, `Accept-Language`, `sec-ch-ua`, ...)
#'   in the correct order. This is usually what you want, since header set and
#'   order are themselves fingerprinted.
#' * `headers = FALSE`: only the TLS/HTTP2 fingerprint is impersonated; you are
#'   fully responsible for headers.
#'
#' **Interaction with headers you set yourself** (via `httr2::req_headers()`,
#' `httr::add_headers()`, or `curl::handle_setopt(.list = list(httpheader =))`):
#' all of these set libcurl's `CURLOPT_HTTPHEADER`, which is *replace*, not
#' merge. Headers you set generally **override** the impersonated defaults for
#' the fields you specify and can disturb header ordering, which may make the
#' request look less like the target browser. If you only need to add or change
#' a header (e.g. `Authorization`), expect that it may move to the end / replace
#' the browser default. When fingerprint fidelity matters, set as few headers as
#' possible yourself, and verify the result with [impersonate_check()]. (These
#' are the expected mechanics of libcurl-impersonate; confirm against your build.)
#'
#' @param profile A target string (see [impersonate_profiles()]), e.g.
#'   `"chrome131"`.
#' @param headers Whether libcurl-impersonate should also supply the browser's
#'   default headers and ordering (`CURL_IMPERSONATE_HEADERS`). See the Headers
#'   section.
#' @return `profile` invisibly.
#' @export
impersonate_set <- function(profile, headers = TRUE) {
  stopifnot(is.character(profile), length(profile) == 1L, nzchar(profile))
  Sys.setenv(CURL_IMPERSONATE = profile)
  Sys.setenv(CURL_IMPERSONATE_HEADERS = if (isTRUE(headers)) "yes" else "no")
  invisible(profile)
}

#' Turn impersonation off
#'
#' Unsets the impersonation environment variables. The (still
#' impersonate-capable) libcurl then behaves like ordinary libcurl.
#' @return `TRUE` invisibly.
#' @export
impersonate_clear <- function() {
  Sys.unsetenv(c("CURL_IMPERSONATE", "CURL_IMPERSONATE_HEADERS"))
  invisible(TRUE)
}

#' The currently selected impersonation profile
#' @return The profile string, or `NA` if impersonation is off.
#' @export
impersonate_profile <- function() {
  v <- Sys.getenv("CURL_IMPERSONATE", unset = "")
  if (nzchar(v)) v else NA_character_
}

#' Run code with a temporary impersonation profile
#'
#' Sets the profile, evaluates `code`, and restores the previous environment on
#' exit (whether or not `code` errors).
#'
#' @param profile Impersonation target (see [impersonate_set()]).
#' @param code Code to evaluate.
#' @param headers Passed to [impersonate_set()].
#' @return The value of `code`.
#' @export
with_impersonate <- function(profile, code, headers = TRUE) {
  old <- Sys.getenv("CURL_IMPERSONATE", unset = NA)
  old_h <- Sys.getenv("CURL_IMPERSONATE_HEADERS", unset = NA)
  impersonate_set(profile, headers = headers)
  on.exit({
    if (is.na(old)) Sys.unsetenv("CURL_IMPERSONATE") else Sys.setenv(CURL_IMPERSONATE = old)
    if (is.na(old_h)) Sys.unsetenv("CURL_IMPERSONATE_HEADERS") else Sys.setenv(CURL_IMPERSONATE_HEADERS = old_h)
  })
  force(code)
}
