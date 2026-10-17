#!/bin/sh
# Hardware video (venus): device probe, then an encode/decode round trip
# through gstreamer. No display needed.
#   ./video.sh [frames] [width] [height] [codec: h264|h265]
. "$(dirname "$0")/lib.sh"
N=${1:-300}; W=${2:-1280}; H=${3:-720}; C=${4:-h264}
case $C in h264) P=h264parse ;; h265) P=h265parse ;; *) echo "codec h264|h265"; exit 2 ;; esac
OUT=/tmp/venus-test.$C

section "venus devices"
v4l2-ctl --list-devices 2>/dev/null | grep -q 'Venus video encoder' && pass "encoder present" || fail "no venus encoder"
v4l2-ctl --list-devices 2>/dev/null | grep -q 'Venus video decoder' && pass "decoder present" || fail "no venus decoder"
for d in /dev/video*; do info "$d: $(v4l2-ctl -d "$d" --info 2>/dev/null | sed -n 's/.*Card type *: //p')"; done

section "gstreamer elements"
for e in v4l2${C}enc v4l2${C}dec; do
	gst-inspect-1.0 "$e" >/dev/null 2>&1 && pass "$e registered" || fail "$e missing (needs the V4L2 m2m probe)"
done

section "encode $N frames ${W}x${H} to $C"
t0=$(date +%s)
if gst-launch-1.0 -q -e videotestsrc num-buffers="$N" pattern=smpte ! \
	video/x-raw,format=NV12,width="$W",height="$H",framerate=30/1 ! \
	v4l2${C}enc ! $P ! filesink location="$OUT" >/tmp/venc.log 2>&1 && [ -s "$OUT" ]; then
	t=$(( $(date +%s) - t0 )); [ "$t" -gt 0 ] || t=1
	pass "encoded $(wc -c < "$OUT") bytes in ~${t}s (~$((N / t)) fps)"
else
	fail "encode failed"; tail -5 /tmp/venc.log
fi

section "decode $OUT"
if [ -s "$OUT" ]; then
	gst-launch-1.0 -v filesrc location="$OUT" ! $P ! v4l2${C}dec ! \
		fpsdisplaysink video-sink=fakesink text-overlay=false sync=false \
		>/tmp/vdec.log 2>&1
	last=$(grep 'last-message' /tmp/vdec.log | tail -1 | sed 's/.*last-message = //')
	if grep -q 'rendered' /tmp/vdec.log; then pass "decoded: $last"; else fail "decode failed"; tail -5 /tmp/vdec.log; fi
else
	skip "nothing to decode"
fi

section "faults"
faults
summary
