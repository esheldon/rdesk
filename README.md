# rdesk — a remote desktop that needs no root

A persistent desktop on a remote host, reached over SSH from your own machine,
in the spirit of ThinLinc. Nothing is installed system-wide and nothing runs as
root: you unpack a directory in your home and start a session as yourself.

The remote side is a single bundle of statically linked programs, so it does not
care how old the host is, which libraries it has, or what your login environment
sets. It runs on anything x86_64 with a Linux kernel — a CentOS 7 host with no X
libraries and no fonts works fine.

    your machine                        remote host
    ┌───────────┐    ssh tunnel    ┌──────────────────────────┐
    │ vncviewer │◀─── socket ─────▶│  Xvnc ── fvwm ── apps    │
    └───────────┘                  └──────────────────────────┘

Closing the viewer leaves everything running; connect again and your windows are
where you left them.


## What is here

| File | What it is |
|---|---|
| `rdesk` | the command you run on your own machine |
| `rdesk-session` | runs on the host to start, stop and report on a session |
| `fvwm.rdesk` | example window manager configuration for remote sessions |
| `build/` | builds the bundle from source |

The bundle itself is not in the repository: build it with `build/build.sh`,
which writes `work/rdesk-static-x86_64.tar.gz`.


## Install on a host

```sh
# install the bundle
scp rdesk-static-x86_64.tar.gz fvwm.rdesk host:
# on the host. Remove any existing install first
rm -rf ~/local/rdesk &&
tar xzf rdesk-static-x86_64.tar.gz -C ~/local

# if you want to install the provided fvwm config (you can use your own)
scp fvwm.rdesk host:
# on the host
mkdir -p ~/.fvwm
cp fvwm.rdesk ~/.fvwm/config
```

That gives `~/local/rdesk`, which is where `rdesk` looks by default. Any other
path works too — tell `rdesk` about it with `RDESK_REMOTE`. If your home
directory is shared between hosts, install it once and every host has it.

Use the same commands to update: the `rm -rf` matters, because unpacking over
an old bundle keeps files the new one no longer ships, and a stale font or
program can then shadow the new one. Removing the directory under a running
session is safe; the next `rdesk host stop` and reconnect picks up the new
programs.

## Use it

```sh
rdesk host          # connect, starting a session if none is running
rdesk host stop     # end the session
```

You need a VNC viewer on your own machine (`tigervnc-viewer` on most
distributions). Everything goes through one SSH connection, so you are asked for
a password or passphrase at most once.

There is one session per host. `rdesk host` reconnects to it as often as you
like; only `rdesk host stop` ends it. Connecting from a second machine takes
the session over: the first viewer is disconnected, the desktop carries on.


## Using the desktop

Everything is done with the mouse, and no binding uses a modifier key, so Alt,
Super and Tab all reach the programs you are running rather than being caught by
the window manager at either end.

If you are familiar with fvwm, it should go smoothly.  With the default config,
click on the desktop background to see a menu, which can launch a terminal
(xterm).

The desktop starts at 1920x1200 and follows your viewer window when you resize
or maximize it.

To end a session, use `rdesk host stop` from your own machine. There is
deliberately no "quit" entry in the menus.

## Settings

On your machine, as environment variables for `rdesk`:

| Variable | Default | For |
|---|---|---|
| `RDESK_SSH` | `ssh` | e.g. `"ssh -J gateway"`; `~/.ssh/config` is used either way |
| `RDESK_VIEWER` | `vncviewer` | another viewer, or one with options |
| `RDESK_REMOTE` | `~/local/rdesk/bin/rdesk-session` | if the bundle is elsewhere on the host |

On the host:

| Variable | Default | For |
|---|---|---|
| `RDESK_GEOMETRY` | `1920x1200` | the desktop's initial size |

The terminal the desktop opens is set by one line in `~/.fvwm/fvwm.rdesk`,
and it comes from the host rather than the bundle:

```
InfoStoreAdd terminal xterm -fa Hack -fs 13
```

The file is read afresh each session, and "Restart fvwm" in the menu reloads it.

Fonts come from two places. Scalable fonts go through fontconfig, which sees
the host's fonts plus the bundle's own: `Inconsolata`, `Hack`, `DejaVu Sans`,
`DejaVu Sans Mono` and `DejaVu Serif` — so `xterm -fa Inconsolata` works on
every host. Old-style bitmap fonts such as `fixed` are served by the display
server itself; the bundle carries the full `misc-fixed` family, so `fixed`
has its complete Unicode coverage everywhere, and any core font directories
the host has are added to the server's font path as well.

To use your own `~/.fvwm/config` on a host instead, delete `~/.fvwm/fvwm.rdesk`
there. Be aware that a configuration written for a local desktop usually binds
keys and Alt-drags that the window manager on your own machine swallows first.


## Commands on the host

```sh
ssh host '~/local/rdesk/bin/rdesk-session version'   # which bundle is installed
ssh host '~/local/rdesk/bin/rdesk-session status'    # is a session running
ssh host '~/local/rdesk/bin/rdesk-session log 40'    # what the session reported
ssh host '~/local/rdesk/bin/rdesk-session stop'      # same as rdesk host stop
```


## How it works

`Xvnc` from TigerVNC is both the X server and the VNC server — the same engine
ThinLinc uses — so the desktop lives entirely on the host and only compressed
screen updates cross the network. fvwm manages the windows; the programs you
run, terminal included, come from the host.

The session listens on a Unix socket that only your account can open, with no
network listener at all, and the X display is protected by a cookie in your
private runtime directory. `rdesk` forwards that socket through your SSH
connection, so nothing is exposed even on a host with thousands of users.


## Limits

- **x86_64 Linux only**, though any kernel and any glibc: the programs are static.
- **No OpenGL** and **no sound**.
- **One session per host.**
- On load-balanced login pools, connect to a specific node's name, or you may not
  land on the node where your session is running.
- Programs you run inside the session come from the host, so they need whatever
  they normally need. The bundle provides the desktop, not the applications:
  the terminal is the host's `xterm`.


## If something looks wrong

Start with `rdesk-session version` and `rdesk-session log 40` on the host.

- **Modules missing** (no pager) with errors naming `/opt/rdesk/...`: the host has
  an older bundle. Install the current one and restart the session.
- **Changes not taking effect:** a running session keeps the old programs and
  configuration. `rdesk host stop`, then connect again.
- **A session that will not start:** the log names the reason; `rdesk host stop`
  clears a half-dead one.
- **A session gone after logging out of the host:** some sites configure
  systemd to kill a user's processes when their last login ends
  (`KillUserProcesses=yes`), which takes the desktop with it. Ask for lingering
  once with `loginctl enable-linger`, and sessions survive logouts. A host that
  merely clears your runtime directory at logout leaves the session running
  with its bookkeeping gone; `rdesk-session stop` still finds and stops it.
- **Missing PATH entries in the desktop's terminals:** the desktop is started
  through your login shell, so `/etc/profile`, `/etc/profile.d` and your own
  profile all apply. If something is still missing, it is set only for
  interactive shells on that host.


## Building the bundle

```sh
build/build.sh
```

Needs `curl`, about 3 GB of disk and roughly half an hour. No privileges are
needed anywhere: the build runs in an Alpine Linux tree under `proot`, which
gives a fake root using only ptrace. Alpine is used because its musl C library
links statically without glibc's warnings and pitfalls.

Everything lands in `work/` (override with `RDESK_WORK`), ending with
`work/rdesk-static-x86_64.tar.gz`. Finished steps are skipped on a re-run, so
fixing one thing is cheap; delete `work/` to start over. `JOBS` sets build
parallelism.

| Script | What it does |
|---|---|
| `build/build.sh` | runs everything below in order |
| `build/versions.sh` | the pinned source versions |
| `build/bootstrap.sh` | fetches proot and Alpine, installs build packages |
| `build/libs.sh` | the X libraries Alpine has no static packages for |
| `build/pam.sh` | a static `libpam.a`, which TigerVNC insists on linking |
| `build/xvnc.sh` | `Xvnc`: TigerVNC's server code patched into the X.Org server |
| `build/apps.sh` | `xkbcomp`, `xauth` and fvwm |
| `build/assemble.sh` | collects it all into the bundle and the tarball |

One patch is applied to an upstream source during the build, in `apps.sh`:

- **fvwm** treats the first `+` anywhere in `ModulePath`/`ImagePath` as "the
  previous path", which breaks any installation under a directory whose name
  contains `+`. It now only does that for a `+` that is a whole path element.

`Xvnc` is built with an empty xkb binary directory so it finds `xkbcomp` on
`PATH`, which is what lets the bundle work from any location.
