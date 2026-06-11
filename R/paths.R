# Locations and platform detection -------------------------------------------

# The managed cache: where we download binaries and build the private curl.
.managed_dir <- function() tools::R_user_dir("curlimpersonate", "data")

#' Where curlimpersonate looks for libcurl-impersonate
#'
#' Returns the prefix that holds `lib/` (and optionally `include/`) for
#' libcurl-impersonate. If the `CURLIMPERSONATE_HOME` environment variable is
#' set, it is used verbatim (point it at an existing install to skip
#' downloading). Otherwise the managed cache under
#' [tools::R_user_dir()] is used.
#'
#' @return A file path (character scalar).
#' @export
impersonate_home <- function() {
  env <- Sys.getenv("CURLIMPERSONATE_HOME", unset = "")
  if (nzchar(env)) {
    return(normalizePath(env, mustWork = FALSE))
  }
  .managed_dir()
}

.lib_dir <- function() file.path(impersonate_home(), "lib")
.inc_dir <- function() file.path(impersonate_home(), "include")

# The rebuilt curl package always lives in the managed cache, regardless of
# where the impersonate library itself comes from.
.rlib_dir <- function() file.path(.managed_dir(), "rlib")
.build_dir <- function() file.path(.managed_dir(), "build")

.detect_os <- function() {
  s <- tolower(Sys.info()[["sysname"]])
  if (s == "darwin") {
    "macos"
  } else if (s == "windows") {
    "windows"
  } else {
    s
  }
}

.detect_arch <- function() tolower(Sys.info()[["machine"]])

.os_pattern <- function(os) {
  switch(os,
    macos = "macos|darwin",
    linux = "linux",
    windows = "windows|win64|win32|win",
    os
  )
}

.arch_pattern <- function(arch) {
  arch <- tolower(arch)
  if (grepl("arm64|aarch64", arch)) {
    "arm64|aarch64"
  } else if (grepl("x86_64|amd64", arch)) {
    "x86_64|amd64"
  } else {
    arch
  }
}

# Find the impersonate shared library inside a directory.
.find_impersonate_lib <- function(dir = .lib_dir()) {
  if (!dir.exists(dir)) {
    return(NULL)
  }
  all <- list.files(dir, full.names = TRUE)
  hits <- grep(
    "libcurl-impersonate.*\\.(dylib|dll)$|libcurl-impersonate.*\\.so(\\.[0-9]+)*$",
    all,
    value = TRUE
  )
  if (!length(hits)) {
    return(NULL)
  }
  sort(hits)[1]
}

# Derive the linker name (e.g. "curl-impersonate-chrome") from a dylib path.
.link_name <- function(lib) {
  n <- basename(lib)
  n <- sub("^lib", "", n)
  n <- sub("\\.dylib$", "", n)
  n <- sub("\\.dll$", "", n)
  n <- sub("\\.so.*$", "", n)
  n <- sub("\\.[0-9]+$", "", n) # strip trailing version, e.g. -chrome.4 -> -chrome
  n
}

# Headers: prefer downloaded/vendored, then common system locations.
.include_dir <- function() {
  inc <- .inc_dir()
  if (file.exists(file.path(inc, "curl", "curl.h"))) {
    return(inc)
  }
  cand <- character()
  brew <- Sys.which("brew")
  if (nzchar(brew)) {
    pfx <- tryCatch(
      system2(brew, c("--prefix", "curl"), stdout = TRUE, stderr = FALSE),
      error = function(e) character()
    )
    if (length(pfx)) cand <- c(cand, file.path(pfx, "include"))
  }
  cand <- c(cand, "/opt/homebrew/include", "/usr/local/include", "/usr/include")
  for (d in cand) {
    if (file.exists(file.path(d, "curl", "curl.h"))) {
      return(d)
    }
  }
  stop(
    "No curl headers (curl/curl.h) found in ", inc, " or system locations.\n",
    "Install curl development headers, or download a libcurl-impersonate ",
    "build that bundles headers. See `vignette` / inst/BUILD-FROM-SOURCE.md.",
    call. = FALSE
  )
}

# Path to the rebuilt curl package's shared object, if present.
.curl_shared_object <- function() {
  base <- file.path(.rlib_dir(), "curl", "libs")
  if (!dir.exists(base)) {
    return(NULL)
  }
  cand <- list.files(base, pattern = "curl\\.(so|dll)$", full.names = TRUE, recursive = TRUE)
  if (length(cand)) cand[1] else NULL
}

# Prebuilt macOS dylibs often carry an absolute install name (LC_ID_DYLIB) from
# the machine they were built on (e.g. /Users/runner/work/...). curl.so would
# then record that non-existent path and fail to load. Rewrite each
# libcurl-impersonate dylib's id to its real path here and ad-hoc re-sign.
# Returns TRUE if all writable dylibs were fixed. macOS only; no-op elsewhere.
.macos_fix_install_names <- function(libdir = .lib_dir()) {
  if (.detect_os() != "macos" || !dir.exists(libdir)) {
    return(invisible(TRUE))
  }
  dylibs <- list.files(libdir, pattern = "libcurl-impersonate.*\\.dylib$", full.names = TRUE)
  ok <- TRUE
  for (f in dylibs) {
    abs <- normalizePath(f, mustWork = TRUE)
    if (file.access(f, mode = 2) != 0) {
      ok <- FALSE
      next
    }
    system2("install_name_tool", c("-id", abs, abs), stdout = FALSE, stderr = FALSE)
    # install_name_tool invalidates the (ad-hoc) signature on arm64; re-sign.
    suppressWarnings(system2("codesign", c("--force", "--sign", "-", abs), stdout = FALSE, stderr = FALSE))
  }
  invisible(ok)
}

# Path to the compiled object of whichever `curl` package would be loaded now
# (respecting the current .libPaths()). Does not load the package.
.active_curl_so <- function() {
  pkg <- tryCatch(find.package("curl"), error = function(e) NULL)
  if (is.null(pkg)) {
    return(NULL)
  }
  cand <- list.files(file.path(pkg, "libs"),
    pattern = "curl\\.(so|dll)$", full.names = TRUE, recursive = TRUE
  )
  if (length(cand)) cand[1] else NULL
}

# Linker dependencies of a shared object (otool -L / ldd output lines).
# NB: `otool -L` echoes the object's own path as the first line; we drop it so
# a cache path containing "curlimpersonate" isn't mistaken for a dependency.
.so_deps <- function(so) {
  if (is.null(so) || !file.exists(so)) {
    return(character())
  }
  os <- .detect_os()
  if (os == "macos") {
    out <- tryCatch(system2("otool", c("-L", so), stdout = TRUE, stderr = TRUE), error = function(e) character())
    if (length(out)) out <- out[-1]
    out
  } else if (os == "windows") {
    character()
  } else {
    tryCatch(system2("ldd", so, stdout = TRUE, stderr = TRUE), error = function(e) character())
  }
}
