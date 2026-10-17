# Shared helpers for the UNO Q peripheral tests (BusyBox ash).
PASS=0; FAIL=0; SKIP=0
pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $*"; SKIP=$((SKIP + 1)); }
info() { echo "  $*"; }
section() { echo; echo "== $*"; }
# Run a command for at most $1 seconds (BusyBox here has no timeout).
run_for() {
	secs=$1; shift
	"$@" </dev/null & pid=$!
	( sleep "$secs"; kill "$pid" 2>/dev/null ) & killer=$!
	wait "$pid"; rc=$?
	kill "$killer" 2>/dev/null
	return $rc
}
faults() {
	n=$(dmesg | grep -ciE 'Stream ID|xpu.*violation|gpu fault|hangcheck|venus.*(err|fail)')
	[ "$n" -eq 0 ] && pass "no SMMU/XPU/GPU/venus faults in dmesg" ||
		{ fail "$n fault lines in dmesg"; dmesg | grep -iE 'Stream ID|xpu.*violation|gpu fault|hangcheck|venus.*(err|fail)' | sort | uniq -c | head -5; }
	n=$(dmesg | grep -cE 'Internal error|Unable to handle kernel|BUG:|WARNING:.*at ')
	[ "$n" -eq 0 ] && pass "no kernel oops or warning in dmesg" ||
		{ fail "$n kernel oops/warning lines in dmesg"; dmesg | grep -E 'Internal error|Unable to handle kernel|BUG:|WARNING:.*at ' | head -5; }
}
summary() {
	echo; echo "== $(basename "$0"): $PASS passed, $FAIL failed, $SKIP skipped"
	[ "$FAIL" -eq 0 ]
}
