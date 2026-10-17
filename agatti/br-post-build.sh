#!/bin/sh
# Buildroot post-build script for the Arduino UNO Q rootfs (agatti.mk).
# $1 is the target directory; BUILD_DIR comes from Buildroot's environment.
set -e
TARGET_DIR=$1

# BlueZ builds btmgmt but its Makefile never installs it. The UNO Q needs
# it at boot: the WCN39xx comes up without a valid BD address, so the
# controller stays unconfigured (hci0 DOWN RAW) until one is set over mgmt.
BTMGMT=$(ls "$BUILD_DIR"/bluez5_utils-*/tools/btmgmt 2>/dev/null | head -1)
if [ -n "$BTMGMT" ]; then
	install -D -m 0755 "$BTMGMT" "$TARGET_DIR/usr/bin/btmgmt"
fi
