#!/bin/sh
# Build the optional programs, for hosts that lack them: mupdf, a PDF viewer,
# and feh, an image viewer.  Static binaries, like the rest of the bundle.
# Runs inside the Alpine build tree (see bootstrap.sh); build.sh runs it only
# when RDESK_X11PROGRAMS=1.

set -e
. /rdesk/build/versions.sh
cd /build
mkdir -p src stamps
PREFIX=/opt/x11programs

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

# image libraries only these programs use
apk add -q giflib-dev giflib-static libwebp-dev libwebp-static

# MuPDF: its plain X11 viewer; the OpenGL one needs GLX, which Xvnc lacks.  It
# carries its own copies of the libraries it needs, fonts included, but not
# the Noto and CJK fonts (tofu), which are most of its 51 MB of fonts; the
# standard PDF fonts are kept.  No libcrypto, which is only for checking digital signatures.
if [ ! -f stamps/mupdf ]; then
    echo "== mupdf"
    fetch https://mupdf.com/downloads/archive/mupdf-$MUPDF-source.tar.gz
    make -j "${JOBS:-8}" build=release OUT=build/rdesk \
        HAVE_X11=yes HAVE_GLUT=no HAVE_LIBCRYPTO=no tofu=yes tofu_cjk=yes \
        X11_LIBS="$($PKG_CONFIG --libs x11 xext)" build/rdesk/mupdf-x11 > m.log 2>&1
    install -D build/rdesk/mupdf-x11 $PREFIX/bin/mupdf
    touch /build/stamps/mupdf
fi

# imlib2: feh reads images with it.  It loads each format's code as a module
# with dlopen(), which a static program cannot do, so the patch lets the
# modules ("loaders") be compiled into the library instead.  Only the library
# is built with make; the loaders are compiled here, each with its "loader"
# symbol renamed, and listed in a table the patched library looks them up in.
# The loaders: those needing no other library, and those whose libraries
# Alpine has static builds of.
IMLIB2_LOADERS="ani argb bmp ff ico lbm pnm qoi tga xbm xpm bz2 gif jpeg png webp zlib"
if [ ! -f stamps/imlib2 ]; then
    echo "== imlib2"
    fetch https://downloads.sourceforge.net/project/enlightenment/imlib2-src/$IMLIB2/imlib2-$IMLIB2.tar.xz
    patch -p1 < /rdesk/build/patches/imlib2-static-loaders.patch > p.log
    ./configure --prefix=/usr --libdir=/usr/lib --enable-static --disable-shared \
        --disable-filters --with-bz2 --with-gif --with-jpeg --with-png \
        --with-webp --with-zlib --without-avif --without-heif --without-id3 \
        --without-j2k --without-jxl --without-lzma --without-ps --without-raw \
        --without-svg --without-tiff --without-y4m \
        CPPFLAGS=-DIMLIB2_STATIC_LOADERS > c.log 2>&1
    make -C src/lib -j "${JOBS:-8}" > m.log 2>&1
    make -C src/lib install > i.log 2>&1
    make install-pkgconfigDATA >> i.log 2>&1

    cd src/modules/loaders
    # as its Makefile would; the xpm loader looks for rgb.txt there, then in
    # /usr/share/X11
    cflags="$CFLAGS -I../../.. -I../../lib -DPACKAGE_DATA_DIR=\"/usr/share/imlib2\"
            $($PKG_CONFIG --cflags libpng libjpeg libwebpdemux)"
    for l in $IMLIB2_LOADERS; do
        cc $cflags -c loader_$l.c -o static_$l.o
        objcopy --redefine-sym loader=__imlib_loader_$l static_$l.o
    done
    {
        echo '#include <stddef.h>'
        echo '#include "common.h"'
        echo '#include "loaders.h"'
        for l in $IMLIB2_LOADERS; do
            echo "extern ImlibLoaderModule __imlib_loader_$l;"
        done
        echo 'const ImlibStaticLoader __imlib_static_loaders[] = {'
        for l in $IMLIB2_LOADERS; do
            echo "    { \"$l\", &__imlib_loader_$l },"
        done
        echo '    { NULL, NULL }'
        echo '};'
    } > static_loaders.c
    for f in static_loaders decompress_load exif ldrs_util; do
        cc $cflags -DIMLIB2_STATIC_LOADERS -c $f.c -o $f.o
    done
    ar rcs /usr/lib/libImlib2.a static_*.o decompress_load.o exif.o ldrs_util.o
    touch /build/stamps/imlib2
    cd /build
fi

# feh: the image viewer.  The patch has it find its fonts and images next to
# where the program is, rather than in a directory fixed when it is built.
# inotify has it reload an image that changes on disk.
if [ ! -f stamps/feh ]; then
    echo "== feh"
    fetch https://feh.finalrewind.org/feh-$FEH.tar.bz2
    patch -p1 < /rdesk/build/patches/feh-data-path.patch > p.log
    # imlib2's pkg-config file lists none of the libraries it needs, so name
    # them all: its loaders', its fonts' and X's, in link order
    FEH_LIBS="-lImlib2 -lgif $($PKG_CONFIG --libs libpng libjpeg libwebpdemux \
        bzip2 zlib freetype2 x11-xcb xcb-shm xext x11) -lm"
    make -j "${JOBS:-8}" PREFIX=$PREFIX curl=0 exif=0 magic=0 xinerama=0 \
        inotify=1 help=1 LDLIBS="$FEH_LIBS" > m.log 2>&1
    install -D src/feh $PREFIX/bin/feh
    for d in fonts images; do   # the tarball has them readable only by owner
        mkdir -p $PREFIX/share/feh/$d
        install -m 644 share/$d/* $PREFIX/share/feh/$d/
    done
    touch /build/stamps/feh
fi

echo "== built binaries:"
for b in $PREFIX/bin/*; do
    printf '%s: %s\n' "$(basename "$b")" "$(file -b "$b" | cut -d, -f1-2)"
done
