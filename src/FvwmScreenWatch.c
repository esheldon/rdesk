/*
 * FvwmScreenWatch: an fvwm module that runs an fvwm command once the screen
 * has changed size.
 *
 *   Module FvwmScreenWatch [command]      (default command: Restart)
 *
 * fvwm 2 never notices a RandR resize of the screen: its RandR support is
 * compiled out upstream.  After the VNC viewer resizes the desktop, fvwm
 * still maximizes and places windows for the old size, and anything anchored
 * to the bottom or right edge stays where the old edge was.  A Restart makes
 * fvwm read the real screen size again, keeps every window where it is, and
 * takes well under a second.
 *
 * Resizes come in bursts while a viewer window is being dragged, so the
 * command runs only once the size has held still for a moment.
 */

#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <X11/Xlib.h>

#define SETTLE_MS 500

static int to_fvwm, from_fvwm;

/* The module pipe protocol: window id, text length, the text, then a
 * "continue" flag, all as unsigned longs (see libs/Module.c in fvwm). */
static void send_text(const char *text)
{
	unsigned long window = 0, len = strlen(text), cont = 1;

	if (write(to_fvwm, &window, sizeof window) < 0 ||
	    write(to_fvwm, &len, sizeof len) < 0 ||
	    write(to_fvwm, text, len) < 0 ||
	    write(to_fvwm, &cont, sizeof cont) < 0)
	{
		exit(0);
	}
}

/* Discard whatever fvwm sends us; exit when it goes away. */
static void drain_fvwm(void)
{
	char buf[4096];
	ssize_t n = read(from_fvwm, buf, sizeof buf);

	if (n == 0 || (n < 0 && errno != EINTR && errno != EAGAIN))
	{
		exit(0);
	}
}

int main(int argc, char *argv[])
{
	Display *dpy;
	Window root;
	struct pollfd fds[2];
	char command[1024] = "";
	int width, height, seen_w, seen_h, pending = 0, i;

	if (argc < 6)
	{
		fprintf(stderr, "%s: must be started by fvwm as a module\n",
			argv[0]);
		return 1;
	}
	to_fvwm = atoi(argv[1]);
	from_fvwm = atoi(argv[2]);
	for (i = 6; i < argc; i++)
	{
		if (strlen(command) + strlen(argv[i]) + 2 > sizeof command)
		{
			break;
		}
		if (command[0])
		{
			strcat(command, " ");
		}
		strcat(command, argv[i]);
	}
	if (!command[0])
	{
		strcpy(command, "Restart");
	}

	dpy = XOpenDisplay(NULL);
	if (!dpy)
	{
		fprintf(stderr, "FvwmScreenWatch: cannot open display\n");
		return 1;
	}
	root = DefaultRootWindow(dpy);
	XSelectInput(dpy, root, StructureNotifyMask);
	width = seen_w = DisplayWidth(dpy, DefaultScreen(dpy));
	height = seen_h = DisplayHeight(dpy, DefaultScreen(dpy));

	send_text("SET_MASK 0");
	send_text("NOP FINISHED STARTUP");

	fds[0].fd = ConnectionNumber(dpy);
	fds[0].events = POLLIN;
	fds[1].fd = from_fvwm;
	fds[1].events = POLLIN;

	for (;;)
	{
		int n;

		while (XPending(dpy))
		{
			XEvent ev;

			XNextEvent(dpy, &ev);
			if (ev.type == ConfigureNotify &&
			    ev.xconfigure.window == root)
			{
				seen_w = ev.xconfigure.width;
				seen_h = ev.xconfigure.height;
				pending = 1;
			}
		}
		n = poll(fds, 2, pending ? SETTLE_MS : -1);
		if (n < 0 && errno != EINTR)
		{
			return 1;
		}
		if (n > 0 && (fds[1].revents & (POLLIN | POLLHUP | POLLERR)))
		{
			drain_fvwm();
		}
		if (n == 0 && pending)
		{
			/* the size has held still */
			pending = 0;
			if (seen_w != width || seen_h != height)
			{
				width = seen_w;
				height = seen_h;
				send_text(command);
			}
		}
	}
}
