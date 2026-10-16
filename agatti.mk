################################################################################
# agatti.mk — Qualcomm QCM2290 / QRB2210 (Agatti, Arduino UNO Q)
#
# Open boot firmware (TF-A + OP-TEE + U-Boot) built natively on the host,
# following the kodiak.mk / lemans.mk pattern.
#
# Key differences from kodiak.mk:
#   - SoC:        QCM2290 / QRB2210 (4x Kryo 2xx Silver, GIC-500) vs QCS6490
#   - TF-A PLAT:  uno_q                                            vs kodiak
#   - qtiseclib:  none, the EL3 drivers are native
#   - Signing:    QTI CASS remote for BL2 (tz), qtestsign for the FIP (uefi)
#   - Storage:    eMMC, single LUN
#
# Targets
#   bootimage      optee-os -> u-boot -> tfa -> bl2-sign: agatti/output/tz.mbn
#                  (CASS-signed BL2) and uefi.elf (FIP: BL31 + OP-TEE + U-Boot)
#   linux          Kernel Image + DTB (KERNEL=mainline|arduino, see below)
#   buildroot      Rootfs with tee-supplicant, xtest, the TAs and the ADSP image
#   efi            agatti/output/efi.bin: FAT32 with extlinux.conf + Image + DTB
#   all            Everything above that produces files
################################################################################

################################################################################
# Platform
################################################################################
PLATFORM          = agatti
OPTEE_OS_PLATFORM = qcom

override COMPILE_NS_USER   := 64
override COMPILE_NS_KERNEL := 64
override COMPILE_S_USER    := 64
override COMPILE_S_KERNEL  := 64

################################################################################
# OP-TEE OS settings
################################################################################
CFG_TEE_CORE_LOG_LEVEL := 2
OPTEE_OS_COMMON_EXTRA_FLAGS += PLATFORM_FLAVOR=agatti
# OP-TEE writes to out/arm-plat-qcom (no O= override), not the out/arm that
# common.mk assumes; the Buildroot TA packages need the real dev kit path.
OPTEE_OS_OUT_DIR         = $(OPTEE_OS_PATH)/out/arm-plat-qcom
OPTEE_OS_TA_DEV_KIT_DIR ?= $(OPTEE_OS_OUT_DIR)/export-ta_arm64
# common.mk passes CFG_IN_TREE_EARLY_TAS on the make command line, which
# overrides the "+= qcom_pas/..." in bruin/agatti/target.mk, so list the PAS
# early TA here explicitly or the kernel's qcom_pas_tee never finds it.
CFG_IN_TREE_EARLY_TAS ?= trusted_keys/f04a0fe7-1f5d-4b9b-abf7-619b85b4ce8c \
	qcom_pas/cff7d191-7ca0-4784-af13-48223b9a4fbe

################################################################################
# Paths
################################################################################
TF_A_PATH      ?= $(ROOT)/trusted-firmware-a
U-BOOT_PATH    ?= $(ROOT)/u-boot
OUT_DIR         = $(CURDIR)/agatti/output
DL_DIR         ?= $(ROOT)/downloads
OVERLAY_DIR     = $(CURDIR)/agatti/overlay

# Kernel flavour. One tree ($(ROOT)/linux), two branches, separate out-of-tree
# build directories so the configs never mix:
#   KERNEL=mainline (default): branch agatti-unoq-optee (v7.3-rc6 + the agatti
#                   OP-TEE DT commit), DTB qrb2210-arduino-imola
#   KERNEL=arduino:  branch igor-v7.0.0-unoq (Arduino qcom-v7.0.0-unoq + DT
#                   commit), DTB qrb2210-arduino-imola-base
# Check out the matching branch yourself; the flavour only selects the config
# recipe, the DTB name and $(LINUX_OUT).
KERNEL         ?= mainline
LINUX_PATH     ?= $(ROOT)/linux
LINUX_OUT       = $(LINUX_PATH)/out-$(KERNEL)
ifeq ($(KERNEL),mainline)
LINUX_DTB_NAME ?= qrb2210-arduino-imola
else
LINUX_DTB_NAME ?= qrb2210-arduino-imola-base
endif

################################################################################
# Buildroot
################################################################################
BR2_TARGET_GENERIC_GETTY_PORT := ttyMSM0
BR2_LINUX_KERNEL                = n
BR2_TARGET_ARM_TRUSTED_FIRMWARE = n
BR2_TARGET_OPTEE_OS             = n
BR2_TARGET_UBOOT                = n
BR2_PACKAGE_OPTEE_CLIENT        = n
BR2_PACKAGE_OPTEE_TEST          = n
BR2_PACKAGE_OPTEE_EXAMPLES      = n
BR2_PACKAGE_OPTEE_BENCHMARK     = n
# The rootfs partition is written as an ext4 image (qdl write rootfs ...).
BR2_TARGET_ROOTFS_EXT2          = y
BR2_TARGET_ROOTFS_EXT2_4        = y
BR2_TARGET_ROOTFS_EXT2_SIZE     = 512M
BR2_TARGET_ROOTFS_EXT2_LABEL    = rootfs
# agatti/overlay carries /lib/firmware (ADSP image, fetched); modules_dir is
# where a modules_install would land (empty, the kernels have MODULES=n).
BR2_ROOTFS_OVERLAY = $(OVERLAY_DIR) $(LINUX_PATH)/modules_dir

include common.mk
include toolchain.mk

################################################################################
# Top-level targets
################################################################################
.PHONY: all clean help

all: bootimage linux buildroot efi

clean: bootimage-clean linux-clean buildroot-clean efi-clean

help:
	@echo "Qualcomm QCM2290/QRB2210 (Agatti / Arduino UNO Q) build system"
	@echo ""
	@echo "  make all           Build everything"
	@echo "  make bootimage     optee-os -> u-boot -> tfa -> bl2-sign (agatti/output/tz.mbn + uefi.elf)"
	@echo "  make linux         Kernel Image + DTB (KERNEL=mainline|arduino)"
	@echo "  make buildroot     Rootfs (out-br/images/rootfs.ext4)"
	@echo "  make efi           agatti/output/efi.bin (extlinux.conf + Image + DTB)"
	@echo ""
	@echo "Per-component: optee-os u-boot tfa bl2-sign linux-defconfig linux-config and *-clean"

################################################################################
# OP-TEE OS
################################################################################
.PHONY: optee-os optee-os-clean
optee-os: optee-os-common
optee-os-clean: optee-os-clean-common

################################################################################
# U-Boot
################################################################################
U_BOOT_EXPORTS      = CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"
U_BOOT_DEVICE_TREE ?= qcom/qrb2210-arduino-imola
U_BOOT_OUTPUT       = $(U-BOOT_PATH)/.output

.PHONY: u-boot u-boot-defconfig u-boot-clean

u-boot-defconfig:
	mkdir -p $(U_BOOT_OUTPUT)
	cd $(U-BOOT_PATH) && \
		./scripts/kconfig/merge_config.sh \
			configs/qcom_defconfig \
			board/qualcomm/tfa-optee.config
	mv $(U-BOOT_PATH)/.config $(U_BOOT_OUTPUT)/

u-boot:
	@if [ ! -f $(U_BOOT_OUTPUT)/.config ]; then \
		$(MAKE) -f agatti.mk u-boot-defconfig; \
	fi
	$(U_BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) O=$(U_BOOT_OUTPUT) \
		-j$(shell nproc) DEVICE_TREE=$(U_BOOT_DEVICE_TREE)

u-boot-clean:
	$(U_BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) O=$(U_BOOT_OUTPUT) clean

################################################################################
# TF-A
################################################################################
TF_A_EXPORTS       = CROSS_COMPILE="$(AARCH64_CROSS_COMPILE)"
TF_A_BUILD_STRING ?= qcom-agatti
TF_A_PLAT         ?= uno_q
TF_A_FLAGS        ?= PLAT=$(TF_A_PLAT) SPD=opteed E=0 BUILD_STRING=$(TF_A_BUILD_STRING)
FIP_ELF_LOAD_ADDR ?= 0x5F800000

BL32_BIN = $(OPTEE_OS_OUT_DIR)/core/tee-raw.bin
BL33_BIN = $(U_BOOT_OUTPUT)/u-boot.bin

.PHONY: tfa tfa-clean

tfa:
	mkdir -p $(OUT_DIR)
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) -j$(shell nproc) $(TF_A_FLAGS) \
		BL32=$(BL32_BIN) \
		BL33=$(BL33_BIN) \
		fip all
	cd $(TF_A_PATH) && CROSS_COMPILE="$(AARCH64_CROSS_COMPILE)" \
		./tools/qti/generate_fip_elf.sh build/$(TF_A_PLAT)/release/fip.bin $(FIP_ELF_LOAD_ADDR)
	mv $(TF_A_PATH)/fip.elf $(OUT_DIR)/uefi.elf
	cp $(TF_A_PATH)/build/$(TF_A_PLAT)/release/bl2/bl2.elf $(OUT_DIR)/tz.elf

tfa-clean:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) clean

################################################################################
# BL2 signing: QTI CASS remote, with the Agatti security profile fetched from
# https://github.com/qualcomm/security-profiles (latest main; TZ is signed
# with its default ELF-V6 format, hash segment at the end).
################################################################################
SECTOOLS_PATH        ?= $(ROOT)/sectools/latest/Linux_$(UNAME_M)
SECURITY_PROFILE_URL ?= https://raw.githubusercontent.com/qualcomm/security-profiles/refs/heads/main/agatti_security_profile.xml
SECURITY_PROFILE      = $(DL_DIR)/agatti_security_profile.xml
CASS_CAPABILITY      ?= qtee_test_v4_qtee_release
CASS_SERVER_URL      ?= https://crm-sign.qualcomm.com
CASS_SERVER_PORT     ?= 50110

$(SECURITY_PROFILE):
	mkdir -p $(DL_DIR)
	curl --retry 5 -sSfL -o $@.tmp $(SECURITY_PROFILE_URL)
	mv $@.tmp $@

.PHONY: bl2-sign
bl2-sign: $(SECURITY_PROFILE)
	$(SECTOOLS_PATH)/sectools secure-image $(OUT_DIR)/tz.elf \
		--outfile $(OUT_DIR)/tz.mbn \
		--image-id TZ \
		--security-profile $(SECURITY_PROFILE) \
		--qti --sign --signing-mode QTI-REMOTE \
		--cass-capability $(CASS_CAPABILITY) \
		--qti-remote-signing-server-url $(CASS_SERVER_URL) \
		--qti-remote-signing-server-port $(CASS_SERVER_PORT)

################################################################################
# Boot image: tz.mbn + uefi.elf (always flash both, BL2 with SPD=opteed
# refuses a FIP without BL32)
################################################################################
.PHONY: bootimage bootimage-clean

bootimage:
	rm -f $(OUT_DIR)/tz.elf $(OUT_DIR)/tz.mbn $(OUT_DIR)/uefi.elf
	$(MAKE) -f agatti.mk optee-os
	$(MAKE) -f agatti.mk u-boot
	$(MAKE) -f agatti.mk tfa
	$(MAKE) -f agatti.mk bl2-sign
	@echo "Boot image ready: $(OUT_DIR)/tz.mbn + uefi.elf"

bootimage-clean: tfa-clean optee-os-clean u-boot-clean
	rm -f $(OUT_DIR)/tz.elf $(OUT_DIR)/tz.mbn $(OUT_DIR)/uefi.elf

################################################################################
# Linux kernel
################################################################################
LINUX_EXPORTS    = ARCH=arm64 CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"
LINUX_MAKE       = $(LINUX_EXPORTS) $(MAKE) -C $(LINUX_PATH) O=$(LINUX_OUT)
LINUX_DEFCONFIG ?= defconfig
LINUX_IMAGE      = $(LINUX_OUT)/arch/arm64/boot/Image
LINUX_DTB        = $(LINUX_OUT)/arch/arm64/boot/dts/qcom/$(LINUX_DTB_NAME).dtb

# Mainline starts from the saved Arduino config (a "make savedefconfig" of the
# booting Arduino tree): plain arm64 defconfig leaves pinctrl, sdhci, the RPM
# regulators and rpmpd as modules, and with nothing loading modules the
# console UART and eMMC never probe. On top of it the OP-TEE + PAS +
# remoteproc + GLINK/RPMSG + fastrpc + GPU/video stack is built in.
# ARM_SMMU_DISABLE_BYPASS_BY_DEFAULT is hidden behind EXPERT and cannot be
# turned off here; the ADSP relies on arm-smmu.disable_bypass=0 in U-Boot's
# do_boot bootargs instead.
# Arduino tree: MODULES=n (its xt_mark.h header is broken, so NETFILTER too).
ARDUINO_DEFCONFIG = $(CURDIR)/agatti/kernel/agatti_arduino_defconfig
ifeq ($(KERNEL),mainline)
LINUX_CONFIG_TWEAKS = \
	-e TEE -e RPMB -e OPTEE -e DEVTMPFS -e EFI_BOOT -e EFI_ZBOOT \
	-e QCOM_SCM -e QCOM_SMEM -e QCOM_SMP2P -e QCOM_SMSM -e QCOM_AOSS_QMP \
	-e RPMSG_QCOM_SMD -e QCOM_SMD_RPM \
	-e QCOM_PAS -e QCOM_PAS_TEE \
	-e REMOTEPROC -e QCOM_RPROC_COMMON -e QCOM_Q6V5_COMMON -e QCOM_Q6V5_PAS \
	-e QCOM_SYSMON -e QCOM_PIL_INFO -e QCOM_MDT_LOADER \
	-e QCOM_PDR_HELPERS -e QCOM_APR \
	-e RPMSG -e RPMSG_QCOM_GLINK -e RPMSG_QCOM_GLINK_SMEM -e RPMSG_CHAR -e RPMSG_CTRL \
	-e QCOM_FASTRPC -e DRM_MSM -e DRM_ANALOGIX_ANX7625 -e VIDEO_QCOM_VENUS \
	-d MODULES
else
LINUX_CONFIG_TWEAKS = \
	-e TEE -e OPTEE -e DEVTMPFS -e EFI_BOOT -e EFI_ZBOOT \
	-e QCOM_SCM -e QCOM_SMEM \
	-d MODULES -d NETFILTER
endif

.PHONY: linux-defconfig linux-config linux linux-clean

linux-defconfig:
	rm -rf $(LINUX_OUT)
	mkdir -p $(LINUX_OUT)
ifeq ($(KERNEL),mainline)
	cp $(ARDUINO_DEFCONFIG) $(LINUX_OUT)/.config
	$(LINUX_MAKE) olddefconfig
else
	$(LINUX_MAKE) $(LINUX_DEFCONFIG)
endif
	$(MAKE) -f agatti.mk KERNEL=$(KERNEL) linux-config

# Re-apply the config tweaks to an existing .config
linux-config:
	$(LINUX_EXPORTS) $(LINUX_PATH)/scripts/config --file $(LINUX_OUT)/.config \
		$(LINUX_CONFIG_TWEAKS)
	$(LINUX_MAKE) olddefconfig

linux:
	@if [ ! -f $(LINUX_OUT)/.config ]; then \
		$(MAKE) -f agatti.mk KERNEL=$(KERNEL) linux-defconfig; \
	fi
	$(LINUX_MAKE) -j$(shell nproc) Image
	$(LINUX_MAKE) -j1 qcom/$(LINUX_DTB_NAME).dtb

linux-clean:
	rm -rf $(LINUX_OUT) $(LINUX_PATH)/modules_dir

################################################################################
# Buildroot rootfs: the target itself comes from common.mk; this adds the
# overlay prerequisites (ADSP firmware from linux-firmware, modules_dir).
################################################################################
ADSP_FW_COMMIT ?= a32c856835b5ebdf901b857702cb02fc330ff5c6
ADSP_FW_URL    ?= https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qcom/qcm2290/adsp.mbn?id=$(ADSP_FW_COMMIT)
ADSP_FW_SHA256 ?= 2ba888211fc34fed355a5b2b83010dfd0b437036cc4f18df396dd2dc5fdb050a
ADSP_FW         = $(OVERLAY_DIR)/lib/firmware/qcom/qcm2290/adsp.mbn

.PHONY: adsp-firmware
adsp-firmware: $(ADSP_FW)

$(ADSP_FW):
	mkdir -p $(dir $@)
	curl --retry 5 -sSfL -o $@.tmp '$(ADSP_FW_URL)'
	echo "$(ADSP_FW_SHA256)  $@.tmp" | sha256sum -c - || { rm -f $@.tmp; exit 1; }
	mv $@.tmp $@

# Buildroot's target-finalize rsyncs every overlay and fails if one is absent.
$(LINUX_PATH)/modules_dir:
	mkdir -p $@

buildroot: $(ADSP_FW) $(LINUX_PATH)/modules_dir

################################################################################
# efi.bin: FAT32 boot partition image with extlinux/extlinux.conf, Image and
# the DTB. U-Boot's do_boot (board/qualcomm/default.env) does not read
# extlinux.conf: it sets bootargs itself and fatloads Image plus a hard-coded
# $(U_BOOT_DTB_NAME).dtb, so the selected DTB is stored under that name too.
# Host dependencies: mtools, dosfstools.
################################################################################
EXTLINUX_CONF   = $(CURDIR)/agatti/extlinux.conf
U_BOOT_DTB_NAME = qrb2210-arduino-imola-base
EFI_BIN         = $(OUT_DIR)/efi.bin
EFI_BIN_SIZE    = 512M

.PHONY: efi efi-clean

efi: linux
	mkdir -p $(OUT_DIR)
	rm -f $(EFI_BIN)
	truncate -s $(EFI_BIN_SIZE) $(EFI_BIN)
	mkfs.fat -F 32 $(EFI_BIN) >/dev/null
	mmd -i $(EFI_BIN) ::/extlinux
	sed 's|^\(\s*fdt \).*|\1/$(LINUX_DTB_NAME).dtb|' $(EXTLINUX_CONF) \
		> $(OUT_DIR)/extlinux.conf
	mcopy -i $(EFI_BIN) $(OUT_DIR)/extlinux.conf ::/extlinux/extlinux.conf
	mcopy -i $(EFI_BIN) $(LINUX_IMAGE) ::/Image
	mcopy -i $(EFI_BIN) $(LINUX_DTB) ::/$(LINUX_DTB_NAME).dtb
	if [ "$(LINUX_DTB_NAME)" != "$(U_BOOT_DTB_NAME)" ]; then \
		mcopy -i $(EFI_BIN) $(LINUX_DTB) ::/$(U_BOOT_DTB_NAME).dtb; \
	fi
	@echo "EFI image ready: $(EFI_BIN)"

efi-clean:
	rm -f $(EFI_BIN) $(OUT_DIR)/extlinux.conf
