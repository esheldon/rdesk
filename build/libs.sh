#!/bin/sh
# Build the X libraries Alpine has no -static package for.
# Runs inside the Alpine build tree (see bootstrap.sh).

set -e
. /rdesk/build/versions.sh
cd /build
mkdir -p src stamps
BASE=https://www.x.org/releases/individual/lib

for lib in $XLIBS; do
    name=${lib%-*}
    if [ -f "stamps/$name" ]; then
        echo "== $name already built"
        continue
    fi
    echo "== building $lib"

    cd /build/src
    [ -f "$lib.tar.xz" ] || curl -fsSLO "$BASE/$lib.tar.xz"
    rm -rf "$lib"
    busybox tar xf "$lib.tar.xz"   # GNU tar's permission calls fail under proot
    cd "$lib"

    extra=""
    dir="."        # some packages ship sample programs that don't link on musl
    case $name in
        libSM)  extra="--without-libuuid" ;;
        libXpm) dir="src" ;;               # sxpm/cxpm want gettext
    esac

    if [ -x ./configure ]; then
        ./configure --prefix=/usr --libdir=/usr/lib --enable-static \
            --disable-shared --disable-selective-werror $extra > configure.log 2>&1
        make -C "$dir" -j "${JOBS:-8}" > make.log 2>&1
        make -C "$dir" install > install.log 2>&1
    else   # newer X.Org libraries have moved to meson
        meson setup build --prefix=/usr --libdir=lib --default-library=static \
            --buildtype=release > configure.log 2>&1
        ninja -C build install > make.log 2>&1
    fi

    touch "/build/stamps/$name"
    cd /build
done

echo "== all libraries built"
