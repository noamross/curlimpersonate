# Integration test: downloads libcurl-impersonate and rebuilds curl.
# Off by default (network + compiler + several minutes). The CI workflow sets
# CURLIMPERSONATE_TEST_INTEGRATION=true on macOS and Linux runners.

skip_if_not(
  identical(tolower(Sys.getenv("CURLIMPERSONATE_TEST_INTEGRATION")), "true"),
  "integration tests disabled (set CURLIMPERSONATE_TEST_INTEGRATION=true)"
)
skip_on_cran()

test_that("download + build produces a curl linked to libcurl-impersonate", {
  skip_on_os("windows")
  install_impersonate(quiet = TRUE)

  so <- file.path(curlimpersonate:::.rlib_dir(), "curl", "libs", "curl.so")
  expect_true(file.exists(so))

  link <- impersonate_linkage(so)
  expect_identical(link$linkage, "dynamic")
  expect_true(isTRUE(link$impersonate))
})
