#!/bin/sh
# Display: DSI -> anx7625 -> DisplayPort over the type-C dock.
#   ./display.sh [seconds of colour bars]
. "$(dirname "$0")/lib.sh"
S=${1:-8}
C=/sys/class/drm/card0-DP-1

section "connector"
[ -d $C ] || { fail "no DP connector"; summary; exit 1; }
st=$(cat $C/status); info "status $st, $(wc -c < $C/edid) bytes of EDID"
[ "$st" = connected ] && pass "monitor connected" || { skip "no monitor (board not on a dock)"; summary; exit 0; }
[ "$(wc -c < $C/edid)" -gt 0 ] && pass "EDID read over DP AUX" || fail "no EDID"
info "modes: $(tr '\n' ' ' < $C/modes)"

section "colour bars, $S s"
CONN=$(modetest -M msm 2>/dev/null | awk '/^Connectors/{f=1;next} f&&/^[0-9]/&&$3=="connected"{print $1; exit}')
CRTC=$(modetest -M msm 2>/dev/null | awk '/^CRTCs/{f=1;next} f&&/^[0-9]/{print $1; exit}')
MODE=$(head -1 $C/modes)
run_for "$S" modetest -M msm -s "$CONN@$CRTC:$MODE" >/tmp/modetest.log 2>&1
grep -q 'setting mode' /tmp/modetest.log && pass "$(grep -m1 'setting mode' /tmp/modetest.log)" || { fail "modeset"; tail -5 /tmp/modetest.log; }
summary
