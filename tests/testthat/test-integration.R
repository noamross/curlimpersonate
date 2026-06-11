# Integration tests: download libcurl-impersonate and rebuild curl, then make
# real requests and confirm the server sees the impersonated fingerprint.
# Off by default (network + compiler + several minutes). The CI workflow sets
# CURLIMPERSONATE_TEST_INTEGRATION=true on macOS and Linux runners.

skip_if_not(
  identical(tolower(Sys.getenv("CURLIMPERSONATE_TEST_INTEGRATION")), "true"),
  "integration tests disabled (set CURLIMPERSONATE_TEST_INTEGRATION=true)"
)
skip_on_cran()
skip_on_os("windows")

test_that("download + build produces a curl linked to libcurl-impersonate", {
  install_impersonate(quiet = TRUE)

  so <- file.path(curlimpersonate:::.rlib_dir(), "curl", "libs", "curl.so")
  expect_true(file.exists(so))

  link <- impersonate_linkage(so)
  expect_identical(link$linkage, "dynamic")
  expect_true(isTRUE(link$impersonate))
})

# Fetch the JA4 the reflector sees, for the baseline and each profile, in ONE
# fresh R process that uses the rebuilt curl (libcurl-impersonate reads
# CURL_IMPERSONATE per request handle, so we can switch profiles in-process).
.fetch_ja4_table <- function(rlib, profiles, url = "https://tls.peet.ws/api/all") {
  script <- sprintf('
    suppressMessages(library(curl))
    args <- commandArgs(trailingOnly = TRUE)
    get <- function() tryCatch(
      jsonlite::fromJSON(rawToChar(curl_fetch_memory("%s")$content))$tls$ja4,
      error = function(e) ""
    )
    Sys.unsetenv("CURL_IMPERSONATE")
    cat(sprintf("%%s\\t%%s\\n", "(base)", get()))
    for (p in args) {
      Sys.setenv(CURL_IMPERSONATE = p, CURL_IMPERSONATE_HEADERS = "yes")
      cat(sprintf("%%s\\t%%s\\n", p, get()))
    }
  ', url)
  out <- suppressWarnings(system2(
    "Rscript", c("--vanilla", "-e", shQuote(script), profiles),
    env = paste0("R_LIBS=", rlib), stdout = TRUE, stderr = FALSE
  ))
  parts <- strsplit(out, "\t", fixed = TRUE)
  vals <- vapply(parts, function(x) if (length(x) == 2) x[2] else "", character(1))
  names(vals) <- vapply(parts, function(x) x[1], character(1))
  vals
}

test_that("requests show the impersonated fingerprint across all profiles", {
  skip_if_offline()
  rlib <- curlimpersonate:::.rlib_dir()
  skip_if_not(dir.exists(file.path(rlib, "curl")), "build curl first")

  profiles <- impersonate_profiles()
  expect_true(length(profiles) > 0)

  fp <- .fetch_ja4_table(rlib, profiles)
  base <- fp[["(base)"]]
  skip_if(is.na(base) || !nzchar(base), "reflector unreachable from subprocess")

  prof_fp <- fp[setdiff(names(fp), "(base)")]
  passed <- prof_fp[nzchar(prof_fp) & prof_fp != base]
  failed <- setdiff(names(prof_fp), names(passed))

  message(sprintf(
    "profiles: %d tested, %d changed the fingerprint%s",
    length(profiles), length(passed),
    if (length(failed)) paste0(" (unchanged/unsupported: ", paste(failed, collapse = ", "), ")") else ""
  ))

  # Every fingerprint we got back must be a well-formed JA4.
  got <- prof_fp[nzchar(prof_fp)]
  expect_true(all(grepl("^t1[0-9]d", got)),
    info = paste("malformed JA4(s):", paste(got[!grepl("^t1[0-9]d", got)], collapse = ", ")))

  # Anchors known to be supported by the lexiforest build must impersonate, and
  # different browser families must look different.
  expect_true("chrome116" %in% names(passed))
  expect_true("firefox133" %in% names(passed))
  expect_false(identical(passed[["chrome116"]], passed[["firefox133"]]))

  # Broad coverage: most bundled profiles should change the fingerprint.
  expect_gte(length(passed), max(3L, ceiling(length(profiles) / 2)))
})
