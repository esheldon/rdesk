#!/bin/sh
# Build the rest of the session as static binaries: xkbcomp, xauth, fvwm, st.
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

# Static linking needs every dependency named explicitly, in dependent-first
# order; shared libraries would have carried these along themselves.
XLIBS_LINK="-lXrender -lXfixes -lXext -lSM -lICE -lfontconfig -lfreetype -lexpat \
-lpng16 -lbz2 -lbrotlidec -lbrotlicommon -lz -lxcb -lXau -lXdmcp -lm"

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

# fvwm 2: the window manager
if [ ! -f stamps/fvwm ]; then
    echo "== fvwm"
    fetch https://github.com/fvwmorg/fvwm/releases/download/$FVWM/fvwm-$FVWM.tar.gz

    # fvwm treats the first '+' anywhere in ModulePath/ImagePath as "the previous
    # path", so a directory whose name contains '+' breaks module loading.
    # Only accept '+' when it is a whole path element.
    python3 - <<'PYEOF'
src = open('libs/System.c').read()
old = """	int found_plus = strchr(newpath, '+') != NULL;"""
new = """	int found_plus = find_plus_element(stripped_path) != NULL;"""
assert old in src, "setPath not as expected"
src = src.replace(old, new)
old2 = """		char *p = strchr(*p_path, '+');
		memmove(p + oldlen, p + 1, strlen(p + 1) + 1);
		memmove(p, oldpath, oldlen);"""
new2 = """		char *p = find_plus_element(*p_path);

		if (p != NULL)
		{
			memmove(p + oldlen, p + 1, strlen(p + 1) + 1);
			memmove(p, oldpath, oldlen);
		}"""
assert old2 in src
src = src.replace(old2, new2)
helper = """/* A '+' is the "previous path" marker only when it is a whole element;
 * inside a directory name (/direct/astro+u/...) it is part of the name. */
static char *find_plus_element(char *path)
{
	char *p;

	for (p = strchr(path, '+'); p != NULL; p = strchr(p + 1, '+'))
	{
		if ((p == path || p[-1] == ':') && (p[1] == '\\0' || p[1] == ':'))
		{
			return p;
		}
	}

	return NULL;
}

void setPath(char **p_path, const char *newpath, int free_old_path)"""
src = src.replace("void setPath(char **p_path, const char *newpath, int free_old_path)", helper, 1)
open('libs/System.c', 'w').write(src)
print("patched libs/System.c")
PYEOF

    # -std=gnu17 -fpermissive: GCC 15 rejects some of fvwm's old C
    CFLAGS="-O2 -std=gnu17 -fpermissive" ./configure --prefix=$PREFIX \
        --disable-nls --disable-htmldoc --disable-mandoc --disable-iconv \
        LIBS="$XLIBS_LINK" > c.log 2>&1
    make -j "${JOBS:-8}" > m.log 2>&1
    make install > i.log 2>&1
    touch /build/stamps/fvwm
fi

# st: the terminal
if [ ! -f stamps/st ]; then
    echo "== st"
    fetch https://dl.suckless.org/st/st-$ST.tar.gz

    # Hack at a comfortable size, shipped in the bundle; st's default
    # (Liberation Mono, pixelsize 12, autohinted) is not in the bundle and
    # falls back to something small and rough.
    sed -i 's|^static char \*font = .*|static char *font = "Hack:pixelsize=15:antialias=true:autohint=false";|' config.def.h
    rm -f config.h

    # The mouse pointer.  For the I-beam shape the outline (mousebg) covers
    # twice the area of the body (mousefg), so the outline is what you see:
    # xterm's black-body-white-outline default is what makes its pointer look
    # light on a dark terminal.  Do the same, in this palette's colours.
    sed -i -e 's|^static unsigned int mousefg = .*|static unsigned int mousefg = 259;|' \
           -e 's|^static unsigned int mousebg = .*|static unsigned int mousebg = 258;|' config.def.h

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

    make PREFIX=$PREFIX LDFLAGS="-static" -j "${JOBS:-8}" \
        LIBS="-lX11 -lXft $XLIBS_LINK -lutil -lrt" > m.log 2>&1
    mkdir -p $PREFIX/bin $PREFIX/share/terminfo
    cp st $PREFIX/bin/
    tic -sx -o $PREFIX/share/terminfo st.info
    touch /build/stamps/st
fi

echo "== built binaries:"
for b in $PREFIX/bin/*; do
    printf '%s: %s\n' "$(basename "$b")" "$(file -b "$b" | cut -d, -f1-2)"
done
