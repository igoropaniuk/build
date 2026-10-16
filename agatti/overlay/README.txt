Buildroot rootfs overlay for Agatti.

lib/firmware/qcom/qcm2290/adsp.mbn is fetched by "make -f agatti.mk
adsp-firmware" (a prerequisite of buildroot) from the official linux-firmware
repository at the commit pinned in agatti.mk (ADSP_FW_COMMIT), sha256-checked.
It is the ADSP (LPASS Hexagon) image loaded by remoteproc through the OP-TEE
PAS pseudo-TA. Licence: LICENSE.qcom in linux-firmware. Nothing under lib/ is
committed.
