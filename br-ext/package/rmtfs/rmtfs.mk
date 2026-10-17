################################################################################
#
# rmtfs
#
################################################################################

RMTFS_VERSION = 1.3
RMTFS_SITE = $(call github,linux-msm,rmtfs,v$(RMTFS_VERSION))
RMTFS_LICENSE = BSD-3-Clause
RMTFS_LICENSE_FILES = LICENSE
RMTFS_DEPENDENCIES = qrtr udev

# qmi_rmtfs.c/.h are committed; keep make from regenerating them with qmic.
define RMTFS_TOUCH_GENERATED
	touch $(@D)/qmi_rmtfs.c $(@D)/qmi_rmtfs.h
endef
RMTFS_PRE_BUILD_HOOKS += RMTFS_TOUCH_GENERATED

# The Makefile appends its libraries to LDFLAGS; a command-line LDFLAGS
# would drop them.
define RMTFS_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) \
		LDFLAGS="$(TARGET_LDFLAGS) -lqrtr -ludev -lpthread" \
		-C $(@D) rmtfs
endef

define RMTFS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/rmtfs $(TARGET_DIR)/usr/bin/rmtfs
endef

$(eval $(generic-package))
