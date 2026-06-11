#' curlimpersonate: browser TLS/HTTP2 fingerprints for R HTTP
#'
#' @description
#' `curlimpersonate` makes R HTTP requests carry a real browser's TLS (JA3/JA4)
#' and HTTP/2 fingerprint by routing them through
#' [`libcurl-impersonate`](https://github.com/lexiforest/curl-impersonate), a
#' drop-in build of the libcurl C library with a patched TLS stack.
#'
#' @section Three different "curls" (read this first):
#' It matters which one a given request uses, because `curlimpersonate` only
#' affects some of them:
#'
#' * **The `curl` R package** (and `httr`, `httr2`, `crul`, and anything else
#'   built on it). This is the usual target. It wraps a copy of the libcurl
#'   *C library*.
#' * **R's built-in internet module**, used by [download.file()] with
#'   `method = "libcurl"`, [url()], and `install.packages()`. This links a
#'   *separate* libcurl from the one in the `curl` package.
#' * **The system `curl` command-line program**, used by [download.file()] with
#'   `method = "curl"`. A completely separate binary.
#'
#' Throughout the docs, **"the `curl` package"** means the R package; **"libcurl"**
#' means the underlying C library; **"system curl"** means the command-line tool.
#'
#' @section Two ways to get libcurl-impersonate under the `curl` package:
#' Which one applies depends on how *your* installed `curl` package links
#' libcurl (check with [impersonate_linkage()]):
#'
#' * **Preload (no rebuild)** — works when the `curl` package links libcurl
#'   *dynamically* (typical on Linux). Set a loader environment variable
#'   (`LD_PRELOAD` on Linux) *before R starts* so the existing `curl.so` picks
#'   up libcurl-impersonate. See [impersonate_env()].
#' * **Rebuild** — required when the `curl` package links libcurl *statically*
#'   (the CRAN macOS binary does this). [build_impersonate_curl()] compiles the
#'   `curl` package from source against libcurl-impersonate into a private
#'   library; [activate()] puts it first on the search path. Nothing in your
#'   main library is modified.
#'
#' Either way, **no `.Rprofile` is edited for you.** The functions report
#' exactly what to run or which variables to set; you decide where to put them
#' (interactively, in `.Rprofile`, in `.Renviron`, or in your shell).
#'
#' @section Choosing a profile and how headers behave:
#' Once libcurl-impersonate is in use it does nothing until you select a target
#' with the `CURL_IMPERSONATE` environment variable (via [impersonate_set()]).
#' `CURL_IMPERSONATE_HEADERS` controls whether the library *also* installs the
#' browser's default request headers and their ordering. See [impersonate_set()]
#' for how that interacts with headers you set yourself through `httr2`,
#' `httr`, or `curl`.
#'
#' @section download.file() and friends:
#' Because they use different libcurls (see above):
#'
#' * `download.file(method = "libcurl")`, `url()` — use R's internet module, a
#'   *separate* libcurl. The **rebuild** mechanism does **not** affect these.
#'   The **preload** mechanism *does* (it is process-wide), on platforms where
#'   that module links libcurl dynamically.
#' * `download.file(method = "curl")` — shells out to system curl; affected only
#'   if a curl-impersonate wrapper is first on `PATH`.
#' * `curl::curl_download()`, `httr`/`httr2` downloads — use the `curl` package,
#'   so both mechanisms affect them.
#'
#' Always confirm your specific call path with [impersonate_check()].
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom tools R_user_dir
#' @importFrom utils download.file install.packages untar unzip
NULL
