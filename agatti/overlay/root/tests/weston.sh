#!/bin/sh
# Start Weston on the monitor with two GL demo clients. Stop with
# 'killall weston'. Needs the dock.
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
killall weston 2>/dev/null
weston --backend=drm --log=/tmp/weston.log &
for i in 1 2 3 4 5 6 7 8 9 10; do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 1; done
export WAYLAND_DISPLAY=wayland-1
[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || { echo "weston did not start, see /tmp/weston.log"; tail -5 /tmp/weston.log; exit 1; }
weston-simple-egl & weston-flower &
echo "weston running (log /tmp/weston.log); 'killall weston' to stop"
