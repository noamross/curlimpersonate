# curlimpersonate

Make R HTTP requests carry a real browser's TLS (JA3/JA4) and HTTP/2
fingerprint, using [`libcurl-impersonate`](https://github.com/lexiforest/curl-impersonate)
as the libcurl behind R's HTTP stack.

## Three different "curls"

It matters which one your request uses, because curlimpersonate only affects
some of them. Throughout, **"the `curl` package"** = the R package; **"libcurl"**
= the underlying C library; **"system curl"** = the command-line program.

| Path | Which libcurl | Affected by curlimpersonate? |
|------|---------------|------------------------------|
| `curl` package, `httr`, `httr2`, `crul`, `curl::curl_download()` | the `curl` package's libcurl | **Yes** — this is the target |
| `download.file(method = "libcurl")`, `url()`, `install.packages()` | R's built-in internet module (a *separate* libcurl) | Only via the **preload** mechanism, not the rebuild |
| `download.file(method = "curl")` | system curl binary | Only if a curl-impersonate wrapper is first on `PATH` |

Always confirm your actual call path with `impersonate_check()`.

## Two mechanisms (pick based on your linkage)

Run `impersonate_linkage()` to see how *your* installed `curl` package links
libcurl. It recommends one of:

- **Preload (no rebuild)** — works when the `curl` package links libcurl
  **dynamically** (typical on Linux). Set a loader variable *before R starts*
  so the existing `curl.so` picks up libcurl-impersonate.
- **Rebuild** — required when it links libcurl **statically** (the CRAN macOS
  binary does). Recompile the `curl` package against libcurl-impersonate into a
  private library; nothing in your main library changes.

**No files are edited for you.** Functions print exactly what to run or set;
you decide where it goes (interactively, `.Rprofile`, `.Renviron`, or your
shell). Less magic, fewer surprises.

## Quick start (rebuild path, e.g. macOS)

```r
library(curlimpersonate)

install_impersonate()        # download libcurl-impersonate into the user cache,
                             # then rebuild `curl` against it (verifies linkage)
```

Then make that `curl` the one R loads. It must be on the library path **before
`curl` loads**, so either run `activate()` at the very top of a script:

```r
curlimpersonate::activate()  # prepends the private library to .libPaths()
library(httr2)               # now uses libcurl-impersonate
```

…or, with no code at startup, prepend it via `R_LIBS` in `~/.Renviron`
(get the path with `cat(curlimpersonate:::.rlib_dir())`):

```
R_LIBS=/Users/you/Library/.../curlimpersonate/rlib
```

…or in `.Rprofile`:

```r
if (requireNamespace("curlimpersonate", quietly = TRUE)) curlimpersonate::activate()
```

Pick a browser and verify:

```r
curlimpersonate::impersonate_set("chrome116")
curlimpersonate::impersonate_check()      # JA4 should be Chrome's (t13d1516h2_...)
curlimpersonate::impersonate_clear()      # back to vanilla
```

## Quick start (preload path, e.g. Linux)

```r
curlimpersonate::download_impersonate()    # into the user cache
curlimpersonate::impersonate_env("chrome116")
#> export LD_PRELOAD=.../libcurl-impersonate.so
#> export CURL_IMPERSONATE=chrome116
```

Put those in your shell / launcher (the loader reads `LD_PRELOAD` at process
start, so `.Renviron` is too late), start R, then use `curl`/`httr`/`httr2` as
usual. `CURL_IMPERSONATE` can instead be set at runtime with `impersonate_set()`.

## Choosing profiles and headers

```r
impersonate_profiles()                 # list known targets
impersonate_set("firefox133")          # TLS + browser default headers
with_impersonate("safari17_0", {       # scoped to one block
  httr2::request("https://example.com") |> httr2::req_perform()
})
```

`impersonate_set(headers = TRUE)` (the default) makes libcurl-impersonate send
the browser's default headers in the browser's order — usually what you want,
since headers are themselves fingerprinted. Headers you set yourself via
`httr2::req_headers()`, `httr::add_headers()`, or
`curl::handle_setopt(.list = list(httpheader = ...))` all map to libcurl's
`CURLOPT_HTTPHEADER`, which **replaces** rather than merges — so your headers
override the impersonated defaults for the fields you set and may disturb
ordering. For maximum fidelity, set as few headers as possible and verify with
`impersonate_check()`. Use `headers = FALSE` to impersonate TLS/HTTP2 only and
manage headers entirely yourself. See `?impersonate_set` for details.

## API

| Function | Purpose |
|----------|---------|
| `impersonate_linkage()` | How the `curl` package links libcurl → which mechanism. |
| `download_impersonate()` | Download a prebuilt `libcurl-impersonate` into the user cache. |
| `build_impersonate_curl()` / `install_impersonate()` | Rebuild the `curl` package against it (private lib). |
| `activate()` / `deactivate()` | Add/remove the private lib from `.libPaths()`. |
| `impersonate_env()` | Loader env vars for the preload (no-rebuild) path. |
| `impersonate_profiles()` | List available profiles. |
| `impersonate_set()` / `impersonate_clear()` / `impersonate_profile()` / `with_impersonate()` | Select the profile. |
| `impersonate_status()` | Overview of cache, build, linkage, profile. |
| `impersonate_check()` | Hit a reflector, report JA3/JA4/HTTP2. |
| `impersonate_lib()` / `impersonate_home()` | Library path / cache location. |

## Configuration

- `CURLIMPERSONATE_HOME` — prefix with `lib/` (and optionally `include/`) of an
  existing libcurl-impersonate; set it to skip downloading. (On macOS, a
  prebuilt dylib's baked-in install name is rewritten to a resolvable path
  during the build; a read-only prefix may need manual `install_name_tool`.)
- `options(curlimpersonate.repo = "owner/repo")` — release source (default
  `lexiforest/curl-impersonate`).
- `CURL_IMPERSONATE` / `CURL_IMPERSONATE_HEADERS` — the underlying library's own
  knobs, managed by `impersonate_set()`.

## Supported builds (lexiforest, not the lwthiker original)

curl-impersonate exists in two lineages, and they are not equivalent:

- **`lexiforest/curl-impersonate`** (the default here): a **single**
  `libcurl-impersonate` that statically embeds BoringSSL and impersonates
  Chrome, Edge, Safari **and** Firefox from one library — no NSS, no separate
  CA-certificate install, and arm64 macOS builds. Verified: the downloaded
  dylib has no dynamic NSS/SSL dependency.
- **`lwthiker/curl-impersonate`** (the original): **two** libraries —
  `libcurl-impersonate-chrome` (BoringSSL) and `libcurl-impersonate-ff` (NSS).
  The Firefox build needs system NSS (`libnss3`, `nss-plugin-pem`) and CA
  certificates, ships Intel-only macOS binaries, and is largely unmaintained.

This package targets the lexiforest single-library design — that's how it
avoids the two-version + NSS complications entirely. If you point it at an
lwthiker-style install (two `-chrome`/`-ff` libraries, or an NSS-linked
library), it stops with an explanatory error rather than silently building
against one variant. A single BoringSSL library (lexiforest, or a chrome-only
lwthiker build) is fine.

## Building libcurl-impersonate yourself

Nothing is vendored. If no prebuilt binary fits your platform, build it and
point `CURLIMPERSONATE_HOME` at the result — see
[`inst/BUILD-FROM-SOURCE.md`](inst/BUILD-FROM-SOURCE.md).

## Caveats

- The rebuilt `curl` is tied to your R version/OS/arch; re-run
  `install_impersonate()` after upgrading R. `impersonate_status()` shows state.
- `install.packages("curl")` / `update.packages()` only touch your main
  library, not the private one.
- Windows is experimental (linker verification is skipped).

## Tear-down

```r
unlink(tools::R_user_dir("curlimpersonate", "data"), recursive = TRUE)
# and remove any line you added to .Rprofile / .Renviron
```
