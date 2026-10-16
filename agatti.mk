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

include common.mk
include toolchain.mk

################################################################################
# Top-level targets
################################################################################
.PHONY: all clean help

all: bootimage

clean: bootimage-clean

help:
	@echo "Qualcomm QCM2290/QRB2210 (Agatti / Arduino UNO Q) build system"
	@echo ""
	@echo "  make all           Build everything"
	@echo "  make bootimage     optee-os -> u-boot -> tfa -> bl2-sign (agatti/output/tz.mbn + uefi.elf)"
	@echo ""
	@echo "Per-component: optee-os u-boot tfa bl2-sign and *-clean"

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
