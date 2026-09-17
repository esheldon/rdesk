# Source versions the bundle is built from.  Pinned so a rebuild produces the
# same thing; bump deliberately.

ALPINE_BRANCH=v3.24

TIGERVNC=1.16.2
XSERVER=21.1.24
JWM=2.4.6
PANGO=1.57.1
XKBCOMP=1.5.0
XAUTH=1.1.5
LINUX_PAM=1.7.2

# X libraries Alpine ships without a static build, in dependency order
XLIBS="libXau-1.0.12 libXdmcp-1.1.5 libfontenc-1.1.9 libXfont2-2.0.9
       libXfixes-6.0.2 libXrender-0.9.12 libXrandr-1.5.5 libXcursor-1.2.3
       libXinerama-1.1.6 libXft-2.3.9 libXpm-3.5.19 libxkbfile-1.2.0
       libSM-1.2.6 libXt-1.3.1 libXmu-1.3.1"
