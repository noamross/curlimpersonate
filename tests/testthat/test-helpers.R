# Pure-logic unit tests (no network, no build).

test_that(".link_name strips lib prefix, version, and extension", {
  expect_equal(curlimpersonate:::.link_name("libcurl-impersonate-chrome.4.dylib"), "curl-impersonate-chrome")
  expect_equal(curlimpersonate:::.link_name("libcurl-impersonate.4.dylib"), "curl-impersonate")
  expect_equal(curlimpersonate:::.link_name("libcurl-impersonate-ff.so.4"), "curl-impersonate-ff")
})

test_that("os/arch patterns match release-asset naming", {
  expect_match("macos", curlimpersonate:::.os_pattern("macos"))
  expect_match("darwin", curlimpersonate:::.os_pattern("macos"))
  expect_match("aarch64", curlimpersonate:::.arch_pattern("arm64"))
  expect_match("amd64", curlimpersonate:::.arch_pattern("x86_64"))
})

test_that(".pick_asset chooses libcurl over the bare binary and gnu over musl", {
  assets <- list(
    list(name = "curl-impersonate-v1.0.0.x86_64-linux-gnu.tar.gz", browser_download_url = "bin"),
    list(name = "libcurl-impersonate-v1.0.0.x86_64-linux-musl.tar.gz", browser_download_url = "musl"),
    list(name = "libcurl-impersonate-v1.0.0.x86_64-linux-gnu.tar.gz", browser_download_url = "gnu"),
    list(name = "libcurl-impersonate-v1.0.0.arm64-macos.tar.gz", browser_download_url = "mac")
  )
  expect_equal(curlimpersonate:::.pick_asset(assets, "linux", "x86_64")$browser_download_url, "gnu")
  expect_equal(curlimpersonate:::.pick_asset(assets, "macos", "arm64")$browser_download_url, "mac")
  expect_error(curlimpersonate:::.pick_asset(assets, "windows", "x86_64"), "No libcurl-impersonate asset")
})

test_that("impersonate_profiles returns a non-empty character vector", {
  p <- impersonate_profiles(source = "bundled")
  expect_type(p, "character")
  expect_true(length(p) > 0)
  expect_true("chrome131" %in% p)
})

test_that("impersonate_set / clear / profile manage env vars", {
  withr::defer(impersonate_clear())
  impersonate_clear()
  expect_true(is.na(impersonate_profile()))
  impersonate_set("chrome116")
  expect_equal(impersonate_profile(), "chrome116")
  expect_equal(Sys.getenv("CURL_IMPERSONATE_HEADERS"), "yes")
  impersonate_set("firefox133", headers = FALSE)
  expect_equal(Sys.getenv("CURL_IMPERSONATE_HEADERS"), "no")
  impersonate_clear()
  expect_true(is.na(impersonate_profile()))
})

test_that("with_impersonate restores prior state on exit", {
  impersonate_clear()
  out <- with_impersonate("chrome131", impersonate_profile())
  expect_equal(out, "chrome131")
  expect_true(is.na(impersonate_profile())) # restored
})

test_that("impersonate_env emits the right loader var per OS", {
  fake <- tempfile(fileext = ".dylib")
  file.create(fake)
  e <- impersonate_env("chrome116", lib = fake)
  expect_s3_class(e, "impersonate_env")
  expect_equal(unname(e[["CURL_IMPERSONATE"]]), "chrome116")
  os <- curlimpersonate:::.detect_os()
  if (os == "linux") expect_true("LD_PRELOAD" %in% names(e))
  if (os == "macos") expect_true("DYLD_INSERT_LIBRARIES" %in% names(e))
})

test_that("impersonate_env errors without a library", {
  expect_error(impersonate_env(lib = NULL), "No libcurl-impersonate")
})

test_that("guard rejects an lwthiker-style two-library install", {
  d <- file.path(tempdir(), "cimp-guard-two")
  unlink(d, recursive = TRUE)
  dir.create(d)
  file.create(file.path(d, c("libcurl-impersonate-chrome.4.dylib", "libcurl-impersonate-ff.4.dylib")))
  expect_error(curlimpersonate:::.assert_supported_lib(d), "two-library|lwthiker|single-library")
})

test_that("guard accepts a single lexiforest-style library", {
  d <- file.path(tempdir(), "cimp-guard-one")
  unlink(d, recursive = TRUE)
  dir.create(d)
  file.create(file.path(d, "libcurl-impersonate.4.dylib"))
  expect_invisible(curlimpersonate:::.assert_supported_lib(d))
})
