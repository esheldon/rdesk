#!/bin/sh
# Build a static libpam.a.
#
# TigerVNC always links PAM, for the "Plain" password security type we never
# use.  Alpine has no static PAM package, and Linux-PAM's build only produces a
# shared library, so the library objects are archived by hand.  Nothing is
# installed: only /usr/lib/libpam.a is added, next to Alpine's headers.
#
# Runs inside the Alpine build tree (see bootstrap.sh).

set -e
. /rdesk/build/versions.sh
cd /build
mkdir -p src stamps

if [ -f stamps/pam ]; then
    echo "== pam already built"
    exit 0
fi

cd src
file=Linux-PAM-$LINUX_PAM.tar.xz
[ -f "$file" ] ||
    curl -fsSLO "https://github.com/linux-pam/linux-pam/releases/download/v$LINUX_PAM/$file"
rm -rf "Linux-PAM-$LINUX_PAM"
busybox tar xf "$file"
cd "Linux-PAM-$LINUX_PAM"

meson setup build --prefix=/usr --libdir=lib --buildtype=release \
    -Ddocs=disabled -Di18n=disabled -Dexamples=false -Dselinux=disabled \
    -Daudit=disabled -Deconf=disabled -Dlogind=disabled -Dopenssl=disabled \
    -Dnis=disabled -Dpam_userdb=disabled > meson.log 2>&1
ninja -C build > ninja.log 2>&1

ar rcs /usr/lib/libpam.a $(find build/libpam build/libpam_internal -name '*.o')
ranlib /usr/lib/libpam.a

touch /build/stamps/pam
echo "== libpam.a built"
