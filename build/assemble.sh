#!/bin/bash
# Collect the built programs and data into the bundle, and pack it up.
# Runs outside the Alpine tree, on the machine doing the build.

set -euo pipefail

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${RDESK_WORK:-$REPO/work}
A=$WORK/root            # the Alpine tree
R=$A/opt/rdesk          # where its builds were installed
OUT=${RDESK_OUT:-$WORK/rdesk}
TARBALL=${RDESK_TARBALL:-$WORK/rdesk-static-x86_64.tar.gz}

[ -d "$R/bin" ] || { echo "nothing built yet in $R; run build/build.sh" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"/{bin,share/jwm,share/X11,share/fonts,share/xfonts,cache}

# programs
cp "$A/build/tvbuild/unix/xserver/hw/vnc/Xvnc" "$OUT/bin/"
for b in jwm xauth xkbcomp; do
    cp "$R/bin/$b" "$OUT/bin/"
done

# the optional programs, with feh's fonts and images
if [ "${RDESK_X11PROGRAMS:-0}" = 1 ]; then
    X=$A/opt/x11programs
    [ -x "$X/bin/mupdf" ] && [ -x "$X/bin/feh" ] || {
        echo "mupdf and feh are not built yet in $X; run build/build.sh with RDESK_X11PROGRAMS=1" >&2
        exit 1
    }
    cp "$X/bin/mupdf" "$X/bin/feh" "$OUT/bin/"
    cp -r "$X/share/feh" "$OUT/share/"
fi

strip "$OUT"/bin/* 2>/dev/null || true

# data: keyboard data
cp -r "$A/usr/share/X11/xkb" "$OUT/share/X11/"

# fonts, for the window manager and for anything started in the session
for f in DejaVuSans DejaVuSans-Bold DejaVuSansMono DejaVuSansMono-Bold \
         DejaVuSerif DejaVuSerif-Bold; do
    cp "$A/usr/share/fonts/dejavu/$f.ttf" "$OUT/share/fonts/"
done
cp "$A"/usr/share/fonts/hack/Hack-{Regular,Bold,Italic,BoldItalic}.ttf "$OUT/share/fonts/"
# Inconsolata 3: only the normal width, of its many.  xterm spaces its cells
# too wide with this version (it sizes them by the widest glyph, a ligature);
# terminals that size cells by an ordinary character, such as alacritty, are fine.
cp "$A"/usr/share/fonts/inconsolata/Inconsolata-{Regular,Medium,Bold}.otf "$OUT/share/fonts/"
# JuliaMono for its symbol coverage: a monospaced fallback for the symbols
# terminal programs draw that no other font here has, such as the ⛶ and ⛝ of
# Claude Code's /context.
cp "$A/usr/share/fonts/juliamono/JuliaMono-Regular.ttf" "$OUT/share/fonts/"

# core (bitmap) fonts, served by Xvnc itself: the misc-fixed family, so that
# "fixed" has full Unicode coverage rather than the server's Latin-1 built-in.
# Kept apart from share/fonts so fontconfig does not index them.
cp -r "$A/usr/share/fonts/misc" "$OUT/share/xfonts/"

# the parts kept in this repo
cp "$REPO/jwm.rdesk" "$OUT/share/jwm/jwm.rdesk"
cp "$REPO/rdesk-session" "$OUT/bin/rdesk-session"
chmod +x "$OUT/bin/rdesk-session"

tar czf "$TARBALL" --transform "s|^$(basename "$OUT")|rdesk|" \
    -C "$(dirname "$OUT")" "$(basename "$OUT")"

echo "== bundle:  $OUT  ($(du -sh "$OUT" | cut -f1))"
echo "== tarball: $TARBALL  ($(du -h "$TARBALL" | cut -f1))"
