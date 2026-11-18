#!/bin/sh
# sync-venom-ports.sh - convert the venomlinux spkgbuild port trees into
# CRUX Pkgfile recipes for pkgutils/prt-get and import them into the local
# port trees.
#
# Each upstream tree is cloned (or updated) into $VENOM_SRC, then every
# spkgbuild is converted with tools/spkgbuild2pkgfile.sh rules into a staging
# area and imported:
#   core, extra, multilib              -> ports/{core,extra,multilib}
#   nonfree, mate, xfce, kde-lxqt, s6  -> ports/{nonfree,mate,xfce,kde-lxqt,s6}
# A port whose name already exists in a local tree is skipped: the local copy is
# the distribution's own (LFS 13.1 pins, the source-mirror patches), and a second
# copy under the same name would change what prt-get resolves.
#
# A port's `depends` file, when present, becomes a `# Depends: ...` header line
# because that is how prt-get reads dependencies from a Pkgfile.
#
# Usage: tools/sync-venom-ports.sh [repo ...]
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DEST_ROOT="$ROOT/ports"
CLONE_DIR=${VENOM_SRC:-/tmp/venom}
TREES=${*:-"core extra nonfree multilib kde-lxqt mate xfce s6"}

STAGE=$(mktemp -d)
AWK_PROG=$(mktemp)
LIST=$(mktemp)
NEW=$(mktemp)
HAVE=$(mktemp)
trap 'rm -rf "$STAGE"; rm -f "$AWK_PROG" "$LIST" "$NEW" "$HAVE"' EXIT

OUT="$STAGE"
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
    # pre-create the staging directories so the converter never has to
    find "$CLONE_DIR/$r" -name spkgbuild | sed "s|^$CLONE_DIR/||; s|/spkgbuild\$||" |
        awk -v out="$OUT" '{ print out "/venom-" $0 }' |
        xargs -P 16 -I{} mkdir -p {} 2>/dev/null

    find "$CLONE_DIR/$r" -name spkgbuild | sort |
        xargs awk -f "$AWK_PROG"
    echo "$r: $(find "$STAGE/venom-$r" -name Pkgfile 2>/dev/null | wc -l) recipes converted"
done

# ---------------------------------------------------------------- importing ---
# Names the local trees already provide. Port directories sit at
# ports/<tree>/<port>; the imported scratchpkg trees are deeper and cannot
# collide with a recipe name.
for t in core extra contrib multilib opt nonfree mate xfce kde-lxqt s6; do
    [ -d "$DEST_ROOT/$t" ] || continue
    ls "$DEST_ROOT/$t"
done | LC_ALL=C sort -u > "$HAVE"

for r in $TREES; do
    [ -d "$STAGE/venom-$r" ] || continue
    dest="$DEST_ROOT/$r"
    ls "$STAGE/venom-$r" | LC_ALL=C sort > "$LIST"
    total=$(wc -l < "$LIST")
    comm -23 "$LIST" "$HAVE" > "$NEW"
    n=0
    while IFS= read -r p; do
        mkdir -p "$dest/$p"
        cp "$STAGE/venom-$r/$p/Pkgfile" "$dest/$p/Pkgfile"
        n=$((n + 1))
    done < "$NEW"
    if [ "$n" -gt 0 ]; then
        LC_ALL=C sort -u -o "$HAVE" "$HAVE" "$NEW"
    fi
    echo "$r -> ports/$r: $n imported, $((total - n)) already provided locally"
done

echo "total: $(find "$DEST_ROOT" -mindepth 3 -maxdepth 3 -name Pkgfile | wc -l) ports in the local trees"
