#!/bin/sh
# Convert a scratchpkg "spkgbuild" recipe into a CRUX pkgutils "Pkgfile".
#
# pkgmk already cd's into $SRC/$name-$version before calling build(), so the
# spkgbuild idiom of cd'ing there is dropped. Empty backup/noextract strings are
# dropped because pkgutils expects arrays. Everything else - including build_opt,
# which is only ever read inside build() and is valid shell in a Pkgfile - is
# carried over verbatim, so multi-line arrays and quoted strings stay intact.
# CRs are stripped so heredocs terminate correctly.
in=$1
out=$2
tr -d '\r' < "$in" | awk '
  /^[[:space:]]*cd[[:space:]]+"?\$name-\$version"?[[:space:]]*;?[[:space:]]*$/ { next }
  /^[[:space:]]*backup=""[[:space:]]*$/ { next }
  /^[[:space:]]*noextract=""[[:space:]]*$/ { next }
  { print }
' > "$out"
