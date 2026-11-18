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
- use `openrc` as main init by default (ports can still ship runit service files with `sv=()`).
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

# chroot /mnt/lfs env PATH=/usr/sbin:/usr/bin:/sbin:/bin PS1="(chroot)# " /bin/bash
```

`PATH` is set explicitly here: `/usr/sbin` holds `useradd`, `passwd` and the
other shadow tools, and the host environment a chroot inherits rarely has it.

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

# openrc
`lfs-scripts` boots with OpenRC: `/sbin/init` is a symlink to `openrc-init`,
which reads `/etc/inittab` for the `sysinit`, `boot` and `default` states plus
the console gettys. Two ports provide it, both in `ports/core` so the stage 2
chroot can build them:

- `openrc` 0.63 - built with meson; installs `/sbin/openrc-init`, `/etc/inittab`
  and the standard runlevel links OpenRC ships (`sysinit`: cgroups, devfs,
  dmesg, sysfs; `boot`: bootmisc, fsck, hostname, localmount, loopback, root,
  swap, sysctl, binfmt, hwclock, keymaps, modules, mtab, procfs, save-keymaps,
  save-termencoding, seedrng, termencoding; `default`: local, netmount;
  `shutdown`: savecache, killprocs, mount-ro). Its `pre_build` drops `-std=`
  from `CFLAGS`: `meson.build` pins `c_std=c99`, and the bootstrap's
  `-std=gnu17` is appended after it, which re-enables GCC's predefined `unix`
  macro and breaks the `struct sockaddr_un unix` member in `src/shared/misc.c`.
- `openrc-init-scripts` - `/etc/init.d` scripts for eudev and the optional
  daemons (sshd, cups, networkmanager, sddm, ...), plus a `sysklogd` script for
  the logger `basepkg` installs. It enables `udev` in `sysinit` and
  `udev-postmount` and `sysklogd` in `default`.

Manage services the usual way:
```
# rc-update add sshd default
# rc-service sshd start
```

`runit` and `runit-rc` are still in the tree, and a port can still install
runit service files with `sv=()` (see below), but a fresh bootstrap no longer
installs them.
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
trees into `$VENOM_SRC` (default `/tmp/venom`), converts every `spkgbuild` into
a CRUX `Pkgfile`, and imports the recipes into the local trees:

```
core, extra, multilib             -> ports/{core,extra,multilib}
nonfree, mate, xfce, kde-lxqt, s6 -> ports/{nonfree,mate,xfce,kde-lxqt,s6}
```

There are no `venom-*` trees: the 2,418 upstream recipes live in the local
collections (1,639 imported). A recipe is only imported when no local tree
already provides that name - the local copy is the distribution's own (LFS 13.1
pins, the source-mirror patches), and a second copy would change which recipe
`prt-get` resolves. The 779 names the local trees already provided were left
alone. Each port's `depends` file becomes a `# Depends: a b c` header line,
which is how `prt-get` reads dependencies from a Pkgfile. The remaining
`ports/scratch/<category>` trees still come from the stormfs port set.

`s6-services` ships service definitions rather than ports (no `spkgbuild`
files), so it is vendored under `assets/s6-services/`.

`chromium-bin` (prebuilt Chromium) is the port at
`ports/scratch/opt/chromium-bin`, converted from the stormfs `ports/opt` tree.

## Config files

- `etc/scratchpkg.conf` - scratchpkg global options plus the list of port trees
  this repository provides, with the upstream each tree comes from.
- `etc/scratchpkg.repo` - the same trees in scratchpkg's own repo format
  (`<repo dir> <repo url> [branch]`) for `portsync`.
- `etc/ports/*.httpup` - one httpup collection per port tree, installed to
  `/etc/ports/` by the `ports` package; the canonical copies ship in
  `ports/core/ports/` and `etc/ports/` mirrors them.
- `ports/multilib` versions are kept in step with the venomlinux `multilib`
  tree; `ports/multilib/REPO` marks the tree for `prt-get`.

### Synchronising the collections with `ports -u`

Every tree is published as an httpup collection: `ports/core/ports/<tree>.httpup`
(mirrored in `etc/ports/`) sets

```
ROOT_DIR=/usr/ports/<tree>
URL=https://raw.githubusercontent.com/bfitzgit23/lfs-scripts/master/ports/<tree>
```

`httpup` only fetches what a tree's `REPO` index lists, so after changing ports
run `ports/repgen.sh <tree> ...` (a wrapper around `httpup-repgen`) and commit
the regenerated `ports/<tree>/REPO` together with the change.

The venomlinux collections travel the other way, over git:
`/etc/ports/venom-<collection>.git` clones into `/usr/ports/venom-<collection>`
with `/etc/ports/drivers/git`. Those trees only ship `spkgbuild` recipes, so the
driver converts every `spkgbuild` to a `Pkgfile` after the update (`build()`
becomes `pkg_build()`, the `cd $name-$version` goes away, a `depends` file
becomes a `# Depends:` header) - prt-get only reads Pkgfiles. `etc/prt-get.conf`
lists the venom trees after all local ones, so wherever both provide a name the
local recipe still wins.

## prt-get configuration and duplicate pruning

`etc/prt-get.conf` lists every port tree with a `prtdir` line, in search order:

```
prtdir /usr/ports/core
prtdir /usr/ports/extra
prtdir /usr/ports/contrib
prtdir /usr/ports/multilib
prtdir /usr/ports/opt
prtdir /usr/ports/nonfree
...
```

Port names are unique across the ten local trees (2,598 ports, 0 duplicates
between them). `ports/opt` used to be spkgbuild-only, which is why it was absent
from the prt-get configuration; it is now a native Pkgfile tree with a `prtdir`
line of its own, and `ports/nonfree`, `ports/mate`, `ports/xfce`,
`ports/kde-lxqt` and `ports/s6` hold the venomlinux collections of those names.
Where a name is provided by more than one source, the copy from the
highest-precedence source was kept and the rest were removed:

1. `ports/core`, `ports/extra`, `ports/contrib`, `ports/multilib`, `ports/opt`
   - the distribution's own ports: core/extra/contrib/multilib pinned to LFS
   13.1, plus `ports/opt` converted from the stormfs spkgbuild set (304 ports,
   including `chromium-bin`);
2. the venomlinux recipes imported into those trees and into
   `ports/{nonfree,mate,xfce,kde-lxqt,s6}` - plain `Pkgfile` shell without the
   scratchpkg helper;
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

### python needs the compression headers in the temporary toolchain

`python` is built in stage 1 as well as in the base system, and it builds its
`zlib`, `bz2`, `lzma` and `zstd` modules against whatever headers exist in
`$TOOLS/include` at that moment. The toolchain list originally had no `zlib`
and no `zstd`, and `xz` came *after* python, which gave:

```
fatal error: zlib.h: No such file or directory
fatal error: zstd.h: No such file or directory
fatal error: lzma.h: No such file or directory
```

`toolchainpkg` now lists `pkgconf zlib xz zstd python` in that order (the stage
1 loop builds in list order, and bzip2 already comes earlier for `bzlib.h`).
zlib and xz take the generic recipe, which configures with `--prefix=$TOOLS`;
zstd has no `./configure`, so `ports/core/zstd` grew a `bootstrap_build` that
runs `make PREFIX=$TOOLS install` (`make install` there pulls in
`install-includes`, which is what installs `zstd.h`).

The errors above were only the symptoms. CPython 3.14 has no `Modules/setup.py`
anymore: `configure` decides each module with `PKG_CHECK_MODULES` and turns the
`@MODULE_X_TRUE@` lines of `Modules/Setup.stdlib.in` on or off. Stage 1 had no
pkg-config of its own, so those probes were answered by the **host** pkg-config
with the host's `.pc` files. A `.pc` file for `/usr/include` contributes no
`-I` flag, because pkg-config drops system directories, so the module was
enabled by the host library while the header could not be found — the stage 1
compiler searches `$TOOLS/include` (it is built with
`--with-native-system-header-dir=$TOOLS/include`) and not `/usr/include`. Hence
"found the library, missing the header", one library at a time.

Stage 1 now builds `pkgconf` and exports

```sh
export PKG_CONFIG_PATH=
export PKG_CONFIG_LIBDIR="$TOOLS/lib/pkgconfig:$TOOLS/libdata/pkgconfig:$TOOLS/share/pkgconfig"
```

so probes can only see the temporary toolchain. python finds zlib, liblzma and
libzstd there; `readline`, `_sqlite3`, `_ssl` and `_ctypes` are honestly
not found and skipped, and are built properly in the base system, where the
full order applies. The same leak would have hit every later stage 1 package
that uses pkg-config (openssl, curl, libarchive).

### ncurses headers stay out of `$TOOLS/include`

ncurses' `configure` decides where headers go with

```sh
if test "$prefix" = "/usr" ; then with_overwrite=yes; else with_overwrite=no; fi
...
includesubdir=
if test "$with_overwrite" = no && test "x$includedir" = 'x${prefix}/include'; then
	includesubdir="/ncurses"
fi
```

So a stage 1 build with `--prefix=$TOOLS` puts them in `$TOOLS/include/ncurses/`
unless `--enable-overwrite` is passed, while the `/usr` build puts them straight
into `/usr/include` (which is why the port's footprint looks normal either way).

That is what broke python's `_curses`:

```
./Modules/_cursesmodule.c:3777:37: error: implicit declaration of function 'setupterm'
```

`_cursesmodule.c` uses `setupterm()` unconditionally but includes `<term.h>` —
which declares it — only under `#ifdef HAVE_TERM_H`, and python's configure sets
that with `AC_CHECK_HEADERS([term.h], [], [], _CURSES_INCLUDES)`, a bare
`term.h` lookup. With the header one level too deep the check failed, and
python's `-Werror=implicit-function-declaration` turned the call into an error.

`ports/core/ncurses` had a `bootstrap_build` in all but name: the function was
called `bootstrap_pkg`, so `files/pkgmk.bootstrap` never called it and stage 1
used the generic recipe. It is now `bootstrap_build`, which passes
`--enable-overwrite` (plus `--enable-widec`, so `libncursesw` exists and python's
`ncursesw` probe succeeds) and creates the `$TOOLS/lib/libncurses.so` symlink.

Rebuilding ncurses into an existing `$TOOLS` requires dropping its markers:

```sh
rm -f  /tmp/lfs-tools/ncurses                                  # skip marker
sed -i '/^ncurses$/d' /tmp/lfs-rootfs/var/lib/lfs-scripts/stage1.done
rm -rf /tmp/lfs-tools/include/ncurses                           # stale headers
```

### curl 8.4.0 cannot build against OpenSSL 4.0

OpenSSL 4.0 made `ASN1_STRING` opaque and constified much of the X509 API.
curl 8.4.0 still touched the struct directly, so stage 1 stopped at:

```
vtls/openssl.c:455:11: error: invalid use of incomplete typedef 'ASN1_INTEGER'
```

plus a pile of `discards 'const' qualifier` warnings, because `-Wno-error` does
not downgrade a type error. Upstream only grew its compatibility layer later
(`ASN1_STRING_get0_data()` / `ASN1_STRING_length()` behind
`#if OPENSSL_VERSION_NUMBER < 0x40100000L`). `ports/core/curl` is now
**8.23.0**, the current release, which builds cleanly against OpenSSL 4.0.1.

Two details worth knowing:

- the ABI did not move: curl still ships `lib/Makefile.soname` as `12:0:8`, so
  the installed object is `libcurl.so.4.8.0` exactly as with 8.4.0, and the
  header set in `include/curl/` is unchanged — the `.footprint` needed no edit.
  New man pages may appear; refresh `.footprint` from a real build if you use
  `pkgmk -uf`.
- `build_opt` no longer passes `--without-librtmp`: RTMP support was removed
  from curl, so the option no longer exists in `configure` (autoconf would only
  warn, but it is dead weight).

### curl's stage-1 build needs `--without-libpsl`

curl's `configure` defaults `OPT_LIBPSL=off`, which still *probes* libpsl: it
asks pkg-config for `libpsl`, then falls back to `AC_CHECK_LIB(psl, psl_builtin)`,
and hard-fails the run with

```
configure: error: libpsl libs and/or directories were not found!
```

`build_opt` already passed `--without-libpsl` for the base system, but the
stage-1 `bootstrap_opt` did not, so stage 1 stopped at curl. Stage 1 has no
libpsl (nothing built before curl ships it, and stage-1 pkg-config only sees
`$TOOLS`), so the flag now sits in both option sets.

### python needs the LFS "openssl_4" backport for `_ssl`

`ports/core/python` builds `_ssl` in the base system, where openssl 4.0.1 comes
first in the package order. Python 3.14.7 still declares and calls

```c
SSLv3_method(); TLSv1_method(); TLSv1_1_method(); TLSv1_2_method();
```

under `OPENSSL_NO_SSL3_METHOD` / `OPENSSL_NO_TLS1_1_METHOD` guards, and OpenSSL
4.0 removed those functions outright, so the module cannot compile.
`Python-3.14.7-openssl_4-1.patch` (the LFS 13.1 backport, upstream status
"Applied") is now in `source=` and applied in `pre_build()`, before the tests
are deleted, because it also touches `Lib/test/test_ssl.py`.

It was verified by applying it to a fresh `Python-3.14.7.tar.xz`:
`patch -Np1 -i …` exits 0 with no `.rej`, every hunk landing with offsets of a
few lines. A `patch --dry-run` is misleading for this file: it contains five
sequential diffs against the same files, and in dry-run mode later diffs are
compared with the unmodified file, so they report false failures.

`.gitattributes` pins `*.patch`/`*.diff` to `-text`: this repo is developed on
Windows with `core.autocrlf=true`, and a CRLF-rewritten patch would not apply
inside the build.
### man-pages 6.18 refuses to run without `make -R`

man-pages 6.18 ships a `GNUmakefile` (not `Makefile`) that opens with a make
version gate:

```make
ifneq (4.4.999,$(firstword $(sort 4.4.999 $(MAKE_VERSION))))
  ifneq (R,$(findstring R, $(firstword -$(MAKEFLAGS))))
    $(error Please run make(1) with the '-R' option)
  endif
endif
```

The base system's make is 4.4.1, which sorts below that sentinel, so stage 2
stops there. The flag has to be a capital `-R`: the test looks for an `R` in the
first `MAKEFLAGS` word, so lowercase `-r` and `--no-builtin-rules` both still
trip it. `ports/core/man-pages` now runs

```
make -R prefix=/usr DESTDIR=$PKG install
```

and the makefile adds `--no-builtin-rules` / `--no-builtin-variables` itself
once the gate passes.

### glibc 2.44 was carrying the 2.38 upstream_fixes patch

`ports/core/glibc` had been bumped to 2.44, but `source=` still listed
`glibc-2.38-upstream_fixes-3.patch`, so patching failed on the first hunk and
nothing built. It now ships `glibc-2.44-upstream_fixes-1.patch` from the LFS
13.1 patch set: 100 files, applies cleanly to the pristine tarball, and it is
the one that matters here (the `tanh` fix plus the parallel `make`
build/install ordering that MLFS needs).

`.md5sum` was stale in the same way — it still named `glibc-2.38.tar.xz` and the
2.38 patch. Both entries now match 2.44:

```
7677da43ef759c68e005f5d4c37986a6  glibc-2.44.tar.xz
990574184b25aa3029a2444e81865098  glibc-2.44-upstream_fixes-1.patch
```

If you ever re-check this patch on Windows, expect one reject for `ADVISORIES`:
the hunk creates a file with that name while the tree has an `advisories/`
directory, and NTFS is case-insensitive. On Linux both coexist and the hunk
applies.

### GCC 16 asks for `-lgcc_s_asneeded`, which the toolchain does not install

GCC 16's `gcc/configure` sets `gcc_cv_ld_use_as_needed_ldscript=yes` whenever
`ld --help` mentions `as-needed`, and the driver then links runtime support as

```
-lgcc_s_asneeded -latomic_asneeded
```

instead of the pre-16 `--push-state --as-needed -lgcc_s --pop-state`. Those
names are not libraries: they are `INPUT ( AS_NEEDED ( -lgcc_s ) )` linker
scripts (`libgcc_s_asneeded.so`, `libatomic_asneeded.so`) that libgcc's
`t-slibgcc` rule writes next to the shared libgcc. `gcc-pass1` is built with
`--disable-shared`, so it produces no shared libgcc and no script, yet its
driver still carries the `_asneeded` specs — every link through it fails with

```
/tmp/lfs-tools/bin/ld: cannot find -lgcc_s_asneeded: No such file or directory
/tmp/lfs-tools/bin/ld: cannot find -latomic_asneeded: No such file or directory
```

`ports/core/gcc` now pins the cache variable to `no` for `gcc-pass1`,
`gcc-pass3` and the base-system build, which restores the push-state form the
tree is otherwise built against.

To unblock a tree that already has an affected gcc without rebuilding the three
passes, put the two scripts where the driver looks for them:

```sh
for d in /tmp/lfs-tools/lib /tmp/lfs-tools/lib32; do
  [ -d "$d" ] || continue
  rm -f "$d/libgcc_s_asneeded.so"
  printf '/* GNU ld script
   Add DT_NEEDED entry for libgcc_s.so only if needed.  */
INPUT ( AS_NEEDED ( -lgcc_s ) )
' > "$d/libgcc_s_asneeded.so"
  if [ -e "$d/libatomic.so" ]; then
    rm -f "$d/libatomic_asneeded.so"
    printf '/* GNU ld script
   Add DT_NEEDED entry for libatomic only if needed.  */
INPUT ( AS_NEEDED ( -latomic ) )
' > "$d/libatomic_asneeded.so"
  fi
done
```

(The `rm -f` is there because an interactive shell with `set -C`/`noclobber` answers
`cannot overwrite existing file` for a plain `>`. If the scripts already exist and
look correct, `ld` is not searching that directory at all — check
`gcc -print-search-dirs` from inside the build.)

### Stage 2 cannot download a source: "unable to get local issuer certificate"

Nothing inside the chroot provides a CA bundle until `ca-certificates` is
built, which is near the end of `basepkg`, and the toolchain's own bundle is a
Mozilla snapshot from 2023. Any source that stage 2 has to fetch before then
therefore fails TLS verification. `bootstrap-core.sh` copies the freshest
bundle it can find to `$LFS/etc/ssl/certs/bootstrap-ca-bundle.crt` and exports
`CURL_CA_BUNDLE`/`SSL_CERT_FILE` in the chroot's `pkgin`/`pkgmk` config.

To avoid the download entirely, put the tarball in `sources/` on the host;
that directory is bind-mounted into the chroot at `/var/cache/pkg/sources`.

### Forcing a single stage-1 package to rebuild

Stage 1 skips a package when *either* marker is present, so both have to go:

```sh
TOOLS=$(readlink -f /tmp/lfs-tools)
LFS=$(dirname "$(dirname "$TOOLS")")        # $LFS/tmp/lfs-tools -> $LFS
STATE=$LFS/var/lib/lfs-scripts

rm -f "$TOOLS/gcc-pass3" "$STATE/stage1.complete" "$STATE/stage1.failed"
sed -i '/^gcc-pass3$/d' "$STATE/stage1.done"
```

`stage1.complete` is the one people forget: `_buildtoolchain` returns before the
package loop when it exists, so deleting only the per-package marker changes
nothing. No build directory has to be cleaned — `pkgmk` is invoked with `-f`,
which extracts and rebuilds from scratch.

Verify the rebuilt driver before trusting it:

```sh
/tmp/lfs-tools/bin/gcc -dumpspecs | grep asneeded    # must print nothing
```

### Recovering a tree whose toolchain bsdtar cannot extract gcc

`$TOOLS/lib/locale` is empty when the temporary glibc was installed before the
`C.UTF-8` generation was added, and libarchive's bsdtar then has no UTF-8
charset to convert the non-ASCII pathnames in `gcc-16.2.0.tar.xz` into. If
generating the locale by hand does not clear it, stop asking libarchive to
translate anything: GNU tar stores and restores the bytes as they are.

```sh
set +C
T=/tmp/lfs-tools
[ -f "$T/bin/bsdtar.real" ] || mv "$T/bin/bsdtar" "$T/bin/bsdtar.real"
cat > "$T/bin/bsdtar" <<'SHIM'
#!/bin/sh
for a in "$@"; do
	case "$a" in
		-x*|-t*|--extract*|--list*)
			for t in /usr/bin/tar /tmp/lfs-tools/bin/tar /bin/tar; do
				[ -x "$t" ] && exec "$t" "$@"
			done ;;
	esac
done
exec /tmp/lfs-tools/bin/bsdtar.real "$@"
SHIM
chmod +x "$T/bin/bsdtar"
```

Extraction then goes through the host's GNU tar while archive creation and
everything else keep using the toolchain's libarchive. This is a recovery step
for existing trees; fresh builds generate `C.UTF-8` as part of the stage-1 glibc
install and do not need it.

### inetutils: `tgetent` has no prototype in `telnet`

inetutils 2.8 builds `telnet` and `telnetd` against termcap. `am/libcurses.m4`
declares `tgetent()` for those files only through `HAVE_TERMCAP_TGETENT` (or
`HAVE_CURSES_TGETENT`), which it defines when the function comes from libtermcap
or libcurses. When ncurses is found first, `IU_LIB_TERMCAP` just takes
`LIBTERMCAP="$LIBNCURSES"` and defines `HAVE_TGETENT` alone, so
`telnet/telnet.c` compiles `tgetent (termbuf, tname)` with no declaration and
gcc 16 stops the build:

```
telnet.c:724:9: error: implicit declaration of function 'tgetent'; did you mean 'getenv'?
```

`ports/core/inetutils/tgetent_include.patch` adds a `HAVE_TGETENT` branch that
includes `<termcap.h>` when `__has_include` sees it (ncurses ships the header),
for both `telnet/telnet.c` and `telnetd/utility.c`. `pkgmk` applies it
automatically because the patch is listed in `source=()`.

### kmod: `meson: command not found`

kmod 34.2 ships two build systems: the autotools `configure` that LFS uses and a
`meson.build`. `detect_buildtype` in `ports/core/pkgutils/extension` tests
`meson.build` first, so the kmod port was routed to `_meson_build` even though
stage 1 and stage 2 never install meson and the port `build_opt` is autotools
syntax (`--with-openssl --with-xz --with-zlib`):

```
meson: command not found
```

`ports/core/kmod/Pkgfile` now pins `build_type=configure_build`, the same way
`pkgconf` and `util-linux` do, so pkgmk skips detection and runs the configure
script the tarball already contains.


### kmod: `scdoc` is not in the base system

kmod 34 builds its man pages by default and its `configure` stops when scdoc is
missing:

```
configure: error: *** scdoc needed for building manpages. Either install it or pass --disable-manpages
```

scdoc is a BLFS package and neither stage builds it, so the port
`build_opt` now passes `--disable-manpages` the way LFS does and the build skips
the man pages instead of the whole package. The checked-in `.md5sum` was also
still naming `kmod-31.tar.xz`; it now covers the `kmod-34.2.tar.xz` the port
actually downloads.


### elfutils: `stdlib.h: No such file or directory`

elfutils is the first stage 2 package that compiles C++ (`src/srcfiles.cxx`),
and libstdc++ reaches the C library through `#include_next`:

```
/usr/include/c++/16.2.0/cstdlib:75:15: fatal error: stdlib.h: No such file or directory
   75 | #include_next <stdlib.h>
```

The chroot `pkgmk.conf` added `/usr/include` with `-isystem`. That is the
trigger for GCC bug 70129/70936: once `/usr/include` is a system directory,
the follow-up lookup from `#include_next` finds nothing, so C++ code cannot
reach `stdlib.h` at all. C packages never noticed, which is why acl built
with the same flag.

gcc here is built with `--with-native-system-header-dir=$TOOLS/include` (see
the python section above), so `/usr/include` has to be added explicitly.
Both the chroot `CFLAGS`/`CPPFLAGS` and the toolchain specs rewrite now use

```
-idirafter /usr/include
```

which is searched last, after the compiler's own headers, like a stock
`/usr/include`, and leaves `#include_next` working. The
`attr/error_context.h` fix from the acl failure still holds.

### elfutils: `_FORTIFY_SOURCE requires compiling with optimization (-O)`

elfutils is also the first package whose `configure` hardens the build: it
probes for a `-D_FORTIFY_SOURCE` level that compiles and adds the winner to
**both** flag variables.

```
CFLAGS="$fortified_cflags $save_CFLAGS"
CXXFLAGS="$fortified_cflags $CXXFLAGS"
```

Its C++ sources are compiled with `-Werror` (`config/eu.am`), so a C++ compile
that has no `-O` dies on glibc's own warning:

```
/usr/include/features.h:451:4: error: #warning _FORTIFY_SOURCE requires compiling with optimization (-O) [-Werror=cpp]
```

The C flags written to `/tmp/pkgmk.conf` are literal and always carry `-O2`,
but the C++ ones were generated as `export CXXFLAGS="${CFLAGS}"`. That
`${CFLAGS}` is expanded by the shell running `bootstrap.sh` while it writes the
file, and a `./bootstrap.sh --resume` run reaches `basepkg` without
`toolchainpkg` having exported `CFLAGS` in that shell, so it wrote an empty
value and g++ compiled everything unoptimised. Both variables are now written
out literally, and `CXXFLAGS` no longer inherits `-std=gnu17`, which is a C-only
option that g++ can only warn about.

### python: `Python-3.14.7-openssl_4-1.patch: No such file or directory`

`pre_build` applied the OpenSSL 4 backport a second time, from
`$PKGMK_SOURCE_DIR`:

```
patch -Np1 -i $PKGMK_SOURCE_DIR/Python-3.14.7-openssl_4-1.patch
```

pkgmk never copies a port's own files into `$PKGMK_SOURCE_DIR`; only archives
it downloads land there. In `pkgutils-5.40.10/pkgmk.in`, `download_source`
resolves a source entry with no URL to the bare filename - a file in the port
directory - and `unpack_source` copies it to `$SRC` (`$PKGMK_WORK_DIR/src`).
The extension's `_patch()` then applies every `*.patch` from `source=()` as
`patch -t -p1 -i $SRC/<patch>` before `pre_build` runs, so the explicit call
could only fail; with `-N` it would just have been skipped as already applied
had pkgmk kept the file there.

The duplicate is gone and `pre_build` only removes the test suite, still after
the patch has been applied because the patch touches `Lib/test/test_ssl.py`.
This is also why every other port here reads port-local files as `$SRC/...` -
see glibc's `ld.so.conf`, `nsswitch.conf`, `genlocales` and `pyconfig.h`.


### python: `make: *** [Makefile:1763: checksharedmods] Segmentation fault`

Every command in the stage 2 chroot printed

```
/bin/sh: warning: setlocale: LC_ALL: cannot change locale (C.UTF-8): No such file or directory
```

and `make`'s module check then died without naming a module. `python`'s
`pre_build` runs that check with faulthandler enabled, which named the module -
the only one that touches the locale while it initialises:

```
File "<frozen importlib._bootstrap_external>", line 1053 in create_module
Binary file ".../readline.cpython-314-x86_64-linux-gnu.so", at PyInit_readline+0x5ce
Binary file "/usr/lib/libreadline.so.8", at _rl_init_locale+0x45
Binary file "/lib/libc.so.6", at +0x173cd9
```

`readline-8.3/nls.c` reads the locale name out of the environment and hands it
straight to libc:

```c
lspec = _rl_get_locale_var ("LC_CTYPE");  /* LC_ALL, then LC_CTYPE, then LANG */
...
ret = setlocale (LC_CTYPE, lspec);
```

The chroot's glibc has no `C.UTF-8` that it can load, so that `setlocale()`
call faulted inside libc instead of returning NULL. Two separate things
produced that environment:

- the glibc port generates the rootfs `C.UTF-8` by running the installed
  `localedef` through the build tree's loader, and ended the call with
  `|| true` - a failure left no usable locale and no message;
- `bootstrap-core.sh` picks the UTF-8 locale by running `$TOOLS/bin/locale`,
  i.e. the *toolchain's* glibc, which does have `C.UTF-8` from the stage 1
  glibc build, and then exported that name into `_chroot` calls that run the
  rootfs glibc.

`_ensure_chroot_locale()` now asks the chroot itself,
`[ "$(LC_ALL=C.UTF-8 /usr/bin/locale charmap)" = UTF-8 ]`, regenerates
`/usr/lib/locale/C.UTF-8` with the rootfs' own `/usr/bin/localedef` when that
fails, and otherwise builds with `LC_ALL=C`; `_chroot` takes its `LC_ALL` from
`_chrootlocale`. It runs before the package loop, so `--resume` repairs an
existing tree, and again right after glibc is installed. The glibc port
deletes a stale `C.UTF-8` before regenerating and reports a failure instead of
swallowing it.

python's `pre_build` no longer rewrites `Makefile.pre.in` for `--debug`; the
`PYTHONFAULTHANDLER=1` export stays, because a crash in `make`'s module check
is otherwise reported without a module name.

A `--resume` run does not rebuild glibc, and does not need to: the locale is
data, not code, so `_ensure_chroot_locale()` repairs `/usr/lib/locale/C.UTF-8`
in place before the package loop starts. The first attempt still crashed
because `_chroot` passed the host's `LC_ALL` and ignored `_chrootlocale`, so
the chroot kept receiving the toolchain-only name. `_chroot` now always starts
at `C` and uses `C.UTF-8` only after the chroot's own `locale charmap`
confirms it.

### python: `./python: No module named test` (`profile-run-stamp`)

With the locale fixed the build reached python's PGO step and stopped there:

```
LD_LIBRARY_PATH=... ./python -m test --pgo --timeout=
.../python: No module named test
make: *** [Makefile:1021: profile-run-stamp] Error 1
```

`build_opt` enables `--enable-optimizations`, and the last thing `make` does
for it is profile the interpreter by running the test suite - but `pre_build`
deleted `Lib/test` before `make` even started. The tests now stay in the tree
for the build, and `post_build` removes `test`, `*/test`, `*/tests` and
`*/idle_test` from `$PKG` instead, so the package still ships without them.

The three optional modules reported missing in the same log (`_tkinter`,
`_uuid`, `_zstd`) are expected this early: tcl/tk is not in `basepkg` at all,
and util-linux (libuuid) and zstd are built after python.

### tar: `conflicting types for 'acl_get_file_at'`

acl 2.4.0, the version this tree builds, added `acl_get_file_at()`,
`acl_set_file_at()` and `acl_delete_def_file_at()` with an extra `at_flags`
argument. tar 1.35 keeps its own static copies of those three names in
`src/xattrs.c` as fallbacks, so `xattrs.o` no longer compiles and the build
stops at

```
xattrs.c:142:14: error: conflicting types for 'acl_get_file_at'
make[2]: *** [Makefile:1932: xattrs.o] Error 1
```

The port now carries LFS 13.1's required `tar-1.35-acl_fix-1.patch` (upstream
commit `08c3fc2e` "Avoid acl_ prefix for functions", backported to 1.35), which
renames the fallbacks to `tar_acl_*`. The pkgutils extension's `_patch()`
applies every `source=()` entry ending in `.patch`, so listing the file in
`source=()` is all the port needs.

### linux-pam: `too few arguments to function 'memset_explicit'`

libpam's own `pam_inline.h` calls `memset_explicit(ptr, len)` with two
arguments, but the C23 function takes three (`void *, int, size_t`), so every
object that includes it fails:

```
./include/pam_inline.h:85:17: error: too few arguments to function 'memset_explicit'; expected 3, have 2
make[2]: *** [Makefile:627: pam_end.lo] Error 1
```

It only shows up when `HAVE_MEMSET_EXPLICIT` is defined. configure's
`AC_CHECK_FUNCS(explicit_bzero memset_explicit)` compiles `char
memset_explicit();` without including `<string.h>`, so the probe succeeds even
though the two-argument call in `pam_inline.h` could never compile, and the
`explicit_bzero` branch that works is skipped.

Upstream fixed the call by passing the fill byte, giving
`memset_explicit(ptr, '\0', len)`; 1.6.1 was the first release to contain it.

The port no longer builds 1.5.3 at all: it tracks `linux-pam` 1.7.2, the version
BLFS 13.1 builds on an LFS 13.1 platform, where the bug is gone. That bump had
two consequences:

- 1.7.x dropped autotools, so the old flags became meson options
  (`-D docs=disabled` for `--disable-regenerate-docu`, `-D securedir=/lib/security`
  for `--enable-securedir`). The extension still supplies `--prefix=/usr` and
  `--libdir=/usr/lib` itself.
- `basepkg` had no meson, so `ninja` 1.13.2 and `meson` 1.12.0 are now built
  just before it. Ninja bootstraps itself with `configure.py --bootstrap`.
  Meson is installed by hand because LFS uses `pip3` while python here is built
  `--without-ensurepip`: the port copies `mesonbuild/` into site-packages and
  installs `meson.py` as `/usr/bin/meson`.

The bump also fixed a silent bug in `post_build`: it set the setuid bit on
`$PKG/sbin/unix_chkpwd`, but autotools put the helper in `/usr/sbin` too, so
that chmod had never matched anything.It now targets
`/usr/sbin/unix_chkpwd` and fails loudly when the helper is missing.
