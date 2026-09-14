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

echo "== built binaries:"
for b in $PREFIX/bin/*; do
    printf '%s: %s\n' "$(basename "$b")" "$(file -b "$b" | cut -d, -f1-2)"
done
