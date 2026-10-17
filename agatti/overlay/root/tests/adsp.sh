#!/bin/sh
# ADSP over the OP-TEE PAS backend: start/stop cycles, rpmsg channels.
#   ./adsp.sh [cycles]
. "$(dirname "$0")/lib.sh"
N=${1:-3}
R=$(dirname "$(grep -l adsp /sys/class/remoteproc/*/name 2>/dev/null | head -1)")
[ -d "$R" ] || { fail "no adsp remoteproc"; summary; exit 1; }
info "$R: $(cat $R/name), firmware $(cat $R/firmware), state $(cat $R/state)"
i=1
while [ $i -le "$N" ]; do
	section "cycle $i"
	[ "$(cat $R/state)" = running ] && echo stop > $R/state && sleep 1
	echo start > $R/state 2>/dev/null; sleep 3
	[ "$(cat $R/state)" = running ] && pass "running" || fail "state $(cat $R/state)"
	ls /sys/bus/rpmsg/devices 2>/dev/null | grep -i adsp | head -3 | sed 's/^/  /'
	i=$((i + 1))
done
section "faults"
faults
summary
