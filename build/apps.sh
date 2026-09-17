#!/bin/sh
# Build the rest of the session as static binaries: xkbcomp, xauth and jwm.
# Runs inside the Alpine build tree (see bootstrap.sh).

set -e
. /rdesk/build/versions.sh
cd /build
mkdir -p src stamps
PREFIX=/opt/rdesk
APP=https://www.x.org/releases/individual/app

export PKG_CONFIG=/usr/local/bin/pkg-config-static
export LDFLAGS="-static"
export CFLAGS="-O2"

fetch() {   # download (once), unpack fresh, cd into the source
    file=/build/src/${1##*/}
    cd /build/src
    [ -f "$file" ] || curl -fsSLO "$1"
    rm -rf "$(basename "${file%.tar.*}")"
    busybox tar xf "$file"
    cd "$(basename "${file%.tar.*}")"
}

# xkbcomp: the X server runs this to compile the keyboard map
if [ ! -f stamps/xkbcomp ]; then
    echo "== xkbcomp"
    fetch $APP/xkbcomp-$XKBCOMP.tar.xz
    ./configure --prefix=$PREFIX --disable-selective-werror > c.log 2>&1
    make -j "${JOBS:-8}" > m.log 2>&1
    make install > i.log 2>&1
    touch /build/stamps/xkbcomp
fi

# xauth: creates the display's access cookie
if [ ! -f stamps/xauth ]; then
    echo "== xauth"
    fetch $APP/xauth-$XAUTH.tar.xz
    ./configure --prefix=$PREFIX --disable-selective-werror > c.log 2>&1
    make -j "${JOBS:-8}" > m.log 2>&1
    make install > i.log 2>&1
    touch /build/stamps/xauth
fi

# Pango: jwm draws its text with it, and without it has only the X server's
# bitmap fonts.  Alpine has no static build of it.
if [ ! -f stamps/pango ]; then
    echo "== pango"
    fetch https://download.gnome.org/sources/pango/${PANGO%.*}/pango-$PANGO.tar.xz
    # only its static libraries are used; LDFLAGS is cleared because -static
    # breaks the link of the utilities it builds alongside them
    LDFLAGS= meson setup bld --prefix=/usr --libdir=lib --default-library=static \
        -Ddocumentation=false -Dgtk_doc=false -Dman-pages=false \
        -Dintrospection=disabled -Dbuild-testsuite=false -Dbuild-examples=false \
        -Dfontconfig=enabled -Dfreetype=enabled -Dxft=enabled \
        -Dcairo=disabled -Dlibthai=disabled -Dsysprof=disabled > c.log 2>&1
    ninja -C bld > m.log 2>&1
    ninja -C bld install > i.log 2>&1
    touch /build/stamps/pango
fi

# JWM: the window manager.  Built without cairo and rsvg, which it uses only
# for SVG icons.
if [ ! -f stamps/jwm ]; then
    echo "== jwm"
    fetch https://github.com/joewing/jwm/releases/download/v$JWM/jwm-$JWM.tar.xz
    # jwm's configure looks for pkg-config as PKGCONFIG, and puts the libraries
    # it finds into LDFLAGS, where a static link test cannot resolve them; so
    # give its tests and the final link every library, in link order
    JWM_LIBS=$($PKG_CONFIG --libs pangoxft xft xinerama xmu xpm xext xrender libpng libjpeg x11)
    ./configure --prefix=$PREFIX --disable-nls --disable-cairo --disable-rsvg \
        PKGCONFIG=$PKG_CONFIG LIBS="$JWM_LIBS" > c.log 2>&1
    make -j "${JOBS:-8}" LDFLAGS="$(sed -n 's/^LDFLAGS = //p' src/Makefile) $JWM_LIBS" > m.log 2>&1
    make install > i.log 2>&1
    touch /build/stamps/jwm
fi

echo "== built binaries:"
for b in $PREFIX/bin/*; do
    printf '%s: %s\n' "$(basename "$b")" "$(file -b "$b" | cut -d, -f1-2)"
done
