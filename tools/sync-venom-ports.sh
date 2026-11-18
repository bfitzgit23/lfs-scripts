#!/bin/sh
# sync-venom-ports.sh - convert the venomlinux spkgbuild port trees into
# CRUX Pkgfile recipes for pkgutils/prt-get.
#
# Each upstream tree is cloned (or updated) into $VENOM_SRC, then every
# spkgbuild is converted with tools/spkgbuild2pkgfile.sh rules into
#   ports/venom-<repo>/<port>/Pkgfile
# A port's `depends` file, when present, becomes a `# Depends: ...` header line
# because that is how prt-get reads dependencies from a Pkgfile.
#
# Usage: tools/sync-venom-ports.sh [repo ...]
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
OUT="$ROOT/ports"
CLONE_DIR=${VENOM_SRC:-/tmp/venom}
TREES=${*:-"core extra nonfree multilib kde-lxqt mate xfce s6"}

export CLONE_DIR OUT

# ---------------------------------------------------------------- cloning ---
for r in $TREES; do
    if [ -d "$CLONE_DIR/$r/.git" ]; then
        git -C "$CLONE_DIR/$r" fetch --depth 1 -q origin >/dev/null 2>&1 || true
        git -C "$CLONE_DIR/$r" reset --hard -q origin/HEAD >/dev/null 2>&1 || true
        echo "updated $r"
    else
        mkdir -p "$CLONE_DIR"
        git clone --depth 1 -q "https://codeberg.org/venomlinux/$r.git" "$CLONE_DIR/$r"
        echo "cloned $r"
    fi
done

# ------------------------------------------------------------- converting ---
# pkgmk cds into $name-$version itself, so the spkgbuild cd is dropped; empty
# backup/noextract strings are dropped because pkgutils expects arrays.
# The recipe hook is renamed: in this tree build() is the pkgutils driver, and
# a Pkgfile build() is never called, so spkgbuild's build() becomes pkg_build().
# build_opt and everything else is kept verbatim so multi-line arrays survive.
AWK_PROG=$(mktemp)
trap 'rm -f "$AWK_PROG"' EXIT
cat > "$AWK_PROG" <<'AWK'
function outpath(f,  d) {
    d = f
    sub(/^.*\/venom\//, "", d)
    sub(/^.*\/CLONE_PLACEHOLDER\//, "", d)
    sub(/\/spkgbuild$/, "", d)
    return ENVIRON["OUT"] "/venom-" d
}
FNR == 1 {
    p = outpath(FILENAME) "/Pkgfile"
    if (p != cur) { if (cur != "") close(cur); cur = p }
    dep = FILENAME
    sub(/\/spkgbuild$/, "/depends", dep)
    hdr = ""
    while ((getline dl < dep) > 0) {
        sub(/\r/, "", dl)
        if (dl != "") hdr = (hdr == "" ? dl : hdr " " dl)
    }
    close(dep)
    if (hdr != "") print "# Depends: " hdr > cur
}
{
    line = $0
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*cd[ \t]+"?\$name-\$version"?[ \t]*;?[ \t]*$/) next
    if (line ~ /^[ \t]*backup=""[ \t]*$/) next
    if (line ~ /^[ \t]*noextract=""[ \t]*$/) next
    if (line ~ /^[ \t]*build[ \t]*\(\)[ \t]*\{[ \t]*$/) {
        print "pkg_build() {" > cur
        next
    }
    print line > cur
}
END { if (cur != "") close(cur) }
AWK

for r in $TREES; do
    [ -d "$CLONE_DIR/$r" ] || continue
    # pre-create the target directories so the converter never has to
    find "$CLONE_DIR/$r" -name spkgbuild | sed "s|^$CLONE_DIR/||; s|/spkgbuild\$||" |
        awk -v out="$OUT" '{ print out "/venom-" $0 }' |
        xargs -P 16 -I{} mkdir -p {} 2>/dev/null

    find "$CLONE_DIR/$r" -name spkgbuild | sort |
        xargs awk -f "$AWK_PROG"
    echo "$r: $(find "$OUT/venom-$r" -name Pkgfile 2>/dev/null | wc -l) Pkgfiles"
done

echo "total: $(find "$OUT" -path '*/venom-*' -name Pkgfile | wc -l)"
