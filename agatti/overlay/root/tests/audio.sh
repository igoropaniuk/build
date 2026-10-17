#!/bin/sh
# Audio on the PM4125 analog codec (headphone / line out) behind the ADSP:
# ADSP, sound card, SoundWire codec, playback route, and the DAPM power
# state of the headphone path while a tone plays. Hearing the tone needs
# headphones or a speaker on the board's headphone/line-out pins.
#   ./audio.sh [seconds]
. "$(dirname "$0")/lib.sh"
SECS=${1:-4}
R=$(dirname "$(grep -l adsp /sys/class/remoteproc/*/name 2>/dev/null | head -1)")
section "ADSP"
if [ -d "$R" ]; then
	[ "$(cat $R/state)" = running ] || { echo start > $R/state; sleep 4; }
	[ "$(cat $R/state)" = running ] && pass "ADSP running" || fail "ADSP state $(cat $R/state)"
else
	fail "no adsp remoteproc"
fi

section "sound card"
# The kernel's snd-aloop Loopback card is always there; look for real hardware.
i=0; while [ $i -lt 30 ]; do i=$((i + 1)); CARD=$(aplay -l 2>/dev/null | grep '^card' | grep -v Loopback | head -1); [ -n "$CARD" ] && break; sleep 1; done  # up to 30 s: the card re-binds after an ADSP restart
[ -n "$CARD" ] || { skip "no sound card"; summary; exit 0; }
pass "$CARD"
N=$(echo "$CARD" | sed 's/^card \([0-9]*\).*/\1/')
n=$(ls /sys/bus/soundwire/devices 2>/dev/null | grep -c '^sdw:')
[ "$n" -ge 2 ] && pass "PM4125 RX and TX SoundWire devices ($n)" || fail "SoundWire devices: $n"

section "playback route"
sh "$(dirname "$0")/audio-route.sh" playback && pass "headphone route set" || fail "route"

section "tone on hw:$N,0 for ${SECS}s, headphone path power state"
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug 2>/dev/null
speaker-test -D "hw:$N,0" -c 2 -r 48000 -F S16_LE -t sine -f 440 -l 0 >/tmp/speaker.log 2>&1 & ST=$!
sleep 2
A=/sys/kernel/debug/asoc
on=0
for w in MM_DL1 RX_CODEC_DMA_RX_0 "RX_MACRO_AIF1 Playback" "RX INT0_1 INTERP" "RX INT1_1 INTERP" HPHL_RDAC HPHR_RDAC "HPHL PGA" "HPHR PGA" HPHL HPHR; do
	f=$(find $A -path "*/dapm/$w" 2>/dev/null | head -1)
	if [ -n "$f" ] && head -1 "$f" | grep -q ': On'; then on=$((on + 1)); else info "not powered: $w"; fi
done
[ "$on" -eq 11 ] && pass "headphone path powered end to end (11/11 widgets)" || fail "headphone path: $on/11 widgets powered"
sleep $((SECS - 2))
kill $ST 2>/dev/null; wait $ST 2>/dev/null
grep -qiE 'error|fail' /tmp/speaker.log && { fail "speaker-test"; grep -iE 'error|fail' /tmp/speaker.log | head -3; } || pass "speaker-test played (listen on the headphone/line out)"
sh "$(dirname "$0")/audio-route.sh" off >/dev/null 2>&1
summary
