#!/bin/sh
# Regenerate the httpup REPO index of every port collection in this repository.
#
# /etc/ports/<tree>.httpup (installed by the ports package) makes `ports -u`
# fetch a collection over httpup, and httpup only downloads the files listed in
# the collection's REPO index, so the index has to be regenerated whenever a
# port is added, removed or edited.
#
# Usage: ports/repgen.sh [tree ...]

TREES=${*:-"core extra contrib multilib opt nonfree mate xfce kde-lxqt s6"}
TREES="$TREES compat-32 compiz gnome iso kde4 lxqt plasma xorg"

for i in $TREES; do
	httpup-repgen "$i" || exit 1
done
