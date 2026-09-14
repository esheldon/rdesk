#!/bin/sh
# Create the build environment: an Alpine Linux tree running under proot.
#
# Alpine is used because it is built on musl, which links statically without the
# warnings and pitfalls glibc has.  proot puts us "root" inside that tree using
# only ptrace, so no privileges are needed on the machine doing the build.
#
# Writes $WORK/enter, the wrapper every other build script is run through.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${RDESK_WORK:-$REPO/work}
. "$REPO/build/versions.sh"

MIRROR=https://dl-cdn.alpinelinux.org/alpine/$ALPINE_BRANCH
PROOT_URL=https://proot.gitlab.io/proot/bin/proot

mkdir -p "$WORK"

if [ ! -x "$WORK/proot" ]; then
    echo "== fetching proot"
    curl -fsSL -o "$WORK/proot.part" "$PROOT_URL"
    chmod +x "$WORK/proot.part"
    mv "$WORK/proot.part" "$WORK/proot"
fi

if [ ! -d "$WORK/root/etc" ]; then
    echo "== fetching the Alpine root filesystem"
    file=$(curl -fsSL "$MIRROR/releases/x86_64/latest-releases.yaml" |
           grep -oE 'alpine-minirootfs-[0-9.]+-x86_64\.tar\.gz' | head -n 1)
    curl -fsSL -o "$WORK/$file" "$MIRROR/releases/x86_64/$file"
    mkdir -p "$WORK/root"
    tar xzf "$WORK/$file" -C "$WORK/root"
fi

# how every build step is run: fake root inside the tree, this repo at /rdesk
cat > "$WORK/enter" <<EOF
#!/bin/sh
# run a command inside the Alpine build tree
exec $WORK/proot -0 -r $WORK/root -b /etc/resolv.conf -b /dev -b /proc \\
    -b $REPO:/rdesk -w /build \\
    /usr/bin/env -i HOME=/root LANG=C.UTF-8 \\
    PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \\
    JOBS=\${JOBS:-8} "\$@"
EOF
chmod +x "$WORK/enter"
mkdir -p "$WORK/root/build"

echo "== installing build packages"
"$WORK/enter" /bin/sh -c 'apk update -q && apk add -q \
    build-base autoconf automake libtool pkgconf cmake meson ninja bison flex \
    gettext-dev xz tar patch linux-headers perl python3 curl \
    xorgproto xtrans util-macros font-util-dev linux-pam-dev \
    zlib-dev zlib-static libjpeg-turbo-dev libjpeg-turbo-static \
    pixman-dev pixman-static freetype-dev freetype-static \
    fontconfig-dev fontconfig-static expat-dev expat-static \
    libpng-dev libpng-static bzip2-dev bzip2-static brotli-dev brotli-static \
    libx11-dev libx11-static libxcb-dev libxcb-static libxext-dev libxext-static \
    libice-dev libice-static nettle-dev nettle-static \
    libxtst-dev libxtst-static libxi-dev libxi-static \
    libxau-dev libxdmcp-dev libxrender-dev libxft-dev libxpm-dev \
    libxinerama-dev libxrandr-dev libxcursor-dev libxfixes-dev libxkbfile-dev \
    libxmu-dev libxt-dev libsm-dev libfontenc-dev libxfont2-dev \
    xkeyboard-config font-dejavu font-hack ncurses \
    openssl-dev openssl-libs-static'

# fvwm's configure runs "$PKG_CONFIG" as a single word, so --static has to be
# wrapped in a script rather than passed as part of the variable
"$WORK/enter" /bin/sh -c 'printf "#!/bin/sh\nexec pkg-config --static \"\$@\"\n" \
    > /usr/local/bin/pkg-config-static && chmod +x /usr/local/bin/pkg-config-static'

echo "== build environment ready in $WORK"
