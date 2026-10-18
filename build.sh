#!/usr/bin/env bash
#
# Build statically-linked GNU screen for every architecture flavor:
#   x86_64 (native), x86 (i686), arm64 (aarch64), arm32 (armhf),
#   mips64 + mips64el (n64), mips32 + mips32el (o32),
#   ppc64le, ppc32, ppc64be
#
# One binary per flavor. ncurses and libxcrypt are cross-built statically per
# flavor (the Ubuntu cross sysroots ship no libcrypt, and ncurses is not
# packaged for cross use).
#
# Outputs:
#   dist/screen-<ver>-<flavor>-static   stripped static binaries
#   install/<triplet>/                  full install trees
#
# Runs on an x86_64 Ubuntu/Debian host; flavors other than x86_64 are
# cross-compiled with the Ubuntu cross toolchains. qemu-user is used to
# sanity-check the cross binaries. See README.md for details.
#
set -euo pipefail

SCREEN_VERSION="${SCREEN_VERSION:-5.0.2}"
XCRYPT_VERSION="${XCRYPT_VERSION:-4.4.38}"
NCURSES_VERSION="${NCURSES_VERSION:-6.5}"

NATIVE_TRIPLET=x86_64-linux-gnu
TRIPLETS="${TRIPLETS:-x86_64-linux-gnu i686-linux-gnu aarch64-linux-gnu arm-linux-gnueabihf mips64-linux-gnuabi64 mips64el-linux-gnuabi64 mips-linux-gnu mipsel-linux-gnu powerpc64le-linux-gnu powerpc-linux-gnu powerpc64-linux-gnu}"
CROSS_GCC_VER="${CROSS_GCC_VER:-14}"
JOBS="${JOBS:-$(nproc)}"

BASE="${BASE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BUILD=x86_64-linux-gnu
SRC="$BASE/src"
DEPS="$BASE/deps"
DIST="$BASE/dist"
mkdir -p "$SRC" "$DEPS" "$DIST"

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

qemu_for_triplet() {
    case "$1" in
        x86_64-linux-gnu) echo "" ;;
        i686-*)          echo qemu-i386-static ;;
        aarch64-*)       echo qemu-aarch64-static ;;
        arm-*)           echo qemu-arm-static ;;
        mips64el-*)      echo qemu-mips64el-static ;;
        mips64-*)        echo qemu-mips64-static ;;
        mipsel-*)        echo qemu-mipsel-static ;;
        mips-*)          echo qemu-mips-static ;;
        powerpc64le-*)   echo qemu-ppc64le-static ;;
        powerpc64-*)     echo qemu-ppc64-static ;;
        powerpc-*)       echo qemu-ppc-static ;;
        *) echo "unsupported triplet: $1" >&2; return 1 ;;
    esac
}

short_for_triplet() {
    case "$1" in
        x86_64-linux-gnu) echo x86_64 ;;
        i686-*)          echo x86 ;;
        aarch64-*)       echo arm64 ;;
        arm-*)           echo arm32 ;;
        mips64el-*)      echo mips64el ;;
        mips64-*)        echo mips64 ;;
        mipsel-*)        echo mips32el ;;
        mips-*)          echo mips32 ;;
        powerpc64le-*)   echo ppc64le ;;
        powerpc64-*)     echo ppc64be ;;
        powerpc-*)       echo ppc32 ;;
        *) echo "unsupported triplet: $1" >&2; return 1 ;;
    esac
}

# --------------------------------------------------------------------------
# 0. Host dependencies
# --------------------------------------------------------------------------
check_host_deps() {
    local missing=()
    local t QEMU

    [ -f /usr/lib/x86_64-linux-gnu/libc.a ] || missing+=(libc6-dev)
    for t in $TRIPLETS; do
        if [ "$t" != "$NATIVE_TRIPLET" ]; then
            command -v "$t-gcc-$CROSS_GCC_VER" >/dev/null || missing+=("gcc-$CROSS_GCC_VER-$t")
            [ -e "/usr/$t/lib/libc.a" ] || case "$t" in
                i686-*)        missing+=(libc6-dev-i386-cross) ;;
                aarch64-*)     missing+=(libc6-dev-arm64-cross) ;;
                arm-*)         missing+=(libc6-dev-armhf-cross) ;;
                mips64el-*)    missing+=(libc6-dev-mips64el-cross) ;;
                mips64-*)      missing+=(libc6-dev-mips64-cross) ;;
                mipsel-*)      missing+=(libc6-dev-mipsel-cross) ;;
                mips-*)        missing+=(libc6-dev-mips-cross) ;;
                powerpc64le-*) missing+=(libc6-dev-ppc64el-cross) ;;
                powerpc64-*)   missing+=(libc6-dev-ppc64-cross) ;;
                powerpc-*)     missing+=(libc6-dev-powerpc-cross) ;;
            esac
        fi
        QEMU=$(qemu_for_triplet "$t")
        [ -z "$QEMU" ] && continue   # native flavor runs directly, no qemu
        command -v "$QEMU" >/dev/null || missing+=(qemu-user-static)
    done

    # deduplicate
    local uniq=() p
    for p in "${missing[@]:-}"; do
        [ -n "$p" ] || continue
        case " ${uniq[*]:-} " in *" $p "*) ;; *) uniq+=("$p") ;; esac
    done

    if [ "${#uniq[@]}" -gt 0 ]; then
        echo "Missing host packages: ${uniq[*]}" >&2
        echo "Install them with:" >&2
        echo "  sudo apt-get install -y ${uniq[*]}" >&2
        exit 1
    fi
}

# --------------------------------------------------------------------------
# 1. Fetch and unpack sources
# --------------------------------------------------------------------------
fetch_sources() {
    cd "$SRC"
    [ -f "screen-$SCREEN_VERSION.tar.gz" ] || \
        curl -fsSLO "https://ftp.gnu.org/gnu/screen/screen-$SCREEN_VERSION.tar.gz"
    [ -f "libxcrypt-$XCRYPT_VERSION.tar.xz" ] || \
        curl -fsSLO "https://github.com/besser82/libxcrypt/releases/download/v$XCRYPT_VERSION/libxcrypt-$XCRYPT_VERSION.tar.xz"
    [ -f "ncurses-$NCURSES_VERSION.tar.gz" ] || \
        curl -fsSLO "https://ftp.gnu.org/gnu/ncurses/ncurses-$NCURSES_VERSION.tar.gz"

    [ -d "screen-$SCREEN_VERSION" ] || tar xf "screen-$SCREEN_VERSION.tar.gz"
    [ -d "libxcrypt-$XCRYPT_VERSION" ] || tar xf "libxcrypt-$XCRYPT_VERSION.tar.xz"
    [ -d "ncurses-$NCURSES_VERSION" ] || tar xf "ncurses-$NCURSES_VERSION.tar.gz"
    cd "$BASE"
}

# --------------------------------------------------------------------------
# 2. Build one flavor: ncurses + libxcrypt + screen
# --------------------------------------------------------------------------
build_flavor() {
    local T=$1
    local short
    short=$(short_for_triplet "$T")
    local out="$DIST/screen-$SCREEN_VERSION-$short-static"
    local W="$BASE/build-$T"
    local prefix="$BASE/install/$T"
    local P

    if [ "$T" = "$NATIVE_TRIPLET" ]; then
        P="$DEPS/native"
    else
        P="$DEPS/cross/$T"
    fi

    local CC CXX AR RANLIB STRIPTOOL hostflags
    if [ "$T" = "$NATIVE_TRIPLET" ]; then
        CC=gcc CXX=g++ AR=ar RANLIB=ranlib STRIPTOOL=strip
        hostflags=""
    else
        CC=$T-gcc-$CROSS_GCC_VER CXX=$T-g++-$CROSS_GCC_VER
        AR=$T-ar RANLIB=$T-ranlib STRIPTOOL=$T-strip
        hostflags="--build=$BUILD --host=$T"
    fi

    if [ ! -f "$P/lib/libncursesw.a" ]; then
        log "Building ncurses $NCURSES_VERSION for $T"
        mkdir -p "$W/ncurses"
        cd "$W/ncurses"
        # shellcheck disable=SC2086
        BUILD_CC=gcc CC=$CC CXX=$CXX AR=$AR RANLIB=$RANLIB \
            "$SRC/ncurses-$NCURSES_VERSION/configure" \
            $hostflags \
            --prefix="$P" --disable-shared --enable-static \
            --without-progs --without-ada --without-manpages --disable-db-install \
            --disable-stripping --enable-widec
        make -j"$JOBS" && make install
        # readline/screen look for the plain names; provide symlink aliases
        ln -sf libncursesw.a "$P/lib/libncurses.a"
        ln -sf libncursesw.a "$P/lib/libtinfo.a"
        cd "$BASE"
    fi

    if [ ! -f "$P/lib/libcrypt.a" ]; then
        log "Building libxcrypt $XCRYPT_VERSION for $T"
        mkdir -p "$W/xcrypt"
        cd "$W/xcrypt"
        # shellcheck disable=SC2086
        CC=$CC AR=$AR RANLIB=$RANLIB \
            "$SRC/libxcrypt-$XCRYPT_VERSION/configure" \
            $hostflags \
            --prefix="$P" \
            --disable-shared --enable-static \
            --disable-failure-tokens
        make -j"$JOBS" && make install
        cd "$BASE"
    fi

    log "Building screen $SCREEN_VERSION for $T"
    [ -x "$out" ] && { log "$out already built"; return; }
    # screen 5.0.x does not build correctly out-of-tree (generated kmapdef.c
    # + shipped kmapdef.h include paths assume in-tree): pristine copy per flavor
    rm -rf "$W/screen"
    cp -a "$SRC/screen-$SCREEN_VERSION" "$W/screen"
    cd "$W/screen"
    # shellcheck disable=SC2086
    CC=$CC AR=$AR RANLIB=$RANLIB \
        "$SRC/screen-$SCREEN_VERSION/configure" \
        $hostflags \
        --prefix="$prefix" \
        --disable-pam \
        CPPFLAGS="-I$P/include -I$P/include/ncursesw" \
        LDFLAGS="-static -L$P/lib" \
        LIBS="-lcrypt"
    make -j"$JOBS"
    make install
    cd "$BASE"

    cp "$prefix/bin/screen" "$out" 2>/dev/null || cp "$prefix/bin/screen-$SCREEN_VERSION" "$out"
    "$STRIPTOOL" "$out"
}

# --------------------------------------------------------------------------
# 3. Sanity check the results
# --------------------------------------------------------------------------
verify() {
    log "Results"
    local t short QEMU b
    for t in $TRIPLETS; do
        short=$(short_for_triplet "$t")
        QEMU=$(qemu_for_triplet "$t")
        b="$DIST/screen-$SCREEN_VERSION-$short-static"
        [ -e "$b" ] || continue
        file "$b" | sed 's/^/  /'
        if [ -n "$QEMU" ]; then
            timeout 120 "$QEMU" "$b" --version | head -1 | sed 's/^/  /'
        else
            timeout 120 "$b" --version | head -1 | sed 's/^/  /'
        fi
    done
}

main() {
    check_host_deps
    fetch_sources

    local t
    for t in $TRIPLETS; do
        build_flavor "$t"
    done

    verify
    log "Done. Binaries in $DIST"
}

main "$@"
