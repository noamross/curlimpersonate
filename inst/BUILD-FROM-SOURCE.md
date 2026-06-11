# Building libcurl-impersonate from source

`curlimpersonate` does **not** vendor any binaries. It downloads a prebuilt
`libcurl-impersonate` for your platform, or uses one you already have. If no
prebuilt binary exists for your platform (or you don't trust prebuilt
binaries), build it yourself and point `curlimpersonate` at the result.

## 1. Build libcurl-impersonate

Follow the upstream instructions. Two relevant projects:

- `lexiforest/curl-impersonate` — actively maintained fork, publishes macOS
  (incl. arm64), Linux, and Windows releases. **Default source.**
- `lwthiker/curl-impersonate` — the original; largely unmaintained and without
  macOS-arm64 releases.

The build produces a patched BoringSSL plus an ABI-compatible
`libcurl-impersonate` shared library. It is a heavy build (BoringSSL + curl);
the project's `Dockerfile`s are the most reliable route. Install into a prefix,
e.g. `/opt/curl-impersonate`, so you end up with:

```
/opt/curl-impersonate/
  lib/      libcurl-impersonate*.{dylib,so,dll}
  include/  curl/curl.h   (optional — system curl headers also work)
  bin/      curl-impersonate-chrome, ...  (optional)
```

## 2. Point curlimpersonate at it

```r
Sys.setenv(CURLIMPERSONATE_HOME = "/opt/curl-impersonate")
curlimpersonate::build_impersonate_curl()   # skips download, just rebuilds curl
```

`build_impersonate_curl()` reinstalls the R `curl` package from source into the
private library (`tools::R_user_dir("curlimpersonate", "data")/rlib`), forcing
it to link your `libcurl-impersonate` via the `curl` package's own
`CURL_CFLAGS`/`CURL_LIBS` configure hooks (these take precedence over
pkg-config and over the macOS autobrew fallback). Headers come from
`$CURLIMPERSONATE_HOME/include` if present, otherwise from your system curl
(Homebrew / `/usr/include`) — fine because the ABI is curl-compatible.

> A pkg-config shim is **not** used: on macOS the `curl` configure requires
> libcurl ≥ 8.8.0 via pkg-config and otherwise downloads a static libcurl, so a
> shim declaring an older version is silently ignored.

### macOS install names

Prebuilt macOS dylibs often record an absolute install name
(`LC_ID_DYLIB`) from the machine they were built on (e.g.
`/Users/runner/work/...`). The package rewrites this to the real path with
`install_name_tool` and ad-hoc re-signs the dylib, so the rebuilt `curl.so`
can find it. This requires the dylib to be **writable**; if you point
`CURLIMPERSONATE_HOME` at a read-only prefix, fix install names yourself or use
the writable download cache.

## 3. Activate and use

```r
curlimpersonate::use_impersonate(scope = "user", profile = "chrome116")  # writes ~/.Rprofile
# restart R, then:
curlimpersonate::impersonate_check()
```

## Platform notes

- **macOS**: the CRAN `curl` binary statically links libcurl, so a rebuild
  (what this package does) is required — preloading a dylib cannot work.
- **Linux**: the system `curl` package usually links libcurl dynamically, so
  you *can* alternatively `LD_PRELOAD` the impersonate `.so` before launching
  R. Rebuilding still works and is what this package standardizes on.
- **Windows**: experimental. Needs Rtools and a Windows libcurl-impersonate
  build; linker verification is skipped.
