#!/bin/sh
# Build the whole bundle from source, with no privileges anywhere.
#
#   build/build.sh
#
# Everything lands in ./work (override with RDESK_WORK): an Alpine Linux tree,
# the sources, and finally work/rdesk-static-x86_64.tar.gz.  Steps that have
# already finished are skipped, so re-running after a fix is cheap; to start
# over, delete the work directory.
#
# Needs: curl, tar, and roughly 3 GB of disk.  Takes about half an hour.
# Set JOBS to change build parallelism (default 8), and RDESK_X11PROGRAMS=1 to
# add the optional programs, mupdf and feh, for hosts that lack such programs.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=${RDESK_WORK:-$REPO/work}
export RDESK_WORK=$WORK

"$REPO/build/bootstrap.sh"

"$WORK/enter" /bin/sh /rdesk/build/libs.sh
"$WORK/enter" /bin/sh /rdesk/build/pam.sh
"$WORK/enter" /bin/sh /rdesk/build/xvnc.sh
"$WORK/enter" /bin/sh /rdesk/build/apps.sh
if [ "${RDESK_X11PROGRAMS:-0}" = 1 ]; then
    "$WORK/enter" /bin/sh /rdesk/build/x11programs.sh
fi

"$REPO/build/assemble.sh"
