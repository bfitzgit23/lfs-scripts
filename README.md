# lfs-scripts

This repo contain scripts to automate LFS (Linux From Scratch) build, manage, updates, rolling and etc. Yeah its bunch of scripts. Its basically almost whole tools to maintain a Linux distribution. These what I use on my main system as daily use on my main computer. If you want to use LFS as main OS and be able to maintain it, you can use it. But keep in mind, these scripts is not 100% follow LFS, because thats the main point of LFS, you build it yourself and customize it as you want. Your distro your rules, but this one follow my rules.

Heres is important point of `lfs-scripts` that follow my rules;

- bootstrap using [LFS v9.1](https://linuxfromscratch.org/lfs/view/9.1/) way.
- multilib. all 32bit libraries is thrown into `/usr/lib32` directory.
- using [CRUX's pkgutils](https://crux.nu/gitweb/?p=tools/pkgutils.git) to build packages from ports + my own extension script.
- using [CRUX's prt-get](https://crux.nu/gitweb/?p=tools/prt-get.git) to manage packages and dependencies.
- writing port is damn easy, a very minimal port only required url to source tarball, compiling is automatically handled.
- dependencies handled by prt-get.
- `/usr/libexec/` not use, use `/usr/lib/` instead.
- use `runit` as main init by default.
- consolekit2 is used instead of elogind.
- no systemd stuff.

So there, my rules. If you encounter error or bugs when using `lfs-scripts`, open issue here, dont report to LFS dev, they just gonna ignore you.

# bunch of scripts
So i will explain most of these scripts does, else you have to read on top of each script of what it does and how to use it.

## bootstrap.sh
Like its name, this script is to bootstrap main system of LFS. Theres a few stages to bootsrap base system:
```
1 - build temporary toolchain
2 - build base system (using temporary toolchain)
3 - rebuild base system (without depending on temporary toolchain)
4 - compress base rootfs
```

Stage 1 need to run as regular user to build temporary toolchain. Temporary toolchain is build inside `/tmp` directory so, when reboot, your system might wipe completely the toolchain. But dont worry, at the end of stage 1 the temporary toolchain will get compress as backup incase you wanna reuse it.
```
$ ./bootstrap 1
```

Stage 2 need to run as root to build base LFS system. You can use `sudo` or `doas`. Also, base LFS system is build inside `/tmp` directory, and also, you can compress LFS base system to use it anytime you want without bootstrap again.
```
# ./bootstrap 2
```

Stage 3 also need to run as root to rebuild base system. This stage is completely optional if you wanna skip it. This stage is rebuild base without using temporary toolchain that build on stage 1, but it use its own toolchain instead. Its not in any LFS book but this is my way to make sure my base system is working completely. So if everything is rebuild fine, then i'm assure you that your LFS system is working 100%.
```
# ./bootstrap 3
```

Stage 4 is for compressing your base system into `lfs-rootfs.tar.xz` file, temporary toolchain is excluded. See installing from existing tarball below.
```
$ ./bootstrap 4
```

Okay thats all for bootstrapping LFS base. Just keep `lfs-rootfs.tar.xz` to reuse in the future or share with your friends.

# install to disk
First thing to do is making partition and mount it but i will not teach it here, i assume you already know if you come for LFS stuff. I assume you mount the partition into `/mnt/lfs` directory.

Extract compressed base file system into `/mnt/lfs`
```
# tar -xvf lfs-rootfs.tar.xz -C /mnt/lfs
```

Chroot into new extracted system
```
# mount --bind /dev /mnt/lfs/dev
# mount -t devpts devpts /mnt/lfs/dev/pts -o gid=5,mode=620
# mount -t proc proc /mnt/lfs/proc
# mount -t sysfs sysfs /mnt/lfs/sys
# mount -t tmpfs tmpfs /mnt/lfs/run
# test -h /mnt/lfs/dev/shm && mkdir -p /mnt/lfs/$(readlink /mnt/lfs/dev/shm)
(UEFI)
# mkdir -p /mnt/lfs/boot/efi
# mount /dev/<efi partition> /mnt/lfs/boot/efi

# chroot /mnt/lfs env PS1="(chroot)# " /bin/bash
```

Setting hostname
```
# echo myhostname > /etc/hostname
```

Setting timezone (change XXX and YYY to your choice of timezone)
```
# ln -svf /usr/share/zoneinfo/XXX/YYY /etc/localtime
```

Setting user and password
```
# useradd -m -G users,wheel,audio,video -s /bin/bash <your user>
# passwd <your user>
```

Setting locales
```
# vim /etc/locales
# genlocales
# echo "LANG=xx_YY.UTF-8" > /etc/locale.conf
```

Setting /etc/fstab
```
# echo '/dev/sdXY / ext4 defaults 0 1' >> /etc/fstab
# echo '/dev/sdXY swap swap defaults 0 0' >> /etc/fstab
```

Sync ports
```
# ports -u
```

Install grub
```
(BIOS)
# prt-get depinst grub
# grub-install /dev/sdX

(UEFI)
# prt-get depinst grub-efi
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LFS-GRUB

# grub-mkconfig -o /boot/grub/grub.cfg
```

You might wanna install packages before rebooting to your installed lfs like 'xorg', 'networkmanager'?
```
# prt-get depinst xorg lxdm lxde networkmanager
```

Enable some needed services
```
# ln -sv /etc/sv/dbus /var/service
# ln -sv /etc/sv/networkmanager /var/service
# ln -sv /etc/sv/lxdm /var/service
```

You can run 'prt-get' to see the options on how to use it
```
# prt-get help
```

You can reboot now
```
# exit
# reboot
```

# runit
`lfs-scripts` is use `runit` as default init. Basically the initscripts is almost same as the one used in Void Linux, so no need headache to figure out how to use it. I will point some important point of `runit` used:
- theres no runit config file (/etc/runit/rc.conf)
- to enable service, just make symlink from `/etc/sv/<service>` to `/var/service`
- ...

# writing ports
Writing ports is so damn easy, you can learn from existing ports or use `gentemplate.sh` script to generate a very basic port. 

Change to `contrib` directory to make new port. If you want to contribute your port, add it to `contrib` directory then make PR.
```
$ cd ports/contrib
$ ../gentemplate.sh http://dl.suckless.org/dwm/dwm-6.4.tar.gz
# Depends on: 

name=dwm
version=6.4
release=1
source=(http://dl.suckless.org/${name}/${name}-${version}.tar.gz)
```

Here you can see port created for dwm (dwm/Pkgfile). Now lets build it. Always build new ports using fakeroot to make sure port not broken and pollute the system.
```
$ cd dwm
$ fakeroot pkgmk
...
=======> Build result:
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/bin/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/share/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/share/man/
drwxr-xr-x  0 root   root        0 Nov 19 00:45 usr/share/man/man1/
-rw-r--r--  0 root   root     1874 Nov 19 00:45 usr/share/man/man1/dwm.1.gz
-rwxr-xr-x  0 root   root    56608 Nov 19 00:45 usr/bin/dwm
=======> WARNING: Footprint not found, creating new.
=======> Building '/var/cache/pkg/packages/dwm#6.4-1.pkg.tar.xz' succeeded.
```
When package is built, you can install it as root.
```
$ sudo pkgmk -i
```
Ok then the package is installed.

Here is `Pkgfile` with all options available to use:
```
# dependencies
# Depends on: pkg1 pkg2 pkg3

# port's name, make sure same as port directory
name=dwm

# port's version
version=6.4

# port's release, used for bump package, start with '1'. Always revert back to '1' when 'version=' is updated.
release=1

# port's source url, patch and needed files
source=(http://dl.suckless.org/${name}/${name}-${version}.tar.gz examplepatch.patch)

# for runit services, you can use 'run' or '<name>.run' and 'finish' or '<name>.finish' to install service into '/etc/sv/<name>/run' or '/etc/sv/<name>/finish'
# use '<name>.file' to install into '/etc/sv/<name>/file'
# use 'file' to install into '/etc/sv/<port name>/file'
# this runit files required in 'source=()' array
sv=(run finish name.run name.finish conf)

# by default build type is automatically detected but you can force it to use certain build type
# available build type is: meson_build, configure_build, cmake_build, python3_build, makefile_build and perlmodule_build
build_type=

# by default common build opts is already set, use this to add extra build opts
build_opt="-Denablethis=yes -Ddisablethat=no"

# patch (*.patch and *.diff files) is automatically applied using '-Np1' option.
# use this to use other patch options
patch_opt=""

# use this to keep static libraries (*.a)
keep_static=1

# use this to keep libtool files (*.la)
keep_libtool=1

# use this to keep locale files (/usr/share/locale/??)
keep_locale=1

pre_build() {
  # executed before package is build. Eg:
  ./autogen.sh
}

post_build() {
  # executed after package is built. Eg:
  mv -v $PKG/etc/X11/xinit/xinitrc.d/90-consolekit \
    $PKG/etc/X11/xinit/xinitrc.d/90-consolekit.sh
}

pre_build() {
  # this is replacement for regular 'build()' function.
  # if this function is used, both 'pre_build()' and 'pre_build()' is completely ignored.
  ./autogen.sh
  ./configure --prefix=/usr
  make
  # DESTDIR=$PKG is needed, but sometimes not, already handled by automated extension script
  # thats why build package using fakeroot very recommended for new ports
  make install
}
```

Thats some explanation for writing ports. For unused options, remove it. Keep it simple!.

Since the package manager and some utilities is used from CRUX, you can check CRUX wiki for extra info: https://crux.nu/Wiki/HomePage

# lfs-scripts 2026 refresh

This tree now also carries an interactive installer front-end, the ISO builder
and installer script, artwork, and the scratchpkg package set converted to
CRUX `Pkgfile` recipes for `pkgutils`/`prt-get`.

## Interactive bootstrap (ncurses + dialog)

`bootstrap.sh` is a `dialog`/`whiptail` front-end over the original build logic,
which now lives unchanged in `files/bootstrap-core.sh`:

```sh
./bootstrap.sh              # menu: toolchain, base system, rebuild, compress, settings
./bootstrap.sh 1            # scripted: temporary toolchain (regular user)
./bootstrap.sh 2            # scripted: base system (root)
./bootstrap.sh --settings   # edit and save settings to bootstrap.conf
./bootstrap.sh --text       # same menu with plain-text prompts
```

Settings are read from the environment first, then `bootstrap.conf`:

| Variable | Meaning | Default |
| --- | --- | --- |
| `LFS` | installation root | `/tmp/lfs-rootfs` |
| `TOOLS` | temporary toolchain | `/tmp/lfs-tools` |
| `SOURCEDIR` | source cache | `./sources` |
| `PACKAGESDIR` | package cache | `./packages` |
| `BFS_JOBS` | parallel build jobs | `nproc` |

Every stage is logged to `logs/bootstrap-<timestamp>-stage<N>.log`.

## LFS 13.1

`ports/core` is pinned to the Linux From Scratch 13.1 package set (SysV
initscripts, no systemd), including the 13.1 toolchain: binutils 2.47,
gcc 16.2.0, glibc 2.44, coreutils 9.11, bash 5.3 and the rest of
the 13.1 list. The kernel and its headers are pinned ahead of the book at
7.3.4 (`v7.x` tarballs). The reference list used for the bump is kept at
`tools/lfs-13.1-wget-list`, and `tools/update-lfs-versions.sh <list> <portsdir>`
can re-apply a version map after a book update.

## scratchpkg ports converted to Pkgfiles

`ports/scratch/` contains the scratchpkg (spkgbuild) package set from
stormfs-linux converted to CRUX `Pkgfile` recipes:

- `tools/spkgbuild2pkgfile.sh` performs the conversion
  (`spkgbuild` -> `Pkgfile`, CRLF stripped, the redundant `cd $name-$version`
  removed because `pkgmk` already runs there, empty `backup`/`noextract`
  dropped). `build_opt` and everything else is kept, so multi-line arrays and
  quoted strings stay intact.
- Categories are preserved (`core`, `extra`, `contrib`, `multilib`,
  `compat-32`, `compiz`, `gnome`, ...), so a port is
  `ports/scratch/<category>/<port>/Pkgfile`.
- All 1429 recipes pass `bash -n`; `ports/scratch/CONVERSION-NOTES.md` records
  what the conversion strips and lists no exceptions.
- Recipes keep scratchpkg's `build()` bodies, including their sourcing of
  `/usr/share/bfsos/spkgbuild.helper`. Building them with `pkgmk` needs that
  helper installed, or the helper calls replaced with explicit commands.
- Use them with `prt-get`: `etc/prt-get.conf` in this repository lists every port
  tree in search order, ready to install as /etc/prt-get.conf.

## ISO builder and installer

- `iso-builder/` builds a bootable ISO from the finished rootfs
  (`mkiso.sh`, `files/`, `liverootfs/`, `run_qemu`).
- `scripts/install-lfs-menu.sh` is the menu-driven installer, adapted from the
  stormfs-linux installer for lfs-scripts naming and paths.

## Artwork and submodules

- `assets/wallpapers/` - the LFS wallpapers.
- `assets/themes/` - the theme/icon/wallpaper pack and the LFS1 wallpaper set.
- Submodules: `.oh-my-bash`, `StormFS-grub-theme`, `adw-gtk3`,
  `tela-icon-theme`, `tela-circle-icon-theme`, `scratchpkg`.
  Initialise with `git submodule update --init --recursive`.

## Upstream port trees (venomlinux) and chromium-bin

`tools/sync-venom-ports.sh [repo ...]` clones or updates the venomlinux port
trees into `$VENOM_SRC` (default `/tmp/venom`) and converts every `spkgbuild`
into a CRUX `Pkgfile` at:

```
ports/scratch/venom-<repo>/<port>/Pkgfile
```

with the trees `core`, `extra`, `nonfree`, `multilib`, `kde-lxqt`, `mate` and
`xfce`. The `venom-` prefix keeps them apart from the existing
`ports/scratch/<category>` trees, which come from the stormfs port set. Each
port's `depends` file becomes a `# Depends: a b c` header line, which is how
`prt-get` reads dependencies from a Pkgfile.

`s6-services` ships service definitions rather than ports (no `spkgbuild`
files), so it is vendored under `assets/s6-services/`.

`chromium-bin` (prebuilt Chromium) is the port at
`ports/scratch/opt/chromium-bin`, converted from the stormfs `ports/opt` tree.

## Config files

- `etc/scratchpkg.conf` - scratchpkg global options plus the list of port trees
  this repository provides, with the upstream each tree comes from.
- `etc/scratchpkg.repo` - the same trees in scratchpkg's own repo format
  (`<repo dir> <repo url> [branch]`) for `portsync`.
- `ports/multilib` versions are kept in step with the venomlinux `multilib`
  tree; `ports/multilib/REPO` marks the tree for `prt-get`.

## prt-get configuration and duplicate pruning

`etc/prt-get.conf` lists every port tree with a `prtdir` line, in search order:

```
prtdir /usr/ports/core
prtdir /usr/ports/extra
prtdir /usr/ports/contrib
prtdir /usr/ports/multilib
prtdir /usr/ports/scratch/venom-core
...
```

Port names are unique across the whole repository (2837 ports, 0 duplicates).
`ports/opt` used to be spkgbuild-only, which is why it was absent from the
prt-get configuration; it is now a native Pkgfile tree with a `prtdir` line of
its own.
Where a name appeared in more than one tree, the prune kept the copy from the
highest-precedence tree and removed the rest:

1. `ports/core`, `ports/extra`, `ports/contrib`, `ports/multilib`, `ports/opt`
   - the distribution.s own ports: core/extra/contrib/multilib pinned to LFS
   13.1, plus `ports/opt` converted from the stormfs spkgbuild set (306 ports,
   including `chromium-bin`);
2. `ports/scratch/venom-*` - the maintained upstream trees, whose recipes are
   plain `Pkgfile` shell without the scratchpkg helper;
3. the remaining imported `ports/scratch/*` trees - the older scratchpkg port
   set, kept for the ports nothing else provides.

`ports/PRUNED-PORTS.txt` records every removed path with that rule, and a
removed port can be recovered with `git log --diff-filter=D -- <path>`.

## The spkgbuild helper and why no recipe needed rewriting

234 recipes in this repository call into `/usr/share/bfsos/spkgbuild.helper`
inside `build()`, almost always as:

```sh
build() {
    . /usr/share/bfsos/spkgbuild.helper || return 1
    _bfs_src=$(find . -mindepth 1 -maxdepth 1 -type d -iname "$name-$version" -print -quit)
    cd "$_bfs_src" || return 1
    bfs_autobuild
}
```

The helper is not missing: it is a port in this tree.
`ports/scratch/core/bfs-spkgbuild-macros` ships `helper.sh` and installs it to
`/usr/share/bfsos/spkgbuild.helper`. It is plain POSIX shell and only reads
`$SRC`, `$PKG`, `$name`, `$version`, `$build_opt` and `$CFLAGS`, all of which
`pkgmk` provides, so it runs unchanged under `pkgutils`.

Two things were wrong and are now fixed:

* the converted port directory held only `Pkgfile`, so `source=(helper.sh)` had
  no file to install. `helper.sh` is now part of the port and the source line is
  an array, as `pkgutils` expects;
* nothing declared the dependency, so nothing guaranteed the helper was
  installed before a recipe tried to source it. All 234 recipes now carry
  `bfs-spkgbuild-macros` in their `# Depends:` header, so
  `prt-get depinst <port>` installs the helper first.

That is the whole fix - one file plus a dependency line per recipe. Rewriting
234 `build()` bodies would have replaced a tested helper with 234 untested
reimplementations. Only two recipes touched the source line without ever
calling a helper function (`engrampa`, `pidgin`); that line is gone from those.

Patch files and other per-port assets referenced by local name were also
missing from the converted trees, since the first conversion copied only
`Pkgfile`s. They are now copied in (262 files); the references that remain
without a local file are all remote URLs that `pkgmk` downloads itself.

### Stage 2 fails with `chroot: failed to run 'env': No such file or directory`

`chroot` needs an `env` binary *inside* the new root, and a fresh rootfs has
none. Stage 2 therefore links a handful of toolchain binaries into the rootfs
first, including `/usr/bin/env` -> `$TOOLS/bin/env`.

Two things used to break that:

* the links were only created when `$LFS/var/lib/pkg/db` did not exist, so an
  aborted stage 2 (which creates the db) made every later run skip them;
* if the temporary toolchain was gone — `/tmp` is a tmpfs on most systems, so a
  reboot after stage 1 clears it — the run died with that `chroot` error instead
  of saying what was actually missing.

The links are now recreated on every stage 2 run, and stage 2 checks for
`$LFS$TOOLS/bin/env` up front and stops with an explicit message. If you see
that message, the toolchain is gone and stage 1 has to run again; keep `LFS` and
`TOOLS` on a real filesystem (not `/tmp`) if you want them to survive a reboot.

### Stage 1 stops at gmp: `checking whether the C compiler works... no`

`gmp`, `mpfr`, `mpc` and `gcc-pass1` carry no `build()` of their own; they fall
back to `./configure --prefix=$TOOLS` and are compiled by the **host** compiler,
because there is no cross compiler yet. Stage 1 has `$TOOLS/bin` first on PATH
and binutils-pass1 has just filled it, so the host gcc could pick up those
`as`/`ld` instead of its own and fail its link test - which is exactly what
`could not find a working compiler` reports.

Those packages now build with `PATH` rewritten so `$TOOLS/bin` comes last and
with `CC`/`CXX` pinned to the host compiler (`gcc`/`g++` found outside
`$TOOLS/bin`). Stage 1 prints the host compiler and the path it uses, and stops
with a clear message if no host compiler exists at all.

Stage 1 now also test-compiles a trivial program with the chosen host compiler
before building anything, prints the assembler and linker it will use, and runs
host-native builds with `CFLAGS`, `CXXFLAGS`, `CPPFLAGS`, `LDFLAGS`, `CC`,
`CXX`, `CPP` and `LD` unset so a stale value in your shell cannot poison every
configure probe. If the compiler cannot build that program, stage 1 stops and
prints gcc's own error.

### gmp / mpfr / mpc: `could not find a working compiler` on gcc 15+

gmp 6.3.0's configure probes contain

```c
void g(){}
...
g(i,d[i].src,d[i].n,got,d[i].want,9);
```

an empty parameter list, which in C23 means `(void)`. gcc 15 and later default to
C23, so the probe fails to compile with `too many arguments to function 'g'` and
configure reports a missing compiler even though the toolchain is fine.

Stage 1 builds the pre-toolchain packages with `CFLAGS="-O2 -std=gnu17"`, and the
base system builds with `-std=gnu17` appended to `CFLAGS` for the same reason.

### Source mirrors

Downloads must come from hosts the build machine can reach:

- LFS 13.1 packages: `https://ftp.osuosl.org/pub/lfs/lfs-packages/13.1/`
- GNU packages not in the 13.1 set: `https://mirrorservice.org/sites/ftp.gnu.org/gnu/`
  (fallbacks used while verifying: `ftp.nluug.nl/pub/gnu/`,
  `mirrors.dotsrc.org/gnu/`, `ftp.funet.fi/pub/gnu/`)

`ftp.gnu.org`, `ftpmirror.gnu.org` and `mirrors.kernel.org` are unreachable from
the build host, and `https://ftp.osuosl.org/pub/gnu/` hangs there even though it
answers elsewhere. When bumping a version, check the new URL with
`curl -sIL -o /dev/null -w '%{http_code}' <url>` before committing.

## Resume / restore

Every package that finishes is recorded in `$LFS/var/lib/lfs-scripts`:

```
stage1.done          one completed package name per line
stage1.failed        the package the last run died on (removed on progress)
stage1.complete      timestamp, written when the stage finished
stage2.done/...      same, for the base system (stage3.* for rebuild)
```

Re-running a stage skips anything already recorded, so an interrupted toolchain
or base build continues instead of starting over:

```sh
./bootstrap.sh --resume        # reruns the stage that is not complete
./bootstrap.sh 1               # or rerun a stage directly
```

The toolchain stage also keeps `/tmp/lfs-pkg` when a package fails, so the
packages built before the failure are still there when you resume. Delete
`$LFS/var/lib/lfs-scripts` to start a stage from scratch.

## binutils: `'PATH_MAX' undeclared`

`binutils 2.47`'s `ld/ldmain.c` uses `PATH_MAX` inside

```c
#if defined (__linux__) && _POSIX_VERSION >= 200112L
  char name[PATH_MAX];
```

but includes neither `<limits.h>` nor any header that reaches it, and glibc 2.44
no longer provides it transitively. `ports/core/binutils/path_max.patch` adds
the include with a `4096` fallback, and the port applies it before configuring.

### libxcrypt: `initialization discards 'const' qualifier`

libxcrypt 4.5.2 compiles with `-Werror`, and its

```c
char *hptr = strchr ((const char *) intbuf->retval + 3, '$');
```

is fine in C17 but not in C23, where `strchr` returns `const char *` for a const
argument. gcc 15+ defaults to C23, so stage 1 now builds every package with
`CFLAGS="-O2 -std=gnu17 -Wno-error"`, and the base system's `pkgmk.conf` uses
the same policy (`-std=gnu17 -Wno-error`). The C17 flag is the actual fix; the
`-Wno-error` is belt and braces for other packages that ship `-Werror`.

### Where resume state lives, and /tmp

State is under `$LFS/var/lib/lfs-scripts`. The default `LFS` is
`/tmp/lfs-rootfs`, and on many systems (Gentoo included) `/tmp` is tmpfs, so a
reboot wipes both the toolchain and the record of what was built — nothing can
be resumed across a reboot in that case. Put `LFS` on a real filesystem if you
want resume to survive one. `./bootstrap.sh --status` prints the current state.

## Compiler flag policy, and what the ports sweep found

Stage 1 exports and stage 2 writes `pkgmk.conf` with:

```
CFLAGS="-O2 -std=gnu17 -Wno-error"            # stage 1 (plus -march/-pipe in 2)
CXXFLAGS="$CFLAGS"
```

C17 is the substance: gcc 15+ defaults to C23, where `strchr()` returns a const
pointer (libxcrypt), an empty parameter list means `(void)` (gmp's configure
probes) and old-style definitions are gone. `-Wno-error` covers packages that
compile with `-Werror` (libxcrypt); Automake puts `$(CFLAGS)` last on the
compile line, so it overrides `AM_CFLAGS`' `-Werror`.

Swept all `ports/**/Pkgfile` for the three ways that policy can be defeated:

| pattern | hits | state |
|---|---|---|
| `Werror` in a recipe | 19 | all already neutralise it (`--disable-gcc-Werror`, `sed -i 's/-Werror//'`, or an upstream patch); none is in stage 1/2 |
| `CFLAGS=`/`CXXFLAGS=` that drop the inherited value | 13 | only `ports/core/bc` was in a stage-1/2 set; fixed to append `-std=gnu99` instead of replacing with `-std=c99` |
| `-std=` forced by a recipe | 16 | bc (fixed), cdrtools `-std=gnu89`, texlive `-std=gnu17`, protobuf-c and the KDE4/Qt ports `-std=c++*`; none of these is in stage 1/2 |

### The one package that must *not* be built as C17: gcc itself

`ports/core/gcc/Pkgfile` strips `-std=` from `CFLAGS`/`CXXFLAGS` before it
builds (`gcc_default_std`), keeping `-O2` and `-Wno-error`. gcc 16's own tree is
written for the standard the compiler defaults to: `gcc/config/i386/i386.h:1723`
declares `bool preserve_none_abi;` without including `<stdbool.h>`, which only
compiles where `bool` is a keyword (C23). With `-std=gnu17` the target libgcc
fails in stage 1:

```
i386.h:1723:3: error: unknown type name 'bool'
```

Dropping the override rather than adding `-include stdbool.h` is deliberate: it
also restores any other C23 feature gcc's sources rely on, and it works with
older host compilers (which simply default to an older standard).

Re-run the sweep after bumping versions:

```sh
grep -rn 'Werror' ports --include=Pkgfile
grep -rn 'CFLAGS="[^$]\|CXXFLAGS="[^$]' ports --include=Pkgfile
grep -rn '\-std=' ports --include=Pkgfile
```

### gettext and a non-GNU `emacs`

gettext installs Emacs Lisp support (`gettext-tools/emacs/Makefile`) and
byte-compiles it during `make` with `$(EMACS) --batch --no-site-file` whenever
configure found an `emacs` on `PATH`. If that `emacs` is not GNU Emacs (a
wrapper script, `mg`, an alias) it fails with:

```
emacs: invalid option -- '-'
```

Both gettext builds now pass `--without-emacs` (gettext-tools/configure.ac's
documented switch, which sets `EMACS=no`), so the byte-compile and
`install-lispLISP` rules become unconditional no-ops. po-mode is a developer
convenience, not something a bootstrap or a base system needs.
