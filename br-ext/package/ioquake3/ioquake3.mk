################################################################################
#
# ioquake3
#
################################################################################

IOQUAKE3_VERSION = 87a99d18206e878a20289f05ac3c16005dcae5c3
IOQUAKE3_SITE = $(call github,ioquake,ioq3,$(IOQUAKE3_VERSION))
IOQUAKE3_LICENSE = GPL-2.0+
IOQUAKE3_LICENSE_FILES = COPYING.txt
IOQUAKE3_DEPENDENCIES = sdl2
IOQUAKE3_SUPPORTS_IN_SOURCE_BUILD = NO

# Native game modules instead of QVMs: building the QVMs needs q3lcc for
# the host, and the engine has no QVM JIT for aarch64. Codecs and zlib/jpeg
# come from ioq3's bundled sources, SDL from the target; no OpenAL (SDL
# audio over ALSA), no curl downloads, no Mumble.
IOQUAKE3_CONF_OPTS = \
	-DCMAKE_INSTALL_PREFIX=/usr/lib/ioquake3 \
	-DBUILD_SERVER=ON \
	-DBUILD_CLIENT=ON \
	-DBUILD_RENDERER_GL1=ON \
	-DBUILD_RENDERER_GL2=ON \
	-DBUILD_GAME_LIBRARIES=ON \
	-DBUILD_GAME_QVMS=OFF \
	-DUSE_INTERNAL_LIBS=ON \
	-DUSE_INTERNAL_SDL=OFF \
	-DUSE_OPENAL=OFF \
	-DUSE_HTTP=OFF \
	-DUSE_MUMBLE=OFF

define IOQUAKE3_INSTALL_WRAPPER
	mkdir -p $(TARGET_DIR)/usr/bin
	ln -sf ../lib/ioquake3/ioquake3 $(TARGET_DIR)/usr/bin/ioquake3
	ln -sf ../lib/ioquake3/ioq3ded $(TARGET_DIR)/usr/bin/ioq3ded
endef
IOQUAKE3_POST_INSTALL_TARGET_HOOKS += IOQUAKE3_INSTALL_WRAPPER

$(eval $(cmake-package))
