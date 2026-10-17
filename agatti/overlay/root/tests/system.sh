#!/bin/sh
# Basics: CPUs, memory, eMMC, idle/cpufreq state.
. "$(dirname "$0")/lib.sh"
n=$(grep -c ^processor /proc/cpuinfo)
[ "$n" -eq 4 ] && pass "4 CPUs online" || fail "$n CPUs"
info "$(grep MemTotal /proc/meminfo)"
grep -q mmcblk0 /proc/partitions && pass "eMMC: $(cat /sys/block/mmcblk0/device/name) $(( $(cat /sys/block/mmcblk0/size) / 2097152 )) GiB" || fail "no eMMC"
ls /sys/devices/system/cpu/cpu0/cpuidle 2>/dev/null | grep -q state && pass "cpuidle: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name | tr '\n' ' ')" || skip "no cpuidle states"
[ -d /sys/devices/system/cpu/cpufreq/policy0 ] && pass "cpufreq" || skip "no cpufreq (LMH SCM missing in TF-A)"
summary
