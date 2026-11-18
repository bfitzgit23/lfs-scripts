#!/bin/sh
# audit-ports.sh - mechanical audit of the port trees in this repository.
#
# Checks every port for the things that fail silently in this tree:
#   * no Pkgfile
#   * a build() hook: pkgutils dispatches pkg_build() (build() is the driver
#     function in pkgutils' extension), so a Pkgfile-level build() never runs
#   * no .md5sum (the port is not considered complete by httpup either)
#   * no .footprint (pkgmk then writes a new one, which is fine but worth knowing)
#   * source URLs that do not answer 200 (only with --net; this hits the network
#     once per URL, so give it time)
#
# Usage: tools/audit-ports.sh [--net] [tree ...]
#   With no tree argument every tree under ports/ plus ports/scratch/* is used.

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

NET=no
TREES=
for arg in "$@"; do
	case $arg in
		--net) NET=yes ;;
		-*) echo "unknown option: $arg" >&2; exit 2 ;;
		*) TREES="$TREES $arg" ;;
	esac
done

if [ -z "$TREES" ]; then
	TREES="core extra contrib multilib opt nonfree mate xfce kde-lxqt s6"
	for d in ports/scratch/*/; do
		[ -d "$d" ] && TREES="$TREES ${d%/}"
	done
fi

total=0
p_nopkg=0
p_buildhook=0
p_nomd5=0
p_nofp=0
p_badurl=0

printf '%-24s %5s %8s %7s %6s %6s %6s %6s\n' tree ports noPkgfile buildHook noMd5sum noFprint badURL

for t in $TREES; do
	[ -d "$t" ] || continue
	n=0; a=0; b=0; m=0; f=0; u=0
	for d in "$t"/*/; do
		[ -d "$d" ] || continue
		case ${d##*/} in REPO|files) continue ;; esac
		n=$((n + 1))
		if [ ! -f "${d}Pkgfile" ]; then
			a=$((a + 1))
			echo "NO-PKGFILE   ${d%/}"
			continue
		fi
		[ -f "${d}.md5sum" ] || m=$((m + 1))
		[ -f "${d}.footprint" ] || f=$((f + 1))
		if grep -qE '^build[[:space:]]*\(\)' "${d}Pkgfile"; then
			b=$((b + 1))
			echo "BUILD-HOOK   ${d%/} (build() never runs, use pkg_build())"
		fi
		if [ "$NET" = yes ]; then
			for url in $(grep -oE 'https?://[^ )"]+' "${d}Pkgfile" | sort -u); do
				code=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 20 "$url" || echo 000)
				case $code in
					200|301|302) ;;
					*) u=$((u + 1)); echo "URL $code      $url ($d)" ;;
				esac
			done
		fi
	done
	printf '%-24s %5s %8s %7s %6s %6s %6s %6s\n' "${t%/}" "$n" "$a" "$b" "$m" "$f" "$u"
	total=$((total + n)); p_nopkg=$((p_nopkg + a)); p_buildhook=$((p_buildhook + b))
	p_nomd5=$((p_nomd5 + m)); p_nofp=$((p_nofp + f)); p_badurl=$((p_badurl + u))
done

echo
echo "ports=$total no-pkgfile=$p_nopkg dead-build-hook=$p_buildhook no-md5sum=$p_nomd5 no-footprint=$p_nofp bad-url=$p_badurl"
