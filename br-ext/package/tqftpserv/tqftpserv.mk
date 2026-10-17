################################################################################
#
# tqftpserv
#
################################################################################

TQFTPSERV_VERSION = 1.2
TQFTPSERV_SITE = $(call github,linux-msm,tqftpserv,v$(TQFTPSERV_VERSION))
TQFTPSERV_LICENSE = BSD-3-Clause
TQFTPSERV_LICENSE_FILES = LICENSE
TQFTPSERV_DEPENDENCIES = qrtr zstd

$(eval $(meson-package))
