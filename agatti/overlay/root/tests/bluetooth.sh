#!/bin/sh
# Bluetooth: WCN39xx on the GENI UART (ttyHS), BlueZ scan.
#   ./bluetooth.sh [scan-seconds]
. "$(dirname "$0")/lib.sh"
S=${1:-10}

section "controller"
dmesg | grep -q 'QCA setup on UART is completed' && pass "firmware download completed" || fail "QCA setup did not complete"
[ -d /sys/class/bluetooth/hci0 ] && pass "hci0" || { fail "no hci0"; summary; exit 1; }

section "BlueZ"
pidof bluetoothd >/dev/null || { /etc/init.d/S40bluetoothd start >/dev/null 2>&1; sleep 2; }
pidof bluetoothd >/dev/null && pass "bluetoothd running" || { fail "bluetoothd not running"; summary; exit 1; }
if hciconfig hci0 2>/dev/null | grep -q RAW; then
	info "hci0 unconfigured (no BD address), setting one"
	/etc/init.d/S41bluetooth-addr start
fi
info "$(hciconfig hci0 2>/dev/null | grep 'BD Address')"
bluetoothctl power on >/dev/null 2>&1
info "$(bluetoothctl show 2>/dev/null | grep -E 'Controller|Powered' | tr '\n' ' ')"
bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && pass "adapter powered" || fail "adapter not powered"

section "scan $S s"
bluetoothctl --timeout "$S" scan on >/tmp/btscan.log 2>&1
n=$(grep -c 'NEW.*Device' /tmp/btscan.log)
[ "$n" -gt 0 ] && pass "$n device(s) found" || skip "no devices in range (or scan failed)"
grep 'NEW.*Device' /tmp/btscan.log | head -8 | sed 's/^/  /'
summary
