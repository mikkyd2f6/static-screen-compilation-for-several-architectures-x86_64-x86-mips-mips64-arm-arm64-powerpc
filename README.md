# static-screen

Statically-linked [GNU screen](https://www.gnu.org/software/screen/) for every
major Linux architecture — single portable binaries with no shared-library
dependencies, for keeping sessions alive on servers, containers, and embedded
boxes where you can't install packages.

One binary per flavor:

| Binary | Arch | Notes |
|---|---|---|
| `screen-<ver>-x86_64-static` | x86_64 | native build |
| `screen-<ver>-x86-static` | i686 | Pentium Pro baseline (CMOV) |
| `screen-<ver>-arm64-static` | aarch64 LP64 | |
| `screen-<ver>-arm32-static` | armhf (ARMv7-A hard-float) | not for ARMv6/soft-float |
| `screen-<ver>-mips64-static` | MIPS64 big-endian, n64 | |
| `screen-<ver>-mips64el-static` | MIPS64 little-endian, n64 | |
| `screen-<ver>-mips32-static` | MIPS32 big-endian, o32 | |
| `screen-<ver>-mips32el-static` | MIPS32 little-endian, o32 | |
| `screen-<ver>-ppc64le-static` | POWER64 little-endian, ELFv2 | modern POWER8/9/10 |
| `screen-<ver>-ppc32-static` | PowerPC 32-bit big-endian | classic/embedded |
| `screen-<ver>-ppc64be-static` | POWER64 big-endian, ELFv1 | legacy |

Each binary statically links its own **ncurses** (widec) and **libxcrypt**
(the Ubuntu cross sysroots ship no `libcrypt.a`), built `--without-pam`
against glibc 2.40.

## Quick start

Requirements: Ubuntu/Debian-ish **x86_64** host with `build-essential`,
`curl`, and the cross toolchains + qemu for every flavor you build:

```bash
sudo apt-get install -y \
    gcc-14-i686-linux-gnu libc6-dev-i386-cross binutils-i686-linux-gnu \
    gcc-14-aarch64-linux-gnu libc6-dev-arm64-cross binutils-aarch64-linux-gnu \
    gcc-14-arm-linux-gnueabihf libc6-dev-armhf-cross binutils-arm-linux-gnueabihf \
    gcc-14-mips64-linux-gnuabi64 libc6-dev-mips64-cross binutils-mips64-linux-gnuabi64 \
    gcc-14-mips64el-linux-gnuabi64 libc6-dev-mips64el-cross binutils-mips64el-linux-gnuabi64 \
    gcc-14-mips-linux-gnu libc6-dev-mips-cross binutils-mips-linux-gnu \
    gcc-14-mipsel-linux-gnu libc6-dev-mipsel-cross binutils-mipsel-linux-gnu \
    gcc-14-powerpc64le-linux-gnu libc6-dev-ppc64el-cross binutils-powerpc64le-linux-gnu \
    gcc-14-powerpc-linux-gnu libc6-dev-powerpc-cross binutils-powerpc-linux-gnu \
    gcc-14-powerpc64-linux-gnu libc6-dev-ppc64-cross binutils-powerpc64-linux-gnu \
    qemu-user-static
```

(The `build.sh` dependency check prints exactly what is missing for the
flavors you have selected, with the matching install line.)

Then:

```bash
./build.sh
```

Binaries land in `dist/`, install trees under `install/<triplet>/` (includes
`etc/screenrc` and the terminfo-free runtime files). A full build of all 11
flavors takes roughly 20–30 minutes on a 20-core machine. The script is
re-runnable: sources, per-flavor ncurses/libxcrypt installs, and finished
binaries are skipped when already present.

### Options

```bash
SCREEN_VERSION=5.0.2    # screen version
XCRYPT_VERSION=4.4.38   # libxcrypt version
NCURSES_VERSION=6.5     # ncurses version
TRIPLETS="..."          # space-separated subset of triplets (see build.sh)
CROSS_GCC_VER=14        # cross gcc package series on the host
JOBS=$(nproc)           # parallel jobs
BASE=/path/to/dir       # where to place src/deps/build/install/dist (default: repo dir)
```

## Deploying to a machine

```bash
scp dist/screen-5.0.2-arm64-static user@device:/usr/local/bin/screen
```

Screen needs a writable socket directory at runtime (it creates
`$HOME/.screen` or uses `/run/screen` when present) and a `TERM` whose
terminfo entry exists on the target (usually `/usr/share/terminfo` or
`/lib/terminfo` on any full system).

## Verifying on an x86_64 host (qemu)

The build script sanity-checks every binary (`--version`) under qemu-user
(natively for x86_64). A full interactive session also works under qemu on
this host since terminfo is architecture-independent data:

```bash
TERM=xterm qemu-aarch64-static ./dist/screen-5.0.2-arm64-static -R -S test
```

## Caveats

- Built `--disable-pam` (screen 5 enables PAM by default): screen falls back
  to its own password mechanism for multiuser mode.
- Static glibc: NSS-dependent behavior (user/group name resolution in
  `screen -ls` output, etc.) falls back to numeric forms in minimal
  environments — same as any statically linked glibc tool.
- Multiuser mode (`screen -rx other/`) depends on setuid and socket
  permissions on the target, unchanged by static linking.

## How it works / notable gotchas

- ncurses is cross-built per flavor (widec static, no progs, no terminfo
  database install — the target's own terminfo db is used at runtime; plain
  `libncurses.a`/`libtinfo.a` names provided as symlinks to `libncursesw.a`).
- **libxcrypt is required**: Ubuntu's cross sysroots ship no `libcrypt.a`
  (modern glibc dropped libcrypt), and screen needs `crypt()` for its
  password handling.
- Plain `LDFLAGS=-static` suffices for the final link — screen does not wrap
  its link in libtool (no `-all-static` workaround needed, unlike GDB).

Build layout (all gitignored): `src/`, `deps/`, `build-*/`, `install/`,
`dist/`.

## License

GNU screen is GPLv2+; statically-linked binaries are derivative works, so if
you distribute the binaries you must offer the corresponding source (this
repo plus the pinned upstream versions is a reasonable way to do that). No
license is claimed over these build files — add one of your choosing before
publishing.
