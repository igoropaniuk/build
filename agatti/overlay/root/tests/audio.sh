#!/bin/sh
# DRAFT: audio on the PM4125 analog codec (headphone / line out) behind
# the ADSP. Needs the sound card in the device tree (not ported yet) and
# headphones or a speaker on the board's headphone/line-out pins.
#   ./audio.sh
. "$(dirname "$0")/lib.sh"
R=$(dirname "$(grep -l adsp /sys/class/remoteproc/*/name 2>/dev/null | head -1)")
section "ADSP"
if [ -d "$R" ]; then
	[ "$(cat $R/state)" = running ] || { echo start > $R/state; sleep 3; }
	[ "$(cat $R/state)" = running ] && pass "ADSP running" || fail "ADSP state $(cat $R/state)"
else
	fail "no adsp remoteproc"
fi
section "sound card"
sleep 2
# The kernel's snd-aloop Loopback card is always there; look for real hardware.
CARD=$(aplay -l 2>/dev/null | grep '^card' | grep -v Loopback | head -1)
if [ -n "$CARD" ]; then
	pass "$CARD"
	N=$(echo "$CARD" | sed 's/^card \([0-9]*\).*/\1/')
	amixer -c "$N" scontrols 2>/dev/null | head -20 | sed 's/^/  /'
	section "tone (2 s per channel)"
	speaker-test -D "plughw:$N,0" -c 2 -t sine -f 440 -l 1 >/tmp/speaker.log 2>&1 && pass "speaker-test ran (listen on the headphone/line out)" || { fail "speaker-test"; tail -5 /tmp/speaker.log; }
else
	skip "no sound card: the UNO Q sound node is not in the device tree yet"
fi
summary
