#!/bin/sh
# USB (dwc3): role from the type-C port, devices behind a dock, keyboard.
#   ./usb.sh            enumerate only
#   ./usb.sh keys       also show 10 s of key presses from the keyboard
. "$(dirname "$0")/lib.sh"

section "type-C and role"
info "data role $(cat /sys/class/typec/port0/data_role 2>/dev/null), power role $(cat /sys/class/typec/port0/power_role 2>/dev/null)"
role=$(cat /sys/class/usb_role/*/role 2>/dev/null)
info "dwc3 role: $role"
if [ "$role" = host ]; then
	pass "host role"
	section "devices"
	lsusb -t 2>/dev/null
	n=$(lsusb | grep -vc 'root hub')
	[ "$n" -gt 0 ] && pass "$n device(s) behind the root hubs" || fail "nothing enumerated"
	ip -br link 2>/dev/null | grep -E '^eth' && info "(dock Ethernet above)"
	K=""
	for e in /sys/class/input/event*; do grep -qi 'keyboard' "$e/device/name" && { K=/dev/input/$(basename "$e"); break; }; done
	[ -n "$K" ] && pass "keyboard on $K ($(cat /sys/class/input/$(basename "$K")/device/name))" || skip "no USB keyboard"
	if [ "$1" = keys ] && [ -n "$K" ]; then
		echo "press keys for 10 s..."
		run_for 10 evtest "$K" 2>/dev/null | grep 'EV_KEY.*value 1'
	fi
else
	pass "device role (board on the host cable)"
	cat /sys/class/udc/*/state 2>/dev/null | sed 's/^/  udc state: /'
	skip "host tests need the dock"
fi
summary
