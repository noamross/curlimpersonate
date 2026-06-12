# Download prebuilt libcurl-impersonate into the managed cache ---------------

.github_release <- function(repo, version) {
  base <- sprintf("https://api.github.com/repos/%s/releases", repo)
  url <- if (identical(version, "latest")) {
    file.path(base, "latest")
  } else {
    file.path(base, "tags", version)
  }
  headers <- c("User-Agent" = "curlimpersonate-r", "Accept" = "application/vnd.github+json")
  tok <- Sys.getenv("GITHUB_PAT", unset = Sys.getenv("GITHUB_TOKEN", unset = ""))
  if (nzchar(tok)) headers <- c(headers, "Authorization" = paste("Bearer", tok))
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  utils::download.file(url, tmp, quiet = TRUE, headers = headers)
  jsonlite::fromJSON(tmp, simplifyVector = FALSE)
}

.pick_asset <- function(assets, os, arch) {
  names <- vapply(assets, function(a) a$name, character(1))
  keep <- which(
    grepl("libcurl-impersonate", names, ignore.case = TRUE) &
      grepl(.os_pattern(os), names, ignore.case = TRUE) &
      grepl(.arch_pattern(arch), names, ignore.case = TRUE)
  )
  if (!length(keep)) {
    stop(
      "No libcurl-impersonate asset matched os='", os, "' arch='", arch, "'.\n",
      "Available release assets:\n  ", paste(names, collapse = "\n  "), "\n",
      "Set CURLIMPERSONATE_HOME to a local install, or build from source ",
      "(see inst/BUILD-FROM-SOURCE.md).",
      call. = FALSE
    )
  }
  # Prefer glibc over musl when both are offered.
  if (length(keep) > 1) {
    nonmusl <- keep[!grepl("musl", names[keep], ignore.case = TRUE)]
    if (length(nonmusl)) keep <- nonmusl
  }
  assets[[keep[1]]]
}

.collect_artifacts <- function(extract_dir) {
  libdir <- file.path(.managed_dir(), "lib")
  incdir <- file.path(.managed_dir(), "include")
  dir.create(libdir, recursive = TRUE, showWarnings = FALSE)
  dir.create(incdir, recursive = TRUE, showWarnings = FALSE)

  all <- list.files(extract_dir, recursive = TRUE, full.names = TRUE)
  libs <- grep(
    "libcurl-impersonate.*\\.(dylib|dll)$|libcurl-impersonate.*\\.so(\\.[0-9]+)*$",
    all,
    value = TRUE
  )
  if (!length(libs)) {
    stop("Downloaded archive contained no libcurl-impersonate library.", call. = FALSE)
  }
  file.copy(libs, libdir, overwrite = TRUE)

  # Optional wrapper binaries (curl-impersonate-chrome, etc.) for comparison.
  bins <- grep("/curl-impersonate", all, value = TRUE)
  bins <- bins[file.access(bins, mode = 1) == 0]
  if (length(bins)) {
    bindir <- file.path(.managed_dir(), "bin")
    dir.create(bindir, recursive = TRUE, showWarnings = FALSE)
    file.copy(bins, bindir, overwrite = TRUE)
  }

  # Headers, if the archive bundles them.
  hdr <- grep("/curl/curl\\.h$", all, value = TRUE)
  if (length(hdr)) {
    incsrc <- dirname(dirname(hdr[1]))
    file.copy(list.files(incsrc, full.names = TRUE), incdir, recursive = TRUE)
  }
  # Make macOS install names point at the real files (see helper for why).
  .macos_fix_install_names(libdir)
  invisible(libdir)
}

#' Download a prebuilt libcurl-impersonate into the managed cache
#'
#' Fetches a prebuilt release archive for the current OS/architecture and
#' unpacks the shared library (and headers, if bundled) into
#' `tools::R_user_dir("curlimpersonate", "data")`. Skip this entirely by
#' setting `CURLIMPERSONATE_HOME` to an existing install.
#'
#' @param version Release tag (e.g. `"v1.0.0"`) or `"latest"`.
#' @param repo GitHub `owner/repo` publishing the prebuilt binaries. Defaults
#'   to the actively maintained `lexiforest/curl-impersonate` fork; override
#'   with the `curlimpersonate.repo` option or this argument.
#' @param os,arch Platform identifiers; auto-detected by default.
#' @param quiet Suppress progress messages.
#' @return The directory the library was written to (invisibly).
#' @examples
#' \dontrun{
#'   download_impersonate()                    # latest release for your OS/arch
#'   download_impersonate(version = "v0.8.0")  # pin a specific release tag
#'
#'   # Skip downloading by pointing at an existing install instead:
#'   # Sys.setenv(CURLIMPERSONATE_HOME = "/opt/curl-impersonate")
#' }
#' @export
download_impersonate <- function(version = "latest",
                                 repo = getOption("curlimpersonate.repo", "lexiforest/curl-impersonate"),
                                 os = .detect_os(),
                                 arch = .detect_arch(),
                                 quiet = FALSE) {
  if (nzchar(Sys.getenv("CURLIMPERSONATE_HOME"))) {
    warning(
      "CURLIMPERSONATE_HOME is set; downloads go to the managed cache and will ",
      "be ignored unless you unset it. Using ", Sys.getenv("CURLIMPERSONATE_HOME"),
      call. = FALSE
    )
  }
  if (!quiet) message("Querying ", repo, " release '", version, "' ...")
  rel <- .github_release(repo, version)
  asset <- .pick_asset(rel$assets, os, arch)
  if (!quiet) message("Downloading ", asset$name, " ...")

  dl <- file.path(tempdir(), asset$name)
  on.exit(unlink(dl), add = TRUE)
  utils::download.file(asset$browser_download_url, dl, quiet = quiet, mode = "wb")

  ex <- file.path(tempdir(), paste0("curlimp-extract-", as.integer(file.info(dl)$size)))
  unlink(ex, recursive = TRUE)
  dir.create(ex, recursive = TRUE, showWarnings = FALSE)
  if (grepl("\\.zip$", asset$name, ignore.case = TRUE)) {
    utils::unzip(dl, exdir = ex)
  } else {
    utils::untar(dl, exdir = ex)
  }

  out <- .collect_artifacts(ex)
  .assert_supported_lib(out)
  if (!quiet) {
    message("Installed libcurl-impersonate into ", out)
    message("Next: build_impersonate_curl()  (or install_impersonate() to do both)")
  }
  invisible(out)
}
