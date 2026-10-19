#!/bin/sh
# WiFi: WCN3990 through ath10k_snoc. The WLAN firmware runs on the modem
# DSP, so this also checks the modem bring-up (rmtfs, tqftpserv, QRTR).
#   ./wifi.sh              scan and list the visible networks, connect to none
#   ./wifi.sh ssid psk [server]
#                          also associate, get a lease, ping and measure the
#                          link with speedtest-cli (the link stays up
#                          afterwards); server is a speedtest.net server id
#                          (speedtest-cli --list) for when the nearest one,
#                          chosen from the public address, is unreachable
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
			# power save makes the board deaf between beacons: 100-450 ms
			# RTT and ~0.2 MB/s for traffic towards it (ssh, scp)
			iw dev wlan0 set power_save off
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
			section "speedtest"
			# speedtest-cli (sivel, Apache-2.0) over https: the plain http
			# path geolocates a CGNAT address badly and then picks servers
			# thousands of km away that fail the latency probe (0 Mbit/s).
			# TLS needs a sane clock and the board has no RTC (1970 at boot):
			# take the time from an HTTP Date header, there is no ntpd.
			if [ "$(date +%s)" -lt 1000000000 ]; then
				d=$(wget -q -S --spider http://1.1.1.1 2>&1 | sed -n 's/^ *Date: //p' | sed 's/ GMT$//' | head -1)
				[ -n "$d" ] && date -u -D '%a, %d %b %Y %H:%M:%S' -s "$d" >/dev/null 2>&1 && info "clock set from an HTTP Date header: $(date -u)"
			fi
			# A ping of 1800000 ms means none of the chosen servers answered:
			# no verdict on the link then; the third argument picks a server.
			out=$(speedtest-cli --simple --secure ${3:+--server "$3"} 2>&1)
			res=$(echo "$out" | grep -E '^(Ping|Download|Upload):' | tr '\n' ' ' | sed 's/  */ /g')
			dl=$(echo "$out" | awk '/^Download:/ {print $2}')
			if [ -z "$dl" ]; then
				fail "speedtest-cli: $(echo "$out" | grep -v -i -E 'warning|utcnow' | tail -1)"
			elif echo "$out" | grep -q '^Ping: 1800000'; then
				skip "speedtest.net found no reachable server ($res); retry with a server id from speedtest-cli --list as the third argument"
			elif [ "${dl%%.*}" -eq 0 ]; then
				fail "speedtest: $res"
			else
				pass "$res"
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
