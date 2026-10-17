#!/bin/sh
# GPU (Adreno A702 through freedreno). Rendering tests need a monitor on
# the dock: kmscube and glmark2 scan out to the DP connector.
#   ./gpu.sh [kmscube-frames]
. "$(dirname "$0")/lib.sh"
N=${1:-300}

section "kernel side"
[ -e /dev/dri/card0 ] && pass "/dev/dri/card0" || fail "no /dev/dri/card0"
[ -e /dev/dri/renderD128 ] && pass "/dev/dri/renderD128" || fail "no render node"
dmesg | grep -q 'a702_sqe.fw' && pass "SQE microcode loaded" || fail "SQE microcode not loaded"
dmesg | grep -qi 'zap' && info "$(dmesg | grep -i 'zap' | tail -1)"

section "rendering"
if grep -q '^connected' /sys/class/drm/card0-*/status 2>/dev/null; then
	kmscube -D /dev/dri/card0 -c "$N" >/tmp/kmscube.log 2>&1
	r=$(grep -m1 'renderer' /tmp/kmscube.log); f=$(grep 'Rendered' /tmp/kmscube.log | tail -1)
	[ -n "$f" ] && pass "kmscube $r, $f" || { fail "kmscube"; tail -5 /tmp/kmscube.log; }
	glmark2-es2-drm -b build:duration=5 -b texture:duration=5 -b shading:duration=5 >/tmp/glmark2.log 2>&1
	s=$(grep 'glmark2 Score' /tmp/glmark2.log)
	[ -n "$s" ] && { pass "glmark2 $(echo $s)"; grep 'FPS' /tmp/glmark2.log | sed 's/^/  /'; } || { fail "glmark2"; tail -5 /tmp/glmark2.log; }
else
	skip "no monitor connected: kmscube and glmark2 need the dock"
fi

section "faults"
faults
summary
