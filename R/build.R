# Rebuild the curl package against libcurl-impersonate ----------------------

# Does the built private curl.so actually link libcurl-impersonate? Returns
# TRUE/FALSE, or NA when linkage can't be introspected (e.g. Windows).
.verify_linkage <- function() {
  so <- .curl_shared_object()
  if (is.null(so)) {
    return(FALSE)
  }
  if (.detect_os() == "windows") {
    return(NA) # no easy linker introspection; trust the build
  }
  # Match the *library file name*, not just "impersonate" — the cache path
  # itself contains "curlimpersonate" and would give a false positive.
  any(grepl("libcurl-impersonate", .so_deps(so), ignore.case = TRUE))
}

#' Rebuild the 'curl' package against libcurl-impersonate
#'
#' Compiles the CRAN `curl` package from source, linking it against the
#' libcurl-impersonate found via [impersonate_home()], and installs it into a
#' private library (`<cache>/rlib`). Your system/user `curl` is left untouched.
#'
#' @param repos CRAN mirror to fetch the `curl` source from.
#' @param quiet Suppress messages.
#' @return The private library path (invisibly).
#' @export
build_impersonate_curl <- function(repos = "https://cloud.r-project.org", quiet = FALSE) {
  lib <- .find_impersonate_lib(.lib_dir())
  if (is.null(lib)) {
    stop(
      "No libcurl-impersonate found in ", .lib_dir(), ".\n",
      "Run download_impersonate(), or set CURLIMPERSONATE_HOME to an install ",
      "with lib/.",
      call. = FALSE
    )
  }
  .assert_supported_lib(.lib_dir())
  # Ensure macOS install names resolve (prebuilt dylibs carry a foreign path).
  if (isFALSE(.macos_fix_install_names(dirname(lib)))) {
    warning(
      "Could not rewrite install names in ", dirname(lib), " (not writable). ",
      "If the build fails to load, fix the dylib's install name or use a ",
      "writable CURLIMPERSONATE_HOME / the downloaded cache.",
      call. = FALSE
    )
  }
  linkname <- .link_name(lib)
  libdir <- dirname(lib)
  incdir <- .include_dir()
  rlib <- .rlib_dir()
  dir.create(rlib, recursive = TRUE, showWarnings = FALSE)

  # The curl package's configure honours CURL_CFLAGS/CURL_LIBS above everything
  # else (pkg-config, and the Darwin autobrew fallback). We use them directly so
  # the build links our libcurl-impersonate, with an rpath so it resolves at
  # runtime. (A pkg-config shim does NOT work on macOS: configure requires
  # libcurl >= 8.8.0 there and falls back to a static download otherwise.)
  curl_cflags <- sprintf("-I%s", incdir)
  curl_libs <- sprintf("-L%s -l%s -Wl,-rpath,%s", libdir, linkname, libdir)
  if (grepl("[[:space:]]", libdir) || grepl("[[:space:]]", incdir)) {
    warning("A lib/include path contains spaces; the curl build may mishandle ",
            "it. Consider a space-free CURLIMPERSONATE_HOME.", call. = FALSE)
  }

  if (!quiet) {
    message("CURL_LIBS=", curl_libs)
    message("CURL_CFLAGS=", curl_cflags)
    message("Building curl into: ", rlib)
  }

  old_cflags <- Sys.getenv("CURL_CFLAGS", unset = NA)
  old_libs <- Sys.getenv("CURL_LIBS", unset = NA)
  Sys.setenv(CURL_CFLAGS = curl_cflags, CURL_LIBS = curl_libs)
  on.exit(
    {
      if (is.na(old_cflags)) Sys.unsetenv("CURL_CFLAGS") else Sys.setenv(CURL_CFLAGS = old_cflags)
      if (is.na(old_libs)) Sys.unsetenv("CURL_LIBS") else Sys.setenv(CURL_LIBS = old_libs)
    },
    add = TRUE
  )

  utils::install.packages(
    "curl",
    lib = rlib,
    type = "source",
    repos = repos,
    quiet = quiet,
    INSTALL_opts = "--no-multiarch"
  )

  if (!dir.exists(file.path(rlib, "curl"))) {
    stop("Build failed: curl was not installed into ", rlib, call. = FALSE)
  }
  linked <- .verify_linkage()
  if (isFALSE(linked)) {
    warning(
      "Built curl does NOT link libcurl-impersonate (it likely fell back to a ",
      "stock static libcurl). Check the build log above.",
      call. = FALSE
    )
  } else if (!quiet && isTRUE(linked)) {
    message("Verified: rebuilt curl links libcurl-impersonate.")
  }
  if (!quiet) {
    message(
      "Done. Make it the active curl by running activate() before curl loads, ",
      "or set R_LIBS in .Renviron (see ?activate). Then pick a profile with ",
      "impersonate_set()."
    )
  }
  invisible(rlib)
}

#' Download and build in one step
#'
#' Convenience wrapper: [download_impersonate()] (unless a library is already
#' present or `CURLIMPERSONATE_HOME` is set) followed by
#' [build_impersonate_curl()].
#'
#' @param ... Passed to [download_impersonate()].
#' @param quiet Suppress messages.
#' @return The private library path (invisibly).
#' @export
install_impersonate <- function(..., quiet = FALSE) {
  have_lib <- !is.null(.find_impersonate_lib(.lib_dir()))
  if (!have_lib) {
    if (nzchar(Sys.getenv("CURLIMPERSONATE_HOME"))) {
      stop(
        "CURLIMPERSONATE_HOME is set but no libcurl-impersonate library was ",
        "found in ", .lib_dir(), ". Fix the path or unset it to download.",
        call. = FALSE
      )
    }
    download_impersonate(..., quiet = quiet)
  }
  build_impersonate_curl(quiet = quiet)
}
