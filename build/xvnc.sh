#!/bin/sh
# Build a static Xvnc: TigerVNC's server code patched into the X.Org server.
# Runs inside the Alpine build tree (see bootstrap.sh).

set -e
. /rdesk/build/versions.sh
cd /build
mkdir -p src stamps

TV=/build/src/tigervnc-$TIGERVNC
XS=/build/src/xorg-server-$XSERVER
B=/build/tvbuild

# sources
cd /build/src
if [ ! -d "$TV" ]; then
    file=tigervnc-$TIGERVNC.tar.gz
    [ -f "$file" ] ||
        curl -fsSL -o "$file" "https://github.com/TigerVNC/tigervnc/archive/refs/tags/v$TIGERVNC.tar.gz"
    busybox tar xf "$file"
fi
if [ ! -d "$XS" ]; then
    file=xorg-server-$XSERVER.tar.xz
    [ -f "$file" ] ||
        curl -fsSLO "https://www.x.org/releases/individual/xserver/$file"
    busybox tar xf "$file"
fi

# 1. TigerVNC's own libraries (no viewer, no optional crypto or codecs)
if [ ! -f /build/stamps/tigervnc-common ]; then
    echo "== building TigerVNC libraries"
    mkdir -p $B && cd $B
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_VIEWER=OFF -DENABLE_GNUTLS=OFF -DENABLE_NETTLE=OFF \
        -DENABLE_H264=OFF $TV > /build/tv-cmake.log 2>&1
    make -j "${JOBS:-8}" > /build/tv-make.log 2>&1
    touch /build/stamps/tigervnc-common
    cd /build
fi

# 2. the X server, with TigerVNC's vnc device patched in.  The patch is
#    TigerVNC's own (unix/xserver21.patch): it adds hw/vnc to the server's
#    build, it does not change how the server itself behaves.
if [ ! -f /build/stamps/xvnc-configure ]; then
    echo "== preparing and configuring the X server"
    rm -rf $B/unix/xserver
    mkdir -p $B/unix
    cp -R $TV/unix/xserver $B/unix/
    cp -R $XS/* $B/unix/xserver/
    cd $B/unix/xserver
    patch -p1 < $TV/unix/xserver21.patch > /build/xvnc-patch.log 2>&1
    autoreconf -fiv > /build/xvnc-autoreconf.log 2>&1

    # No dri/glx/glamor: those need mesa.  Fonts come from the server's
    # built-ins.  An empty xkb-bin-directory makes the server look xkbcomp up on
    # PATH, so the bundle's copy is used wherever the bundle is unpacked; the xkb
    # data directory is given at run time with -xkbdir.
    ./configure --with-pic --without-dtrace --disable-static \
        --disable-dri --disable-dri2 --disable-dri3 --disable-glx --disable-glamor \
        --disable-xvfb --disable-xnest --disable-xorg --disable-dmx --disable-xwin \
        --disable-xephyr --disable-kdrive --disable-xwayland \
        --disable-config-hal --disable-config-udev --disable-systemd-logind \
        --disable-libunwind --disable-selective-werror --disable-unit-tests \
        --disable-docs --disable-devel-docs \
        --with-sha1=libnettle \
        --with-default-font-path="built-ins" \
        --with-xkb-path=/usr/share/X11/xkb \
        --with-xkb-output=/tmp \
        --with-xkb-bin-directory= \
        LIBS="-lfontenc -lfreetype -lpng16 -lbz2 -lbrotlidec -lbrotlicommon -lz -lm" \
        > /build/xvnc-configure.log 2>&1
    touch /build/stamps/xvnc-configure
fi

# 3. link it statically
echo "== building Xvnc"
cd $B/unix/xserver
make TIGERVNC_SRCDIR=$TV TIGERVNC_BUILDDIR=$B LDFLAGS="-all-static" \
    -j "${JOBS:-8}" > /build/xvnc-make.log 2>&1
file hw/vnc/Xvnc
