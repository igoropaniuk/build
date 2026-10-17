#!/bin/sh
# ADSP over the OP-TEE PAS backend: start/stop cycles, rpmsg channels.
#   ./adsp.sh [cycles]
. "$(dirname "$0")/lib.sh"
N=${1:-3}
R=$(dirname "$(grep -l adsp /sys/class/remoteproc/*/name 2>/dev/null | head -1)")
[ -d "$R" ] || { fail "no adsp remoteproc"; summary; exit 1; }
info "$R: $(cat $R/name), firmware $(cat $R/firmware), state $(cat $R/state)"

# The audio stack sits on top of the ADSP: the sound card, the PM4125
# codec on SoundWire, the SoundWire controllers and the LPASS codec macros
# all hold clocks that the q6afe clock provider hands out. Stopping the ADSP
# unregisters that provider under them, so after a restart their clock
# requests fail and SoundWire's resume touches an unclocked register
# (external abort). Take the stack down from the top before the restart
# and bring it back from the bottom afterwards.
AUDIO_DEVS=""
for d in /sys/bus/platform/devices/*; do
	c=$(cat "$d/of_node/compatible" 2>/dev/null | tr '\0' ' ')
	case "$c" in
	*sndcard*|*soundwire*|*lpass-rx-macro*|*lpass-tx-macro*|*lpass-va-macro*|*lpass-wsa-macro*)
		[ -e "$d/driver" ] && AUDIO_DEVS="$AUDIO_DEVS $(basename $d):$(readlink -f $d/driver)" ;;
	esac
done

audio_unbind() {
	# sound card first, then the SoundWire masters (their codec slaves go
	# with them), then the macros
	for pat in sndcard soundwire macro; do
		for e in $AUDIO_DEVS; do
			dev=${e%%:*}; drv=${e#*:}
			case "$(cat /sys/bus/platform/devices/$dev/of_node/compatible 2>/dev/null)" in
			*$pat*) [ -e /sys/bus/platform/devices/$dev/driver ] && echo "$dev" > "$drv/unbind" ;;
			esac
		done
	done
}

audio_bind() {
	for pat in macro soundwire sndcard; do
		for e in $AUDIO_DEVS; do
			dev=${e%%:*}; drv=${e#*:}
			case "$(cat /sys/bus/platform/devices/$dev/of_node/compatible 2>/dev/null)" in
			*$pat*) [ -e /sys/bus/platform/devices/$dev/driver ] || echo "$dev" > "$drv/bind" 2>/dev/null ;;
			esac
		done
		sleep 1
	done
	t=0
	while [ $t -lt 10 ]; do
		grep -qs . /proc/asound/cards && ! grep -qs "no soundcards" /proc/asound/cards && return 0
		sleep 1; t=$((t + 1))
	done
	return 1
}

# The LPASS codec macro drivers refuse to unbind (suppress_bind_attrs), and
# with them bound an ADSP restart ends in an external abort when SoundWire
# re-probes against the clock provider that went away with the old ADSP.
# That needs restart support in those kernel drivers; until then the
# restart cycles are skipped when the macros are bound.
if [ -n "$AUDIO_DEVS" ]; then
	stuck=""
	for e in $AUDIO_DEVS; do
		dev=${e%%:*}; drv=${e#*:}
		[ -e "$drv/unbind" ] || stuck="$stuck $dev"
	done
	if [ -n "$stuck" ]; then
		skip "ADSP restart cycles: the LPASS audio drivers of$stuck cannot be unbound and would oops on the restart"
		N=0
	else
		info "audio stack ($(echo $AUDIO_DEVS | wc -w) devices) is unbound around each restart"
	fi
fi
i=1
while [ $i -le "$N" ]; do
	section "cycle $i"
	[ -n "$AUDIO_DEVS" ] && audio_unbind && sleep 1
	[ "$(cat $R/state)" = running ] && echo stop > $R/state && sleep 1
	echo start > $R/state 2>/dev/null; sleep 3
	[ "$(cat $R/state)" = running ] && pass "running" || fail "state $(cat $R/state)"
	ls /sys/bus/rpmsg/devices 2>/dev/null | grep -i adsp | head -3 | sed 's/^/  /'
	if [ -n "$AUDIO_DEVS" ]; then
		audio_bind && pass "audio stack back: $(head -1 /proc/asound/cards | sed 's/^ *//')" \
			|| fail "audio stack did not come back"
	fi
	i=$((i + 1))
done
section "faults"
faults
summary
