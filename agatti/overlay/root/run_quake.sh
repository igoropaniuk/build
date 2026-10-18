#!/bin/sh
# Run OpenArena (or Quake III if baseq3 has data) on ioquake3, full screen
# on the DP monitor through KMS/DRM + OpenGL ES. Extra arguments go to the
# engine, e.g.  ./run_quake.sh +map oa_dm1   or   ./run_quake.sh +set cl_renderer opengl2
# Quit: ~ opens the console, then \quit; or Ctrl-C.

BASE=/usr/lib/ioquake3

if ls $BASE/baseoa/*.pk3 >/dev/null 2>&1; then
	GAME=baseoa
elif ls $BASE/baseq3/pak0.pk3 >/dev/null 2>&1; then
	GAME=baseq3
else
	echo "no game data: copy OpenArena's baseoa/*.pk3 to $BASE/baseoa/"
	echo "(or Quake III's baseq3/pak*.pk3 to $BASE/baseq3/)"
	exit 1
fi

if ! grep -q '^connected$' /sys/class/drm/card*-DP-*/status 2>/dev/null; then
	echo "no monitor on the DP output (dock)"
	exit 1
fi

# KMS needs the display: stop Weston if it holds it
killall weston 2>/dev/null && sleep 1

export SDL_VIDEODRIVER=kmsdrm
exec $BASE/ioquake3 \
	+set fs_basepath $BASE \
	+set com_basegame $GAME \
	+set r_preferOpenGLES 1 \
	+set r_fullscreen 1 \
	+set r_mode -2 \
	"$@"
