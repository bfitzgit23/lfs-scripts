#!/bin/sh

PKG="$1"
DESTDIR="$2"

SVDIR="${DESTDIR}"/etc/s6/sv
CONFDIR="${DESTDIR}"/etc/s6/config

for dir in "srv/$PKG"/*; do
    if [ -d "$dir" ]; then
        dirname=$(basename "$dir")
        TOPDIR="${SVDIR}"
        # Install log if needed
        srv_count=$(find "srv/$PKG" -name "*-srv" -type d | wc -l)
        if [ "$srv_count" -eq 1 ] && echo "$dir" | grep -q "\-srv"; then
            srvname=$(basename "$dir" | cut -d "-" -f 1)
            install -v -d "${TOPDIR}/$srvname-log"
            for file in "log"/*; do
                install -v -m644 "$file" "${TOPDIR}/$srvname-log"
                filename=$(basename "$file")
                sed -i "s/daemon/$srvname/g" "${TOPDIR}/$srvname-log/$filename"
                sed -i "s/template/$PKG/g" "${TOPDIR}/$srvname-log/$filename"
            done
        fi
        if [ -f "srv/$PKG/$PKG.conf" ] || ([ "$srv_count" -gt 0 ] && echo "$dir" | grep -q "\-srv"); then
            install -v -d "${CONFDIR}"
            # If a config already exists, don't install the generic one.
            if [ -f "srv/$PKG/$PKG.conf" ]; then
                install -v -m644 "srv/$PKG/$PKG.conf" "${CONFDIR}/$PKG.conf"
            else
                install -v -m644 "conf" "${CONFDIR}/$PKG.conf"
            fi
        fi
        # Install srv
        install -v -d "${TOPDIR}/$dirname"
        for file in "$dir"/*; do
            install -v -m644 "$file" "${TOPDIR}/$dirname"
        done
        # Install any dependencies.d files if needed
        for subdir in "$dir"/*; do
            if [ -d "$subdir" ]; then
                subdirname=$(basename "$subdir")
                install -v -d "${TOPDIR}/$dirname/$subdirname"
                for file in "$subdir"/*; do
                    install -v -m644 "$file" "${TOPDIR}/$dirname/$subdirname"
                done
            fi
        done
    fi
done
