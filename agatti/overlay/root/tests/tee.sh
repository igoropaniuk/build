#!/bin/sh
# OP-TEE: driver, supplicant, PAS pseudo-TA, xtest (quick or full).
#   ./tee.sh            quick (regression suite 1xxx)
#   ./tee.sh full       all xtest suites (takes a while)
. "$(dirname "$0")/lib.sh"
section "driver"
dmesg | grep -q 'optee: initialized driver' && pass "$(dmesg | grep 'optee: revision' | sed 's/.*optee: //')" || fail "optee driver"
ls /sys/bus/tee/devices 2>/dev/null | grep -q cff7d191 && pass "PAS pseudo-TA on the TEE bus" || fail "no PAS TA device"
pidof tee-supplicant >/dev/null || { tee-supplicant -d; sleep 1; }
pidof tee-supplicant >/dev/null && pass "tee-supplicant" || fail "tee-supplicant"
section "xtest"
if [ "$1" = full ]; then xtest >/tmp/xtest.log 2>&1; else xtest -t regression _1 >/tmp/xtest.log 2>&1; fi
tail -4 /tmp/xtest.log | sed 's/^/  /'
grep -qE '^[0-9]+ subtests? of which 0 failed' /tmp/xtest.log && pass "xtest" || fail "xtest (see /tmp/xtest.log)"
summary
