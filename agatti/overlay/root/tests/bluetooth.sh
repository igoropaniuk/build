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
# bluetoothctl 5.86 hangs in one-shot mode (bluetoothctl show, --timeout
# scan on) and prints nothing; commands fed on stdin work. Strip its colours.
ESC=$(printf '\033')
btctl() { bluetoothctl 2>&1 | sed "s/${ESC}\[[0-9;]*[A-Za-z]//g"; }
printf 'power on\nshow\nquit\n' | btctl >/tmp/btshow.log
info "$(grep -E '^Controller|Powered:' /tmp/btshow.log | tr '\n' ' ')"
grep -q 'Powered: yes' /tmp/btshow.log && pass "adapter powered" || fail "adapter not powered"

section "scan $S s"
{ printf 'scan on\n'; sleep "$S"; printf 'scan off\nquit\n'; } | btctl >/tmp/btscan.log
# devices already known to bluetoothd show up as [CHG], new ones as [NEW]
grep -q 'Discovery started' /tmp/btscan.log && pass "discovery started" || fail "discovery did not start"
n=$(grep -o 'Device [0-9A-F:]\{17\}' /tmp/btscan.log | sort -u | wc -l)
[ "$n" -gt 0 ] && pass "$n device(s) seen" || skip "no devices in range"
grep -o 'Device [0-9A-F:]\{17\}.*' /tmp/btscan.log | grep -E 'NEW|Name|RSSI' | head -8 | sed 's/^/  /'
summary
