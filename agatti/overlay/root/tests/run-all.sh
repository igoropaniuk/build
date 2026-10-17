#!/bin/sh
# Run every test that needs no extra hardware; the display/GPU/USB host
# parts skip themselves when the board is not on a dock.
#   ./run-all.sh 2>&1 | tee /tmp/run-all.log
cd "$(dirname "$0")"
total=0; failed=""
for t in system.sh buses.sh tee.sh audio.sh video.sh bluetooth.sh adsp.sh usb.sh display.sh gpu.sh wifi.sh; do
	echo; echo "######## $t"
	sh ./$t || failed="$failed $t"
	total=$((total + 1))
done
echo; echo "######## $total test scripts, failed:${failed:- none}"
[ -z "$failed" ]
