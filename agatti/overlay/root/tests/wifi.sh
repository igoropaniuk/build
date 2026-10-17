#!/bin/sh
# DRAFT: WiFi (WCN3990 via ath10k_snoc). The WLAN firmware runs on the
# modem DSP, which the open stack does not boot yet (modem PAS in OP-TEE,
# rmtfs and tqftpserv missing), so this is expected to SKIP for now.
#   ./wifi.sh [ssid] [psk]
. "$(dirname "$0")/lib.sh"
section "modem"
M=$(dirname "$(grep -l modem /sys/class/remoteproc/*/name 2>/dev/null | head -1)")
[ -d "$M" ] && info "$M: state $(cat $M/state)"
section "wlan0"
if ip link show wlan0 >/dev/null 2>&1; then
	pass "wlan0 present"
	ip link set wlan0 up
	n=$(iw dev wlan0 scan 2>/dev/null | grep -c '^BSS')
	[ "$n" -gt 0 ] && pass "scan: $n networks" || fail "scan found nothing"
	if [ -n "$1" ]; then
		wpa_passphrase "$1" "$2" > /tmp/wpa.conf
		wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf && sleep 8 && udhcpc -i wlan0 -n -q && pass "associated, $(ip -4 -br addr show wlan0)" || fail "association"
	fi
else
	skip "no wlan0 (modem/WLAN firmware not running on the open stack yet)"
fi
summary
