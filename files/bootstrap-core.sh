#!/bin/sh -e

HOSTPATH=$(printf "%s" "$PATH" | sed -e "s|$TOOLS/bin:||g" -e "s|:$TOOLS/bin||g")
	# keep the toolchain last: bsdtar and friends live there, but the host as/ld
	# must win
	HOSTPATH="$HOSTPATH:$TOOLS/bin"

# The ports, files/ and sources/ paths below are relative to the repository
# root, so anchor on the script location instead of the caller's cwd.
cd "$(dirname "$0")/.." || exit 1

_ensure_toolchain_shims() {
	# The base system starts from an empty rootfs and needs a handful of
	# toolchain binaries - env(1) above all - before anything can run inside
	# the chroot. These shims are recreated every run: an aborted stage 2
	# leaves $LFS/var/lib/pkg/db behind, and gating on it used to skip the
	# shims and fail later with "chroot: failed to run 'env'".
	_tc="$LFS$TOOLS"
	if [ ! -x "$_tc/bin/env" ]; then
		echo "error: the temporary toolchain is missing: $_tc/bin/env" >&2
		echo "       run stage 1 first, and check that LFS ($LFS) and TOOLS" >&2
		echo "       ($TOOLS) point at the same tree used to build it." >&2
		return 1
	fi
	mkdir -p "$LFS/bin" "$LFS/usr/bin" "$LFS/usr/lib" "$LFS/etc" "$LFS/dev"
	for i in bash cat chmod dd echo ln mkdir pwd rm stty; do
		ln -sfn "$TOOLS/bin/$i" "$LFS/bin/$i"
	done
	for i in env install perl printf touch; do
		ln -sfn "$TOOLS/bin/$i" "$LFS/usr/bin/$i"
	done
	ln -sfn "$TOOLS/lib/libgcc_s.so" "$LFS/usr/lib/libgcc_s.so"
	ln -sfn "$TOOLS/lib/libgcc_s.so.1" "$LFS/usr/lib/libgcc_s.so.1"
	for i in libstdc++.a libstdc++.so libstdc++.so.6; do
		ln -sfn "$TOOLS/lib/$i" "$LFS/usr/lib/$i"
	done
	ln -sfn bash "$LFS/bin/sh"
	ln -sfn /proc/self/mounts "$LFS/etc/mtab"
	return 0
}

_chroot() {
	# chroot with a clean environment, using an env(1) that exists inside the
	# target root rather than assuming one is on PATH there.
	_env=""
	for _cand in "$TOOLS/bin/env" /usr/bin/env /bin/env; do
		if [ -x "$LFS$_cand" ]; then
			_env="$_cand"
			break
		fi
	done
	if [ -z "$_env" ]; then
		echo "error: no env(1) inside $LFS; run stage 1 before stage 2" >&2
		return 1
	fi
	# Never let the host's LC_ALL into the chroot: the probe at the end of this
	# file exports a C.UTF-8 that only the temporary toolchain's libc can load,
	# and readline hands the name straight to the rootfs libc's setlocale() -
	# which is the call that crashed python's build. _ensure_chroot_locale()
	# raises this to C.UTF-8 only once the rootfs itself has verified it.
	chroot "$LFS" "$_env" -i PATH="$LFSPATH" LC_ALL="${_chrootlocale:-C}" "$@"
}

# A rootfs glibc carries no compiled locale data of its own: the ports install
# the C.UTF-8 the temporary toolchain needs (see the glibc port), but this
# tree generates it with the build tree's loader, which does not necessarily
# produce data this libc can load. bash then warns "setlocale: LC_ALL: cannot
# change locale (C.UTF-8)" on every command, and readline's _rl_init_locale()
# passes that same unusable name to setlocale(), which faults inside libc the
# first time a module imports readline - python's build dies there with
# "Makefile: checksharedmods: Segmentation fault". Regenerate the locale with
# the rootfs' own localedef, and hand the chroot only a locale its libc can
# really set.
_ensure_chroot_locale() {
	_chrootlocale=C
	# /usr/bin/localedef exists only once the glibc package is installed
	[ -x "$LFS/usr/bin/localedef" ] || return 0
	if _chroot sh -c '[ "$(LC_ALL=C.UTF-8 /usr/bin/locale charmap 2>/dev/null)" = UTF-8 ]'; then
		_chrootlocale=C.UTF-8
		return 0
	fi
	# The glibc port generates this locale with the build tree's localedef, and
	# only while glibc itself is being built - a --resume run skips it, and the
	# data that build tree left behind is exactly what this libc cannot load.
	# Regenerate in place with the installed localedef and keep its complaint.
	if ! _chroot sh -c 'rm -rf /usr/lib/locale/C.UTF-8 && /usr/bin/localedef -i C -f UTF-8 C.UTF-8' >"$LFS/tmp/localedef.log" 2>&1; then
		echo "stage: warning: localedef could not generate C.UTF-8:" >&2
		sed 's/^/    /' "$LFS/tmp/localedef.log" >&2
	fi
	rm -f "$LFS/tmp/localedef.log"
	if _chroot sh -c '[ "$(LC_ALL=C.UTF-8 /usr/bin/locale charmap 2>/dev/null)" = UTF-8 ]'; then
		_chrootlocale=C.UTF-8
	else
		echo "stage: warning: the rootfs libc cannot load C.UTF-8, building with LC_ALL=C" >&2
	fi
	return 0
}

# Resume support. Every package that finishes is recorded under $LFS, so a run
# that dies (bad source, compiler error, Ctrl-C, reboot) can be restarted and
# skips the work already done instead of rebuilding the whole toolchain.
_state_dir() { echo "$LFS/var/lib/lfs-scripts"; }
_state_file() { echo "$(_state_dir)/stage$1.done"; }

_state_has() {
	grep -qx "$2" "$(_state_file "$1")" 2>/dev/null
}

_state_mark() {
	mkdir -p "$(_state_dir)" 2>/dev/null || return 0
	_state_has "$1" "$2" || echo "$2" >> "$(_state_file "$1")"
	rm -f "$(_state_dir)/stage$1.failed"
}

_state_fail() {
	mkdir -p "$(_state_dir)" 2>/dev/null
	echo "$2" > "$(_state_dir)/stage$1.failed"
}

_state_complete() {
	mkdir -p "$(_state_dir)" 2>/dev/null
	date '+%Y-%m-%d %H:%M:%S' > "$(_state_dir)/stage$1.complete"
	rm -f "$(_state_dir)/stage$1.failed"
}

_state_summary() {
	if [ -f "$(_state_dir)/stage$1.complete" ]; then
		echo "stage $1: already complete ($(cat "$(_state_dir)/stage$1.complete"))"
		return 0
	fi
	if [ -s "$(_state_file "$1")" ]; then
		echo "stage $1: resuming, $(wc -l < "$(_state_file "$1")" | tr -d ' ') package(s) already complete"
	fi
	if [ -f "$(_state_dir)/stage$1.failed" ]; then
		echo "stage $1: the last attempt stopped at '$(cat "$(_state_dir)/stage$1.failed")'"
	fi
}

_buildtoolchain() {
	if [ "$(id -u)" = 0 ]; then
		echo "temporary toolchain need to build as regular user"
		exit 1
	fi

	export BOOTSTRAP=1
	export LFS_TGT=x86_64-lfs-linux-gnu
	export LFS_TGT32=i686-lfs-linux-gnu
	
	mkdir -p ${LFS}${TOOLS} $sourcedir
	rm -f $TOOLS
	ln -sf ${LFS}${TOOLS} $TOOLS

	# A run that died part way can leave skip markers without a usable
	# toolchain. Every package then takes the "already built" path, the loop
	# does no work, and stage 1 still prints "completed".
	if [ ! -x "$TOOLS/bin/env" ] && [ -n "$(ls -A "$TOOLS" 2>/dev/null)" ]; then
		echo "stage 1: $TOOLS has no usable bin/ - clearing stale build markers"
		for m in $toolchainpkg; do rm -f "$TOOLS/$m"; done
	fi
	
	echo "
export MAKEFLAGS=-j$(nproc)

PKGMK_SOURCE_DIR=$sourcedir
PKGMK_PACKAGE_DIR=/tmp/lfs-pkg

. $PWD/files/pkgmk.bootstrap
" > /tmp/bootstrap.conf

	if [ ! "$(PATH=$TOOLS/bin command -v pkgmk)" ]; then
		if [ ! -f $sourcedir/pkgutils-5.40.10.tar.xz ]; then
			curl -o $sourcedir/pkgutils-5.40.10.tar.xz https://crux.nu/files/pkgutils-5.40.10.tar.xz
		fi
		rm -rf /tmp/pkgutils-5.40.10
		tar -xf $sourcedir/pkgutils-5.40.10.tar.xz -C /tmp
		sed -i -e 's/ --static//' -e 's/ -static//' /tmp/pkgutils-5.40.10/Makefile
		make -j$(nproc) -C /tmp/pkgutils-5.40.10
		make -j$(nproc) -C /tmp/pkgutils-5.40.10 BINDIR=$TOOLS/bin MANDIR=$TOOLS/man ETCDIR=$TOOLS/etc install
		rm -rf /tmp/pkgutils-5.40.10
	fi
	
	# The stages up to gcc-pass2 are compiled by the *host* compiler: there is
	# no working cross compiler yet. $TOOLS/bin is first on PATH, and pass 1
	# binutils has just filled it, so the host gcc would pick up those as/ld.
	# Build these packages with the host toolchain and only the host PATH.

	# The toolchain sources predate C23. gcc 15 and later default to -std=gnu23,
	# where e.g. strchr() returns a const pointer, and a package that compiles
	# with -Werror (libxcrypt) then fails on its own code. Build as C17 and do
	# not turn warnings into errors for the bootstrap.
	export CFLAGS="-O2 -std=gnu17 -Wno-error"
	export CXXFLAGS="$CFLAGS"

	# Without this, PKG_CHECK_MODULES in every configure script is answered by
	# the host pkg-config with the host .pc files. A .pc file for /usr/include
	# contributes no -I flag (pkg-config drops system dirs), so a module gets
	# enabled by the host library while its header cannot be found: this
	# compiler's native system header dir is $TOOLS/include, not /usr/include.
	# That is what broke python at zlib.h, zstd.h, lzma.h and readline.h.
	# Point pkg-config at the temporary toolchain only.
	export PKG_CONFIG_PATH=
	export PKG_CONFIG_LIBDIR="$TOOLS/lib/pkgconfig:$TOOLS/libdata/pkgconfig:$TOOLS/share/pkgconfig"
	hostnative="binutils-pass1 gmp mpfr mpc gcc-pass1"
	HOSTPATH=$(printf '%s' "$PATH" | sed -e "s|$TOOLS/bin:||g" -e "s|:$TOOLS/bin||g")
	HOSTCC=$(PATH="$HOSTPATH" command -v gcc 2>/dev/null || PATH="$HOSTPATH" command -v cc 2>/dev/null || true)
	HOSTCXX=$(PATH="$HOSTPATH" command -v g++ 2>/dev/null || PATH="$HOSTPATH" command -v c++ 2>/dev/null || true)
	if [ -z "$HOSTCC" ]; then
		echo "error: no host C compiler (gcc or cc) found" >&2
		echo "       looked in: $HOSTPATH" >&2
		echo "       a host toolchain (gcc, make, tar, xz) is required for stage 1" >&2
		exit 1
	fi
	echo "stage 1: host compiler $HOSTCC"
	echo "stage 1: host PATH $HOSTPATH"
	echo "stage 1: assembler $(command -v as || echo MISSING), linker $(command -v ld || echo MISSING)"

	# Anything the caller exported leaks into every configure probe, and gmp
	# reports a polluted environment as "could not find a working compiler".
	runclean="env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u CC -u CXX -u CPP -u LD"

	# gmp 6.3.0's configure probes declare `void g(){}` and then call g() with
	# six arguments. gcc 15 and later default to C23, where an empty parameter
	# list means "(void)", so that probe stops compiling and gmp reports
	# "could not find a working compiler". These sources predate C23; build
	# the pre-toolchain packages as C17.
	hostcflags="$CFLAGS"

	# Prove the host compiler works before spending time on binutils, and say
	# what it said if it does not.
	_ctmp=$(mktemp -d)
	printf 'int main(void){return 0;}
' > "$_ctmp/t.c"
	echo "stage 1: test-compiling with $HOSTCC"
	if ! $runclean CC="$HOSTCC" "$HOSTCC" -o "$_ctmp/t" "$_ctmp/t.c" 2>"$_ctmp/err"; then
		echo "stage 1: the host compiler cannot build a trivial program:" >&2
		sed -e 's/^/    /' "$_ctmp/err" >&2
		echo "stage 1: environment that affects it:" >&2
		echo "    CC=${CC-<unset>} CFLAGS=${CFLAGS-<unset>}" >&2
		echo "    LDFLAGS=${LDFLAGS-<unset>} LD=${LD-<unset>}" >&2
		rm -rf "$_ctmp"
		exit 1
	fi
	if ! "$_ctmp/t" >/dev/null 2>&1; then
		echo "stage 1: warning: the host compiler links, but the binary will not run" >&2
		echo "stage 1:          (is /tmp mounted noexec?) - configure probes will fail" >&2
	fi
	rm -rf "$_ctmp"
	echo "stage 1: host compiler works"
	_state_summary 1
	case "$LFS" in
		/tmp/*)
			echo "note: $LFS is under /tmp; if /tmp is cleared at boot the"
			echo "      toolchain and this resume state are lost with it"
			;;
	esac

	if [ -f "$(_state_dir)/stage1.complete" ]; then
		echo "stage 1: already complete, nothing to do"
		echo "         delete $(_state_dir) to rebuild the toolchain from scratch"
		return 0
	fi


	_todo=""
	for i in $toolchainpkg; do
		if [ -f "$TOOLS/$i" ] || _state_has 1 "$i"; then
			continue
		fi
		_todo="$_todo $i"
	done
	echo "stage 1: packages still to build:${_todo:- none}"

	n=0
	built=0
	skipped=0
	empty=""
	for i in $toolchainpkg; do
		n=$((n+1))
		if [ -f "$TOOLS/$i" ] || _state_has 1 "$i"; then
			echo "[$n] $i: already built, skipping"
			skipped=$((skipped+1))
			continue
		fi
		echo "[$n] $i: building"
		export tcpkg="$i"
		cd "ports/core/${i%-pass*}" || exit 1
		mkdir -p /tmp/lfs-pkg
		# A rebuild rewrites paths that are already in $TOOLS, so comparing
		# file counts reports "installed nothing" for a package that was
		# installed correctly. Compare timestamps: a file newer than this
		# reference is one the build just put there.
		ref="$(_state_dir)/.ref.$i"
		mkdir -p "$(_state_dir)" 2>/dev/null
	touch -d '2 seconds ago' "$ref" 2>/dev/null || : > "$ref"
		# -f: without it pkgmk is free to answer "Package is up to date" and
		# exit 0, which used to leave a skip marker and no toolchain.
		_pkgmk_rc=0
		case " $hostnative " in
			*" $i "*)
				echo "    (host toolchain: $HOSTCC, CFLAGS=$hostcflags)"
				if [ -n "$HOSTCXX" ]; then
					$runclean PATH="$HOSTPATH" CC="$HOSTCC" CXX="$HOSTCXX" CFLAGS="$hostcflags" CXXFLAGS="$hostcflags" 						"$TOOLS/bin/pkgmk" -d -f -is -if -im -cf /tmp/bootstrap.conf || _pkgmk_rc=$?
				else
					$runclean PATH="$HOSTPATH" CC="$HOSTCC" CFLAGS="$hostcflags" "$TOOLS/bin/pkgmk" -d -f -is -if -im -cf /tmp/bootstrap.conf || _pkgmk_rc=$?
				fi
				;;
			*)
				pkgmk -d -f -is -if -im -cf /tmp/bootstrap.conf || _pkgmk_rc=$?
				;;
		esac
		if [ "$_pkgmk_rc" -ne 0 ]; then
			# configure decisions are invisible in the pkgmk output, so show
			# what the compiler probe actually said before giving up.
			for l in work/*/config.log work/config.log */config.log; do
				[ -f "$l" ] || continue
				echo "---- tail of $l ----"
				tail -n 40 "$l"
				echo "---- end of $l ----"
				break
			done
			echo "host compiler: ${HOSTCC:-<not used for this package>}" >&2
			echo "host path: ${HOSTPATH:-$PATH}" >&2
			ls -l "$TOOLS/bin" 2>/dev/null | head -n 10 >&2
			_state_fail 1 "$i"
			echo "error: pkgmk failed for '$i'" >&2
			echo "       fix the cause, then resume with: ./bootstrap.sh --resume" >&2
			echo "       completed packages are recorded in $(_state_dir)" >&2
			exit 1
		fi
		rm -rf /tmp/lfs-pkg
		cd - >/dev/null 2>&1
		after=$(find -L "$TOOLS" -newer "$ref" ! -name ".ref.$i" 2>/dev/null | wc -l)
		rm -f "$ref"
		if [ "$after" -eq 0 ]; then
			echo "warning: $i installed nothing into $TOOLS" >&2
			empty="$empty $i"
		fi
		touch "$TOOLS/$i"
		_state_mark 1 "$i"
		built=$((built+1))
		unset tcpkg
	done
	rm -f /tmp/bootstrap.conf

	missing=""
	for f in bin/env bin/bash bin/make bin/tar bin/ld bin/gcc bin/sed; do
		[ -x "$TOOLS/$f" ] || missing="$missing $f"
	done
	if [ -n "$missing" ] || [ -n "$empty" ]; then
		echo >&2
		echo "error: the temporary toolchain is incomplete." >&2
		[ -n "$missing" ] && echo "       missing binaries:$missing" >&2
		[ -n "$empty" ] && echo "       installed nothing:$empty" >&2
		echo "       $built package(s) were built in this run, $skipped skipped." >&2
		echo "       Remove ${LFS}${TOOLS} and run stage 1 again; the log above" >&2
		echo "       shows the first package that failed to build." >&2
		exit 1
	fi
	
	TMPPWD=$PWD
	cd $LFS
	rm -f "$TMPPWD/toolchain.tar.xz"
	XZ_DEFAULTS='-T0' tar -cvJpf "$TMPPWD/toolchain.tar.xz" *
	cd $TMPPWD
	
	echo
	_state_complete 1
	echo "toolchain build completed: $built package(s) built, $skipped already present"
}

_compressrootfs() {	
	TMPPWD=$PWD
	cd $LFS
	rm -f "$TMPPWD/lfs-rootfs.tar.xz"
	XZ_DEFAULTS='-T0' tar \
		--exclude='./var/lib/pkg/rejected' \
		--exclude=".$TOOLS" \
		--exclude='./tmp/*' \
		--exclude='./dev/*' \
		--exclude='./sys/*' \
		--exclude='./proc/*' \
		--exclude='./run/*' \
		-cvJpf "$TMPPWD/lfs-rootfs.tar.xz" .
	cd $TMPPWD
	
	echo
	echo "base rootfs is compressed: $TMPPWD/lfs-rootfs.tar.xz"
}

_buildbase() {
	if [ "$(id -u)" != 0 ]; then
		echo "base need to build as root"
		exit 1
	fi
	# stage 3 rebuilds with the base system itself; only the toolchain-backed
	# stages need the shims
	if [ "$1" != rebuild ]; then
		_ensure_toolchain_shims || exit 1
	fi

	_bstage=2
	[ "$1" = rebuild ] && _bstage=3
	_state_summary $_bstage

	if [ -f "$(_state_dir)/stage$_bstage.complete" ]; then
		echo "stage $_bstage: already complete, nothing to do"
		echo "         delete $(_state_dir) to rebuild from scratch"
		return 0
	fi

	if [ ! -f $LFS/var/lib/pkg/db ]; then
		#mknod -m 600 $LFS/dev/console c 5 1 || true
		#mknod -m 666 $LFS/dev/null c 1 3 || true

		cat ports/core/aaa_filesystem/passwd > $LFS/etc/passwd
		cat ports/core/aaa_filesystem/group > $LFS/etc/group

		# pkgutils
		mkdir -p $LFS/var/lib/pkg
		touch $LFS/var/lib/pkg/db
		
		# package and source
		mkdir -p $LFS/$pkgmkpkg
		mkdir -p $LFS/$pkgmksrc
		mkdir -p $packagedir
	fi
	
	# core ports
	rm -rf $LFS/usr/ports/core
	mkdir -p $LFS/usr/ports/core
	cp -r ports/core/* $LFS/usr/ports/core
	
	cp files/pkgin $TOOLS/bin/pkgin
	chmod +x $TOOLS/bin/pkgin
	
	# Nothing in the chroot has a CA bundle until ca-certificates is built
	# (it is near the end of basepkg), and the toolchain's copy is a Mozilla
	# bundle from 2023, so a source pkgmk has to download during stage 2
	# fails with "unable to get local issuer certificate". Install the
	# freshest bundle available and point curl at it below.
	_ca_src=""
	for _ca in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt "$TOOLS/etc/ssl/certs/ca-certificates.crt" "$TOOLS/etc/ssl/cert.pem"; do
		[ -s "$_ca" ] || continue
		_ca_src="$_ca"
		break
	done
	if [ -n "$_ca_src" ]; then
		install -D -m644 "$_ca_src" "$LFS/etc/ssl/certs/bootstrap-ca-bundle.crt"
	fi
	
	# pkgmk
	# gcc keeps its native system headers in $TOOLS/include, so the chroot
	# builds have to add /usr/include themselves. Use -idirafter, not
	# -isystem: libstdc++ headers do "#include_next <stdlib.h>" and gcc loses
	# that lookup when /usr/include was added with -isystem (gcc bug 70129),
	# which is what broke elfutils C++ sources with a missing stdlib.h.
	mkdir -p $LFS/var/lib/pkgmk
	cp ports/core/pkgutils/extension $LFS/var/lib/pkgmk
		# Write both flag sets out. This text is expanded by the shell running
	# bootstrap.sh, and a --resume run reaches basepkg without
	# toolchainpkg having exported CFLAGS here, so "$CFLAGS" would be
	# empty and g++ would compile without -O. elfutils' configure then
	# adds -D_FORTIFY_SOURCE=3 to CXXFLAGS as well as CFLAGS, glibc's
	# features.h warns that fortify needs -O, and elfutils builds C++
	# with -Werror. Keep -std out of CXXFLAGS: gnu17 is a C-only option.
	_bootstrap_flags="-O2 -march=x86-64 -pipe -Wno-error -idirafter /usr/include"
	echo "
export CFLAGS=\"$_bootstrap_flags -std=gnu17\"
export CXXFLAGS=\"$_bootstrap_flags\"
export CPPFLAGS=\"-idirafter /usr/include\"

export JOBS=$(nproc)
export MAKEFLAGS=\"-j \$JOBS\"

PKGMK_SOURCE_DIR=\"/$pkgmksrc\"
PKGMK_PACKAGE_DIR=\"/$pkgmkpkg\"
PKGMK_WORK_DIR=\"/tmp/pkgmk-$name\"

. /var/lib/pkgmk/extension" > $LFS/tmp/pkgmk.conf
	if [ -s "$LFS/etc/ssl/certs/bootstrap-ca-bundle.crt" ]; then
		echo 'export CURL_CA_BUNDLE=/etc/ssl/certs/bootstrap-ca-bundle.crt' >> $LFS/tmp/pkgmk.conf
		echo 'export SSL_CERT_FILE=/etc/ssl/certs/bootstrap-ca-bundle.crt' >> $LFS/tmp/pkgmk.conf
	fi
	
	LFSPATH=/bin:/usr/bin:/sbin:/usr/sbin	
	if [ "$1" != rebuild ]; then
		LFSPATH=$LFSPATH:$TOOLS/bin
	fi
	
	mountfs
	# The toolchain loader's cache is missing on a fresh tree, and stage 2
	# binaries carry that loader, so nothing installed in /usr/lib can be
	# resolved until it exists. Build both caches before the first build.
	_chroot sh -c '[ -x /sbin/ldconfig ] && /sbin/ldconfig' >/dev/null 2>&1 || true
	_chroot sh -c 'if [ -d /tmp/lfs-tools/etc ]; then grep -qx /usr/lib /tmp/lfs-tools/etc/ld.so.conf 2>/dev/null || echo /usr/lib >> /tmp/lfs-tools/etc/ld.so.conf; [ -x /sbin/ldconfig ] && /sbin/ldconfig -f /tmp/lfs-tools/etc/ld.so.conf -C /tmp/lfs-tools/etc/ld.so.cache; fi' >/dev/null 2>&1 || true
	_ensure_chroot_locale
	for i in $basepkg; do
		if [ "$1" != rebuild ]; then
			pkginfo -i -r $LFS | awk '{print $1}' | grep -qx $i && { _state_mark $_bstage "$i"; continue; }
			unset _force
			case $i in
				aaa_filesystem|gcc|bash|dash|perl|coreutils|pkgutils) _force=-f;;
			esac
			_chroot pkgin -d $i -is -if -im -cf /tmp/pkgmk.conf || {
				_state_fail $_bstage "$i"; umountfs
				echo "error: $i failed to build (stage $_bstage)" >&2
				echo "       fix the cause, then resume with: ./bootstrap.sh --resume" >&2
				exit 1
			}
			pkgadd -r $LFS $_force $(ls -1 $packagedir/$i#* | tail -n1) || {
				_state_fail $_bstage "$i"; umountfs
				echo "error: $i failed to install (stage $_bstage)" >&2
				echo "       fix the cause, then resume with: ./bootstrap.sh --resume" >&2
				exit 1
			}
			case $i in
				glibc) cat << EOF > $LFS/tmp/glibc-postinstall
#!/bin/sh
[ -f $TOOLS/bin/ld-old ] && exit 0
mv -v $TOOLS/bin/ld $TOOLS/bin/ld-old
mv -v $TOOLS/$(uname -m)-pc-linux-gnu/bin/ld $TOOLS/$(uname -m)-pc-linux-gnu/bin/ld-old
mv -v $TOOLS/bin/ld-new $TOOLS/bin/ld
ln -sv $TOOLS/bin/ld $TOOLS/$(uname -m)-pc-linux-gnu/bin/ld
gcc -dumpspecs | sed -e "s@$TOOLS@@g" -e "/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}" -e '/\*cpp:/{n;s@\$@ -idirafter /usr/include@}' > \$(dirname \$(gcc --print-libgcc-file-name))/specs
echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose > dummy.log 2>&1
readelf -l a.out | grep ': /lib' > /tmp/adjusttoolchainresult
grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log >> /tmp/adjusttoolchainresult
grep -B1 '^ /usr/include' dummy.log >> /tmp/adjusttoolchainresult
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g' >> /tmp/adjusttoolchainresult
grep "/lib.*/libc.so.6 " dummy.log >> /tmp/adjusttoolchainresult
grep found dummy.log >> /tmp/adjusttoolchainresult
rm -v dummy.c a.out dummy.log
EOF
				_chroot sh /tmp/glibc-postinstall
				_ensure_chroot_locale
				rm -f $LFS/tmp/glibc-postinstall
				;;
			esac
		else
			_chroot prt-get update -fr -if $i || {
				_state_fail $_bstage "$i"; umountfs
				echo "error: $i failed to rebuild (stage $_bstage)" >&2
				echo "       fix the cause, then resume with: ./bootstrap.sh --resume" >&2
				exit 1
			}
		fi
		# pkgadd -r installs into $LFS but cannot run the target's
		# ldconfig, so shared libraries a package just put in /usr/lib stay
		# unknown to the loader and the next build dies on them (binutils'
		# ar needs its own libbfd). Rebuild the cache after each package.
		_chroot sh -c '[ -x /sbin/ldconfig ] && /sbin/ldconfig' >/dev/null 2>&1 || true
		# Binaries linked with the toolchain's gcc use the toolchain's dynamic
		# linker, which reads /tmp/lfs-tools/etc/ld.so.cache and searches
		# /tmp/lfs-tools/lib -- so /usr/lib has to be registered there too, or
		# the freshly installed binutils cannot load its own libbfd.
		_chroot sh -c 'if [ -d /tmp/lfs-tools/etc ]; then grep -qx /usr/lib /tmp/lfs-tools/etc/ld.so.conf 2>/dev/null || echo /usr/lib >> /tmp/lfs-tools/etc/ld.so.conf; [ -x /sbin/ldconfig ] && /sbin/ldconfig -f /tmp/lfs-tools/etc/ld.so.conf -C /tmp/lfs-tools/etc/ld.so.cache; fi' >/dev/null 2>&1 || true
		_state_mark $_bstage "$i"
	done
	umountfs
	
	_state_complete $_bstage
	echo
	echo "base system build completed"
}

mountfs() {
	# unmount first incase already mounted
	umountfs
	mkdir -p $LFS/dev $LFS/run $LFS/proc $LFS/sys
	mount --bind /dev $LFS/dev
	mount -t devpts devpts $LFS/dev/pts -o gid=5,mode=620
	mount -t proc proc $LFS/proc
	mount -t sysfs sysfs $LFS/sys
	mount -t tmpfs tmpfs $LFS/run
	if [ -h $LFS/dev/shm ]; then
	  mkdir -p $LFS/$(readlink $LFS/dev/shm)
	fi
	mkdir -p $LFS/$pkgmksrc $LFS/$pkgmkpkg
	mount --bind $sourcedir $LFS/$pkgmksrc
	mount --bind $packagedir $LFS/$pkgmkpkg
}

umountfs() {
	unmount $LFS/dev/pts
	unmount $LFS/dev
	unmount $LFS/run
	unmount $LFS/proc
	unmount $LFS/sys
	unmount $LFS/$pkgmkpkg
	unmount $LFS/$pkgmksrc
}

unmount() {
	while true; do
		mountpoint -q $1 || break
		umount $1 2>/dev/null
	done
}

export LFS="${LFS:-/tmp/lfs-rootfs}"
export TOOLS="${TOOLS:-/tmp/lfs-tools}"
# libarchive's bsdtar translates the UTF-8 pathnames in a pax archive into
# the current charset and refuses to extract when that charset is ASCII.
# gcc's tarball has a few non-ASCII pathnames, so extraction needs a UTF-8
# locale; everything else keeps byte-order determinism either way.
export LC_ALL=C
# Test against the locale(1) that the toolchain binaries will use: their
# own glibc only knows the locales generated into $TOOLS/lib/locale, and the
# host's list says nothing about those.
_lcbin=locale
[ -x "$TOOLS/bin/locale" ] && _lcbin="$TOOLS/bin/locale"
for _loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
	if LC_ALL=$_loc "$_lcbin" charmap >/dev/null 2>&1; then
		export LC_ALL=$_loc
		break
	fi
done
[ "$LC_ALL" = C ] && echo "stage: warning: no UTF-8 locale - bsdtar cannot extract archives with non-ASCII pathnames" >&2
export PATH=$TOOLS/bin:$PATH

# zlib, xz and zstd sit before python on purpose: python builds its zlib,
# bz2, lzma and zstd modules in stage 1 and needs zlib.h, lzma.h and zstd.h
# from the temporary toolchain (bzip2 already provides bzlib.h). Anything
# after python is simply not visible to its configure.
toolchainpkg="binutils-pass1 gmp mpfr mpc gcc-pass1 linux-headers glibc gcc-pass2 binutils-pass2 libxcrypt gcc-pass3 m4
	ncurses bash bison bzip2 coreutils diffutils file findutils gawk gettext grep gzip make patch perl pkgconf zlib xz zstd python
	sed tar texinfo openssl ca-certificates curl libarchive"
	
basepkg="aaa_filesystem linux-headers man-pages glibc tzdata zlib bzip2 xz file ncurses readline m4 bc binutils libxcrypt
	gmp mpfr mpc attr acl shadow gcc pkgconf libcap sed psmisc iana-etc bison flex pcre2 grep bash dash
	libtool gdbm gperf expat inetutils perl perl-xml-parser intltool autoconf automake openssl kmod gettext elfutils
	libffi sqlite python coreutils check diffutils gawk findutils groff less gzip zstd iptables libtirpc iproute2 kbd
	libpipeline make patch man-db tar texinfo vim procps-ng util-linux e2fsprogs sysklogd eudev which
	libarchive ca-certificates curl pkgutils prt-get httpup ninja meson linux-pam ports prt-utils openrc openrc-init-scripts signify"

sourcedir="${SOURCEDIR:-$PWD/sources}"
packagedir="${PACKAGESDIR:-$PWD/packages}"
pkgmkpkg="var/cache/pkg/packages"
pkgmksrc="var/cache/pkg/sources"

if [ ! "$1" ]; then	
	cat << EOF
Usage:
  $0 <options>
  
Options:
  1  build temporary toolchain
  2  build base system (using temporary toolchain)
  3  rebuild base system (using final system toolchain itself)
  4  compress base rootfs
EOF
	exit 0
fi
	
case $1 in
	1) _buildtoolchain;;
	2) _buildbase;;
	3) _buildbase rebuild;;
	4) _compressrootfs;;
esac

exit 0
