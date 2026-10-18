#!/bin/sh
# WiFi: WCN3990 through ath10k_snoc. The WLAN firmware runs on the modem
# DSP, so this also checks the modem bring-up (rmtfs, tqftpserv, QRTR).
#   ./wifi.sh              scan and list the visible networks, connect to none
#   ./wifi.sh ssid psk     also associate, get a lease, ping, and time a 100 MB
#                          download (the link stays up afterwards)
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
	scan=$(iw dev wlan0 scan 2>/dev/null)
	n=$(echo "$scan" | grep -c '^BSS')
	[ "$n" -gt 0 ] && pass "scan: $n networks" || fail "scan found nothing"
	echo "$scan" | awk '/freq:/ {f=$2} /signal:/ {s=$2} /SSID:/ {sub(/^[ \t]*SSID: ?/, ""); printf "  %5.0f MHz %4.0f dBm  %s\n", f, s, ($0 == "" ? "<hidden>" : $0)}' | sort -k3 -n -r
	if [ -n "$1" ]; then
		section "associate: $1"
		# a quoted psk is the passphrase; wpa_supplicant derives the key
		# itself, so wpa_passphrase is not needed on the target
		printf 'ctrl_interface=/var/run/wpa_supplicant\nnetwork={\n\tssid="%s"\n\tpsk="%s"\n}\n' "$1" "$2" > /tmp/wpa.conf
		killall wpa_supplicant 2>/dev/null; sleep 1
		wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf >/dev/null 2>&1
		i=0
		while ! wpa_cli -i wlan0 status 2>/dev/null | grep -q 'wpa_state=COMPLETED' && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done
		if wpa_cli -i wlan0 status 2>/dev/null | grep -q 'wpa_state=COMPLETED'; then
			pass "associated after ${i}s"
			info "$(wpa_cli -i wlan0 status 2>/dev/null | grep -E '^(freq|key_mgmt|pairwise_cipher)=' | tr '\n' ' ')"
			info "$(iw dev wlan0 link | grep -E 'signal|bitrate' | sed 's/^[ \t]*//' | tr '\n' ' ')"
		else
			fail "association ($(wpa_cli -i wlan0 status 2>/dev/null | grep wpa_state))"
		fi
		if udhcpc -i wlan0 -n -q -t 10 >/dev/null 2>&1; then
			pass "DHCP: $(ip -4 -br addr show wlan0 | awk '{print $3}')"
			gw=$(ip route | awk '/^default/ {print $3; exit}')
			ping -c 3 -W 3 $gw >/dev/null 2>&1 && pass "ping gateway $gw" || fail "ping gateway $gw"
			ping -c 3 -W 3 1.1.1.1 >/dev/null 2>&1 && pass "ping 1.1.1.1" || fail "ping 1.1.1.1"
			section "download"
			url=http://speedtest.newark.linode.com/100MB-newark.bin
			t0=$(awk '{print int($1 * 100)}' /proc/uptime)
			if wget -q -T 30 -O /dev/null "$url" 2>/dev/null; then
				t1=$(awk '{print int($1 * 100)}' /proc/uptime)
				dt=$((t1 - t0)); [ $dt -gt 0 ] || dt=1
				pass "100 MB downloaded in $((dt / 100)).$((dt % 100 / 10)) s ($((100 * 100 / dt)).$((100 * 1000 / dt % 10)) MB/s)"
			else
				fail "download of $url"
			fi
		else
			fail "DHCP"
		fi
	fi
else
	fail "no wlan0 after ${i}s"
	dmesg | grep -i -E 'ath10k|wlan|wcn' | tail -5 | cut -c1-140 | sed 's/^/  /'
fi
faults
summary
