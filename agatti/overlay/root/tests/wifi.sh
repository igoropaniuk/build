#!/bin/sh
# WiFi: WCN3990 through ath10k_snoc. The WLAN firmware runs on the modem
# DSP, so this also checks the modem bring-up (rmtfs, tqftpserv, QRTR).
#   ./wifi.sh [ssid psk]    with credentials, also associate and get a lease
. "$(dirname "$0")/lib.sh"

section "modem"
M=$(dirname "$(grep -l modem /sys/class/remoteproc/*/name 2>/dev/null | head -1)")
if [ ! -d "$M" ]; then
	fail "no modem remoteproc"
	summary; exit 1
fi
[ "$(cat $M/state)" = offline ] && { info "starting the modem"; echo start > $M/state 2>/dev/null; }
i=0
while [ "$(cat $M/state)" != running ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
sleep 3	# a modem that crashes in its init does so within the first second
if [ "$(cat $M/state)" = running ]; then
	pass "modem running ($M)"
else
	fail "modem state: $(cat $M/state)"
	info "$(dmesg | grep -i 'fatal error' | tail -1 | cut -c1-140)"
fi
[ -e /dev/qcom_rmtfs_mem1 ] && pass "rmtfs memory /dev/qcom_rmtfs_mem1" || fail "no rmtfs memory device"
pidof rmtfs >/dev/null && pass "rmtfs running" || fail "rmtfs not running"
pidof tqftpserv >/dev/null && pass "tqftpserv running" || fail "tqftpserv not running"
n=$(qrtr-lookup 2>/dev/null | grep -c -v '^ *Service')
[ "$n" -gt 0 ] && pass "QRTR: $n services" || fail "QRTR: no services (qrtr-lookup)"
qrtr-lookup 2>/dev/null | grep -i -E "wlfw|rmtfs|tftp" | sed 's/^/  /'

section "wlan0"
i=0
while ! ip link show wlan0 >/dev/null 2>&1 && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
if ip link show wlan0 >/dev/null 2>&1; then
	pass "wlan0 present after ${i}s"
	info "$(dmesg | grep -i 'ath10k' | grep -i -E 'firmware|board|version' | tail -3 | cut -c1-140)"
	ip link set wlan0 up && pass "wlan0 up" || fail "wlan0 up"
	n=$(iw dev wlan0 scan 2>/dev/null | grep -c '^BSS')
	[ "$n" -gt 0 ] && pass "scan: $n networks" || fail "scan found nothing"
	iw dev wlan0 scan 2>/dev/null | grep 'SSID:' | sort -u | head -8 | sed 's/^[ \t]*/  /'
	if [ -n "$1" ]; then
		section "associate: $1"
		wpa_passphrase "$1" "$2" > /tmp/wpa.conf
		killall wpa_supplicant 2>/dev/null; sleep 1
		wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf >/dev/null 2>&1
		i=0
		while ! wpa_cli -i wlan0 status 2>/dev/null | grep -q 'wpa_state=COMPLETED' && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done
		wpa_cli -i wlan0 status 2>/dev/null | grep -q 'wpa_state=COMPLETED' && pass "associated after ${i}s" || fail "association ($(wpa_cli -i wlan0 status 2>/dev/null | grep wpa_state))"
		udhcpc -i wlan0 -n -q -t 10 >/dev/null 2>&1 && pass "DHCP: $(ip -4 -br addr show wlan0 | awk '{print $3}')" || fail "DHCP"
		ping -c 3 -W 3 8.8.8.8 >/dev/null 2>&1 && pass "ping 8.8.8.8" || info "no route to 8.8.8.8"
	fi
else
	fail "no wlan0 after ${i}s"
	dmesg | grep -i -E 'ath10k|wlan|wcn' | tail -5 | cut -c1-140 | sed 's/^/  /'
fi
faults
summary
