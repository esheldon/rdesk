#!/bin/sh
# Build the rest of the session as static binaries: xkbcomp, xauth, jwm and st.
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

# st: the terminal.  The desktop needs one of its own, since not every host
# has xterm; st is small, static and needs nothing but X and a font.
if [ ! -f /build/stamps/st ]; then
    echo "== st"
    fetch https://dl.suckless.org/st/st-$ST.tar.gz

    # Inconsolata, shipped in the bundle; st's default (Liberation Mono,
    # pixelsize 12, autohinted) is not, and falls back to something small and
    # rough.  Pixelsize 17 because Inconsolata draws smaller than most fonts
    # at a given size: it gives a 9x19 cell, near the 9x18 of the Hack at 15
    # this used to be.  st sizes its cell from the average advance of the
    # ASCII characters, so Inconsolata 3's wide ligature glyphs do not
    # stretch it the way they stretch xterm's.
    sed -i 's|^static char \*font = .*|static char *font = "Inconsolata:pixelsize=17:antialias=true:autohint=false";|' config.def.h
    rm -f config.h

    # Colours, which st compiles in.  The stock palette is hard to read on a
    # dark background; entries not changed here keep st's own defaults.
    python3 - <<'PYEOF'
import re

palette = '''static const char *colorname[] = {
	/* 8 normal colors */
	"#000000",	/* black */
	"#ff6600",	/* red: an orange red */
	"#99ff99",	/* green: lighter */
	"#ffff66",	/* yellow: brighter */
	"#99ccff",	/* blue: brighter */
	"#dda0dd",	/* magenta: plum */
	"#00cdcd",	/* cyan3, xterm's default */
	"#e5e5e5",	/* gray90, xterm's default */

	/* 8 bright colors */
	"#7f7f7f",	/* gray50, xterm's default */
	"#ff6600",	/* bright red: orange */
	"#99ff99",	/* bright green */
	"#ffff66",	/* bright yellow */
	"#99ccff",	/* bright blue */
	"#ff6699",	/* bright magenta: less harsh */
	"#00ffff",	/* cyan, xterm's default */
	"#ffffff",	/* white, xterm's default */

	[255] = 0,

	/* more colors can be added after 255 to use with DefaultXX */
	"#fffbe5",	/* 256: cursor */
	"#555555",	/* 257: cursor inside a selection or in reverse video,
			   where it is drawn against a light background, so it
			   must not be the background colour itself */
	"#fffbe5",	/* 258: default foreground colour */
	"#1f1f1f",	/* 259: default background colour */
};
'''

src = open('config.def.h').read()
m = re.search(r'static const char \*colorname\[\] = \{.*?\n\};\n', src, re.S)
assert m and '8 normal colors' in m.group(0), "colour table not as expected"
open('config.def.h', 'w').write(src[:m.start()] + palette + src[m.end():])
print("patched colours")
PYEOF

    # A static musl binary can only read /etc/passwd, so users defined in LDAP
    # or SSSD aren't found.  Fall back to the environment instead of dying.
    python3 - <<'PYEOF'
src = open('st.c').read()
old_check = """	errno = 0;
	if ((pw = getpwuid(getuid())) == NULL) {
		if (errno)
			die("getpwuid: %s\\n", strerror(errno));
		else
			die("who are you?\\n");
	}
"""
new_check = """	errno = 0;
	pw = getpwuid(getuid());	/* may be NULL for LDAP/SSSD users */
"""
assert old_check in src, "getpwuid block not found"
src = src.replace(old_check, new_check)
subs = [
    ("sh = (pw->pw_shell[0]) ? pw->pw_shell : cmd;",
     "sh = (pw && pw->pw_shell[0]) ? pw->pw_shell : cmd;"),
    ('setenv("LOGNAME", pw->pw_name, 1);',
     'if (pw) setenv("LOGNAME", pw->pw_name, 1);'),
    ('setenv("USER", pw->pw_name, 1);',
     'if (pw) setenv("USER", pw->pw_name, 1);'),
    ('setenv("HOME", pw->pw_dir, 1);',
     'if (pw) setenv("HOME", pw->pw_dir, 1);'),
]
for old, new in subs:
    assert old in src, old
    src = src.replace(old, new)
open('st.c', 'w').write(src)
print("patched st.c")
PYEOF

    # st's Makefile names only the libraries a shared link needs, so give it
    # every one, in link order, as the jwm build does
    ST_LIBS="$($PKG_CONFIG --libs xft fontconfig freetype2 x11) -lutil -lrt -lm"
    make PREFIX=$PREFIX LDFLAGS="-static" -j "${JOBS:-8}" \
        LIBS="$ST_LIBS" > m.log 2>&1
    mkdir -p $PREFIX/bin $PREFIX/share/terminfo
    cp st $PREFIX/bin/
    tic -sx -o $PREFIX/share/terminfo st.info
    touch /build/stamps/st
fi

echo "== built binaries:"
for b in $PREFIX/bin/*; do
    printf '%s: %s\n' "$(basename "$b")" "$(file -b "$b" | cut -d, -f1-2)"
done
