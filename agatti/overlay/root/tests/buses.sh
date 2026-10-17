#!/bin/sh
# Low-speed buses: GENI I2C, SPI (spidev to the MCU), UARTs.
. "$(dirname "$0")/lib.sh"

section "QUP firmware"
n=$(dmesg | grep -c 'exceeds RAM size\|Failed to load SE firmware')
[ "$n" -eq 0 ] && pass "no GENI firmware load errors" || fail "$n GENI firmware errors"

section "I2C"
for b in /dev/i2c-*; do
	[ -e "$b" ] || continue
	info "$b: $(i2cdetect -y "${b#/dev/i2c-}" 2>/dev/null | grep -oE ' [0-9a-f]{2}|UU' | tr '\n' ' ')"
done
ls /dev/i2c-* >/dev/null 2>&1 && pass "$(ls /dev/i2c-* | wc -l) I2C buses" || fail "no I2C buses"
[ -d /sys/bus/i2c/drivers/anx7625/1-0058 ] && pass "anx7625 bound at 1-0058" || fail "anx7625 not bound"

section "SPI"
[ -e /dev/spidev0.0 ] && pass "spidev0.0 (MCU link)" || fail "no spidev0.0"

section "UARTs"
for t in /dev/ttyMSM* /dev/ttyHS*; do [ -e "$t" ] && info "$t"; done
summary
