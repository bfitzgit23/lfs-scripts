#!/bin/sh
# Convert a scratchpkg "spkgbuild" recipe into a CRUX pkgutils "Pkgfile".
#
# pkgmk already cd's into $SRC/$name-$version before calling build(), so the
# spkgbuild idiom of cd'ing there is dropped. build_opt is not understood by
# pkgutils and is dropped; empty backup/noextract strings are dropped because
# pkgutils expects arrays. CRs are stripped so heredocs terminate correctly.
in=$1
out=$2
tr -d '\r' < "$in" | awk '
  /^[[:space:]]*cd[[:space:]]+\$name-\$version[[:space:]]*;?[[:space:]]*$/ { next }
  /^[[:space:]]*cd[[:space:]]+"\$name-\$version"[[:space:]]*;?[[:space:]]*$/ { next }
  /^[[:space:]]*build_opt=/ { next }
  /^[[:space:]]*backup=""[[:space:]]*$/ { next }
  /^[[:space:]]*noextract=""[[:space:]]*$/ { next }
  { print }
' > "$out"
