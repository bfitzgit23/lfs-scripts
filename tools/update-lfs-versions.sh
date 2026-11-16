#!/bin/sh
# Update ports/*/Pkgfile "version=" fields from an LFS wget-list.
# usage: update-lfs-versions.sh <wget-list> <ports-dir>
list=$1; ports=$2
awk -F/ '{ f=$NF; sub(/\.tar\.(xz|gz|bz2|lz)$/,"",f);
           n=f; sub(/-[0-9][^-]*$/, "", n);
           v=f; sub("^" n "-", "", v);
           if (n == f) next;
           print n, v }' "$list" | sort -u > /tmp/lfs-versions.txt
updated=0; missing=""
while read -r n v; do
    d=$(find "$ports" -maxdepth 2 -type d -name "$n" 2>/dev/null | head -1)
    if [ -n "$d" ] && [ -f "$d/Pkgfile" ]; then
        old=$(sed -n 's/^version=//p' "$d/Pkgfile" | head -1)
        if [ "$old" != "$v" ]; then
            sed -i "s/^version=.*/version=$v/" "$d/Pkgfile"
            echo "  $n: $old -> $v"
            updated=$((updated+1))
        fi
    else
        missing="$missing $n-$v"
    fi
done < /tmp/lfs-versions.txt
echo "updated: $updated"
echo "no matching port:$missing"
