Is it possible to just load the curl library _linking_ to curlimpersonate, rather than building against it?

We should get rid of all the things automatically editing .Rprofile.  Docs should just note what function(s)
should be run or env vars that need to be set before loading curl httr/2 or any other curl-using libraries, suggesting what be put in .Rprofile or environent variables
in .Renviron or elsewhre.  In general less obfuscation of what is actually hapenning.

Docs should reflect that the user may use `curl` directly, or other packages that use `curl`, not just httr/2 packages.

Differentiate between the `curl` R package and system curl/libcurl in docs

Docs should note whether curlimpersonate works  R functions like download.file, if a user check that it does when using the `method` arg, etc.

We definitely needs tests that this works across macos and linux runners on github, but overall let's keep the infrastructure of this package minimal.

There should be a function to read the available profiles, and we should in the docs using roxygen {expr} for the function(s) that set the profile

There should be clear explanation of how using curlimpersonate sets headers by default, and whether/how setting headers and options downstream such as via the curl or httr/2 packages overrides or otherwise interacts with those.