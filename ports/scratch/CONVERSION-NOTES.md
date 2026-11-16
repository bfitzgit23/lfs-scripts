# spkgbuild -> Pkgfile conversion notes

All 1429 scratchpkg recipes are converted to CRUX `Pkgfile` form by
`tools/spkgbuild2pkgfile.sh` and pass `bash -n`. No recipe is left copied
verbatim, and there are no entries here to review.

The conversion removes only what pkgutils makes redundant:

* the standalone `cd $name-$version` line, because `pkgmk` already runs
  `build()` inside `$SRC/$name-$version`;
* an empty `backup=""` or `noextract=""`, because pkgutils expects arrays.

Everything else, including `build_opt` (a plain shell variable read inside
`build()`), is carried over unchanged, so multi-line arrays and quoted strings
survive intact. CRs are stripped so heredocs terminate correctly.
