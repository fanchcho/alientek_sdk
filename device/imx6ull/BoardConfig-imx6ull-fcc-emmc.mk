#!/bin/bash

# Target arch
export IMX_ARCH=arm
# Uboot defconfig
export IMX_UBOOT_DEFCONFIG=mx6ull_fcc_emmc
# Uboot image format type: fit(flattened image tree)
export IMX_UBOOT_FORMAT_TYPE=fit
# Kernel defconfig
export IMX_KERNEL_DEFCONFIG=imx_fcc_emmc_defconfig
# Kernel defconfig fragment
export IMX_KERNEL_DEFCONFIG_FRAGMENT=
# Kernel dts
export IMX_KERNEL_DTS=imx6ull-fcc-emmc
# boot image type
export IMX_BOOT_IMG=boot.img
# kernel image path
export IMX_KERNEL_IMG=kernel/arch/arm/boot/Image
# kernel image format type: fit(flattened image tree)
export IMX_KERNEL_FIT_ITS=boot.its
# parameter for GPT table
export IMX_PARAMETER=parameter-buildroot-fit.txt
# Buildroot config
export IMX_CFG_BUILDROOT=alientek_imx6ull
# Recovery config
export IMX_CFG_RECOVERY=imx6ull_recovery
# Recovery image format type: fit(flattened image tree)
export IMX_RECOVERY_FIT_ITS=boot4recovery.its
# ramboot config
export IMX_CFG_RAMBOOT=
# Pcba config
export IMX_CFG_PCBA=
# Build jobs
export IMX_JOBS=12
# target chip
export IMX_TARGET_PRODUCT=imx6ull
# Set rootfs type, including ext2 ext4 squashfs
export IMX_ROOTFS_TYPE=ext4
# rootfs image path
export IMX_ROOTFS_IMG=rockdev/rootfs.${IMX_ROOTFS_TYPE}
# Set ramboot image type
export IMX_RAMBOOT_TYPE=
# Set oem partition type, including ext2 squashfs
export IMX_OEM_FS_TYPE=ext2
# Set userdata partition type, including ext2, fat
export IMX_USERDATA_FS_TYPE=ext2
#OEM config
export IMX_OEM_DIR=oem_normal
# OEM build on buildroot
#export IMX_OEM_BUILDIN_BUILDROOT=YES
#userdata config
export IMX_USERDATA_DIR=userdata_normal
#misc image
export IMX_MISC=blank-misc.img
#choose enable distro module
export IMX_DISTRO_MODULE=
# Define pre-build script for this board
export IMX_BOARD_PRE_BUILD_SCRIPT=app-build.sh
