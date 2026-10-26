# xbl_feature_config.elf

XBL feature-config image for the `xbl_config_a/b` partitions. The stock
Agatti XBL (`BOOT.XF.4.1.4-00004-KAMORTALAZ-3` from
`Agatti_bootbinaries_00021.zip`) refuses to boot without it: SBL1 fails
right after the SHRM load (`Mem dump cmd` -> `Switching to boot chain :
Recovery` -> `Both Primary and Recovery chains are corrupted. Entering
EDL mode`), before any of our images are read. Verified by bisection on
2026-10-26 (eMMC fully erased, our flash set alone fails, adding only
this file boots to the Buildroot login).

Provenance:

- Dumped over EDL from an Arduino UNO Q (Bughopper `DK0HDRE8`, SoC
  serial `0x7f320167`) on 2026-10-26, trimmed to the ELF size (the rest
  of the 128 KiB partition is zero padding).
- Byte-identical to `flash/xbl_feature_config.elf` of the Yocto build
  `core-image-base-uno-q.rootfs-20260618204641.qcomflash`.
- sha256: `2af100349edfea0db297922c7109bf5542a54f79728ca8e3766da8a59eaea26a`
  (31940 bytes).

Not downloadable from Qualcomm Software Center: the
`QRB2210_bootbinaries.1.0` releases (latest `00021`, checked 2026-10-26)
ship only `xbl.elf`. Arduino's official Debian image
(`downloads.arduino.cc/debian-im/Stable/20260528-558/...tar.zst`)
carries a *different* build of the file
(`db7b4f3615c4dfba2c693526fbd9784ff47e0beafecbcb06bce8ebc02abc8d9e`,
also 31940 bytes, untested here), so we pin the copy proven on the
board. License: same Qualcomm terms as the other boot blobs
(LICENSE.qcom-2 in the bootbinaries zip).
