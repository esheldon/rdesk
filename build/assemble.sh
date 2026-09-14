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
mkdir -p "$OUT"/{bin,libexec/fvwm/2.7.0,share/fvwm,share/X11,share/fonts,share/xfonts,cache}

# programs
cp "$A/build/tvbuild/unix/xserver/hw/vnc/Xvnc" "$OUT/bin/"
for b in fvwm fvwm-root xauth xkbcomp FvwmCommand; do
    [ -f "$R/bin/$b" ] && cp "$R/bin/$b" "$OUT/bin/"
done

# only the fvwm modules a session can use
for m in FvwmButtons FvwmPager FvwmIconMan FvwmEvent FvwmBanner FvwmScript \
         FvwmConsole FvwmForm FvwmCommandS FvwmBacker FvwmAnimate FvwmIdent; do
    [ -f "$R/libexec/fvwm/2.7.0/$m" ] && cp "$R/libexec/fvwm/2.7.0/$m" "$OUT/libexec/fvwm/2.7.0/"
done

strip "$OUT"/bin/* "$OUT"/libexec/fvwm/2.7.0/* 2>/dev/null || true

# data: fvwm's stock config and images, keyboard data
cp -r "$R/share/fvwm/." "$OUT/share/fvwm/"
cp -r "$A/usr/share/X11/xkb" "$OUT/share/X11/"

# fonts, for the window manager and for anything started in the session
for f in DejaVuSans DejaVuSans-Bold DejaVuSansMono DejaVuSansMono-Bold \
         DejaVuSerif DejaVuSerif-Bold; do
    cp "$A/usr/share/fonts/dejavu/$f.ttf" "$OUT/share/fonts/"
done
cp "$A"/usr/share/fonts/hack/Hack-{Regular,Bold,Italic,BoldItalic}.ttf "$OUT/share/fonts/"
cp "$A/usr/share/fonts/inconsolata-classic/Inconsolata.otf" "$OUT/share/fonts/"

# core (bitmap) fonts, served by Xvnc itself: the misc-fixed family, so that
# "fixed" has full Unicode coverage rather than the server's Latin-1 built-in.
# Kept apart from share/fonts so fontconfig does not index them.
cp -r "$A/usr/share/fonts/misc" "$OUT/share/xfonts/"

# the parts kept in this repo
cp "$REPO/fvwm.rdesk" "$OUT/share/fvwm/fvwm.rdesk"
cp "$REPO/rdesk-session" "$OUT/bin/rdesk-session"
chmod +x "$OUT/bin/rdesk-session"

tar czf "$TARBALL" --transform "s|^$(basename "$OUT")|rdesk|" \
    -C "$(dirname "$OUT")" "$(basename "$OUT")"

echo "== bundle:  $OUT  ($(du -sh "$OUT" | cut -f1))"
echo "== tarball: $TARBALL  ($(du -h "$TARBALL" | cut -f1))"
