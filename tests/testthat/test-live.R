# Live request test (unit): hit a fingerprint reflector and confirm we get back
# the fingerprint the server saw. Runs against whatever `curl` is loaded — in a
# plain test run that is the stock package, so this verifies the request +
# parsing path of impersonate_check(), not impersonation itself (the
# integration tests cover the impersonated fingerprint). Skipped offline/CRAN.

skip_on_cran()

test_that("impersonate_check() returns the fingerprint the server sees", {
  skip_if_not_installed("curl")
  skip_if_offline()

  chk <- tryCatch(
    impersonate_check(),
    error = function(e) skip(paste("reflector unreachable:", conditionMessage(e)))
  )
  expect_s3_class(chk, "impersonate_check")
  expect_true(is.character(chk$ja3_hash) && nzchar(chk$ja3_hash))
  expect_true(is.character(chk$ja4) && nzchar(chk$ja4))
  expect_match(chk$ja4, "^t1[0-9]") # JA4: t<tls-version>...
})
