# curlimpersonate quickstart
library(curlimpersonate)

# Which mechanism applies? Inspect how your `curl` package links libcurl.
impersonate_linkage()
#  "static"  -> rebuild (below). "dynamic" -> preload (further below).

## --- Rebuild path (e.g. macOS CRAN binary, statically linked) --------------
install_impersonate()        # download libcurl-impersonate + rebuild `curl`

# Make the rebuilt curl load first. Do this BEFORE anything loads curl:
activate()                   # prepends the private library to .libPaths()
# (or set R_LIBS in ~/.Renviron to cat(curlimpersonate:::.rlib_dir()),
#  or put `curlimpersonate::activate()` in .Rprofile)

library(httr2)
impersonate_set("chrome116")
impersonate_check()          # JA4 should be Chrome's, t13d1516h2_...

# Per-request profile:
with_impersonate("firefox133", {
  request("https://tls.peet.ws/api/all") |>
    req_perform() |>
    resp_body_json() |>
    (\(x) x$tls$ja4)()
})

impersonate_clear()          # impersonation off (curl still works)

## --- Preload path (e.g. Linux, dynamically linked) -------------------------
# No rebuild needed; print the loader vars to set BEFORE launching R:
download_impersonate()
impersonate_env("chrome116")
#> export LD_PRELOAD=.../libcurl-impersonate.so
#> export CURL_IMPERSONATE=chrome116
# Put those in your shell/launcher, restart R, then use curl/httr/httr2.
