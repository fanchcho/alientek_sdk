#!/bin/bash

set -e

SCRIPT_DIR=$(dirname $(realpath $BASH_SOURCE))
TOP_DIR=$(realpath $SCRIPT_DIR/../../..)
cd $TOP_DIR

function unset_board_config_all()
{
	local tmp_file=`mktemp`
	grep -o "^export.*.*=" `find $TOP_DIR/device/imx6ull -name "Board*.mk" -type f` -h | sort | uniq > $tmp_file
	source $tmp_file
	rm -f $tmp_file
}
unset_board_config_all

source $TOP_DIR/device/.BoardConfig.mk
ROCKDEV=$TOP_DIR/rockdev
PARAMETER=$TOP_DIR/device/$TARGET_PRODUCT/$PARAMETER
if [ "${OEM_DIR}x" != "x" ];then
	OEM_DIR=$TOP_DIR/device/oem/$OEM_DIR
else
	OEM_DIR=
fi
USER_DATA_DIR=$TOP_DIR/device/userdata/$USERDATA_DIR
MISC_IMG=$TOP_DIR/device/rockimg/$MISC
ROOTFS_IMG=$TOP_DIR/$ROOTFS_IMG
ROOTFS_IMG_SOURCE=$TOP_DIR/buildroot/output/$CFG_BUILDROOT/images/rootfs.$ROOTFS_TYPE
RAMBOOT_IMG=$TOP_DIR/buildroot/output/$CFG_RAMBOOT/images/ramboot.img
RECOVERY_IMG=$TOP_DIR/buildroot/output/$CFG_RECOVERY/images/recovery.img
if which fakeroot; then
FAKEROOT_TOOL="`which fakeroot`"
else
	echo -e "Install fakeroot First."
	echo -e "  sudo apt-get install fakeroot"
	exit -1
fi
OEM_FAKEROOT_SCRIPT=$ROCKDEV/oem.fs
USERDATA_FAKEROOT_SCRIPT=$ROCKDEV/userdata.fs
TRUST_IMG=$TOP_DIR/u-boot/trust.img
UBOOT_IMG=$TOP_DIR/u-boot/uboot.img
BOOT_IMG=$TOP_DIR/kernel/$BOOT_IMG
LOADER=$TOP_DIR/u-boot/*_loader_v*.bin
SPL=$TOP_DIR/u-boot/*_loader_spl.bin
#SPINOR_LOADER=$TOP_DIR/u-boot/*_loader_spinor_v*.bin
MKIMAGE=$SCRIPT_DIR/mk-image.sh
mkdir -p $ROCKDEV

# Require buildroot host tools to do image packing.
if [ ! -d "$TARGET_OUTPUT_DIR" ]; then
    echo "Source buildroot/build/envsetup.sh"
	if [ "${CFG_RAMBOOT}x" != "x" ];then
		source $TOP_DIR/buildroot/build/envsetup.sh $CFG_RAMBOOT
	fi
	if [ "${CFG_BUILDROOT}x" != "x" ];then
		source $TOP_DIR/buildroot/build/envsetup.sh $CFG_BUILDROOT
	fi
fi

# NOT support the grow partition
get_partition_size() {
	echo $PARAMETER

	PARTITIONS_PREFIX=`echo -n "CMDLINE: mtdparts=rk29xxnand:"`
	while read line
	do
		if [[ $line =~ $PARTITIONS_PREFIX ]]
		then
			partitions=`echo $line | sed "s/$PARTITIONS_PREFIX//g"`
			echo $partitions
			break
		fi
	done < $PARAMETER

	if [ -z $partitions ]
	then
		echo -e "\e[31m $PARAMETER parse no find string \"$PARTITIONS_PREFIX\" or The last line is not empty or other reason\e[0m"
		return
	fi

	PART_NAME_NEED_TO_CHECK=""
	IFS=,
	for part in $partitions;
	do
		part_size=`echo $part | cut -d '@' -f1`
		part_name=`echo $part | cut -d '(' -f2|cut -d ')' -f1`

		[[ $part_size =~ "-" ]] && continue

		part_size=$(($part_size))
		part_size_bytes=$[$part_size*512]

		case $part_name in
			uboot|uboot_[ab])
				uboot_part_size_bytes=$part_size_bytes
				PART_NAME_NEED_TO_CHECK="$PART_NAME_NEED_TO_CHECK:$part_name"
			;;
			boot|boot_[ab])
				boot_part_size_bytes=$part_size_bytes
				PART_NAME_NEED_TO_CHECK="$PART_NAME_NEED_TO_CHECK:$part_name"
			;;
			recovery)
				recovery_part_size_bytes=$part_size_bytes
				PART_NAME_NEED_TO_CHECK="$PART_NAME_NEED_TO_CHECK:$part_name"
			;;
			rootfs|system_[ab])
				rootfs_part_size_bytes=$part_size_bytes
				PART_NAME_NEED_TO_CHECK="$PART_NAME_NEED_TO_CHECK:$part_name"
			;;
			oem)
				oem_part_size_bytes=$part_size_bytes
				PART_NAME_NEED_TO_CHECK="$PART_NAME_NEED_TO_CHECK:$part_name"
			;;
		esac
	done
}

check_partition_size() {

	while true
	do
		part_name=${PART_NAME_NEED_TO_CHECK##*:}
		case $part_name in
			uboot|uboot_[ab])
				uboot_img=`realpath $ROCKDEV/uboot.img`
				if [ $uboot_part_size_bytes -lt `du -b $uboot_img | awk '{print $1}'` ]
				then
					echo -e "\e[31m error: uboot image size exceed parameter! \e[0m"
					return -1
				fi
			;;
			boot|boot_[ab])
				boot_img=`realpath $ROCKDEV/boot.img`
				if [ $boot_part_size_bytes -lt `du -b $boot_img | awk '{print $1}'` ]
				then
					echo -e "\e[31m error: boot image size exceed parameter! \e[0m"
					return -1
				fi
			;;
			recovery)
				if [ -f $RECOVERY_IMG ]
				then
					if [ $recovery_part_size_bytes -lt `du -b $RECOVERY_IMG | awk '{print $1}'` ]
					then
						echo -e "\e[31m error: recovery image size exceed parameter! \e[0m"
						return -1
					fi
				fi
			;;
			rootfs|system_[ab])
				rootfs_img=`realpath $ROCKDEV/rootfs.img`
				if [ -f $rootfs_img ]
				then
					if [ $rootfs_part_size_bytes -lt `du -bD $rootfs_img | awk '{print $1}'` ]
					then
						echo -e "\e[31m error: rootfs image size exceed parameter! \e[0m"
						return -1
					fi
				fi
			;;
		esac
		PART_NAME_NEED_TO_CHECK=${PART_NAME_NEED_TO_CHECK%:*}
		if [ -z "$PART_NAME_NEED_TO_CHECK" ]; then
			break
		fi
	done
}

if [ $ROOTFS_IMG ]
then
	if [ -f $ROOTFS_IMG ]
	then
		echo -n "create rootfs.img..."
		ln -rsf $ROOTFS_IMG $ROCKDEV/rootfs.img
		echo "done."
	else
		echo "warning: $ROOTFS_IMG not found!"
		if [ -f $ROOTFS_IMG_SOURCE ];then
			echo "Fallback to $ROOTFS_IMG_SOURCE"
			ln -rsf $ROOTFS_IMG_SOURCE $ROCKDEV/rootfs.img
		fi
	fi
fi

if [ -f $PARAMETER ]
then
	echo -n "create parameter..."
	ln -rsf $PARAMETER $ROCKDEV/parameter.txt
	echo "done."
else
	echo -e "\e[31m error: $PARAMETER not found! \e[0m"
	exit -1
fi

get_partition_size

if [ $CFG_RECOVERY ]
then
	if [ -f $RECOVERY_IMG ]
	then
		echo -n "create recovery.img..."
		ln -rsf $RECOVERY_IMG $ROCKDEV/recovery.img
		echo "done."
	else
		echo "warning: $RECOVERY_IMG not found!"
	fi
fi

if [ $MISC ]
then
	if [ -f $MISC_IMG ]
	then
		echo -n "create misc.img..."
		ln -rsf $MISC_IMG $ROCKDEV/misc.img
		echo "done."
	else
		echo "warning: $MISC_IMG not found!"
	fi
fi

if [ "${OEM_BUILDIN_BUILDROOT}x" != "YESx" ]
then
	if [ -d "$OEM_DIR" ]
	then
		echo "#!/bin/sh" > $OEM_FAKEROOT_SCRIPT
		echo "set -e" >> $OEM_FAKEROOT_SCRIPT
		if [ -d $OEM_DIR/www ]; then
			echo "chown -R www-data:www-data $OEM_DIR/www" >> $OEM_FAKEROOT_SCRIPT
		fi
		if [ "$OEM_FS_TYPE" = "ubi" ]; then
			echo "$MKIMAGE $OEM_DIR $ROCKDEV/oem.img $OEM_FS_TYPE ${OEM_PARTITION_SIZE:-$oem_part_size_bytes} oem $UBI_PAGE_SIZE $UBI_BLOCK_SIZE"  >> $OEM_FAKEROOT_SCRIPT
		else
			echo "$MKIMAGE $OEM_DIR $ROCKDEV/oem.img $OEM_FS_TYPE"  >> $OEM_FAKEROOT_SCRIPT
		fi
		chmod a+x $OEM_FAKEROOT_SCRIPT
		$FAKEROOT_TOOL -- $OEM_FAKEROOT_SCRIPT
		rm -f $OEM_FAKEROOT_SCRIPT
	else
		echo "warning: $OEM_DIR  not found!"
	fi
else
	if [ -f "$TOP_DIR/buildroot/output/$CFG_BUILDROOT/images/oem.img" ]; then
		ln -sfr $TOP_DIR/buildroot/output/$CFG_BUILDROOT/images/oem.img $ROCKDEV/oem.img
	fi
fi

if [ $USERDATA_DIR ]
then
	if [ -d "$USER_DATA_DIR" ]
	then
		echo "#!/bin/sh" > $USERDATA_FAKEROOT_SCRIPT
		echo "set -e" >> $USERDATA_FAKEROOT_SCRIPT
		if [ "$USERDATA_FS_TYPE" = "ubi" ]; then
			echo "$MKIMAGE $USER_DATA_DIR $ROCKDEV/userdata.img $USERDATA_FS_TYPE $USERDATA_PARTITION_SIZE userdata $UBI_PAGE_SIZE $UBI_BLOCK_SIZE"  >> $USERDATA_FAKEROOT_SCRIPT
		else
			echo "$MKIMAGE $USER_DATA_DIR $ROCKDEV/userdata.img $USERDATA_FS_TYPE"  >> $USERDATA_FAKEROOT_SCRIPT
		fi
		chmod a+x $USERDATA_FAKEROOT_SCRIPT
		$FAKEROOT_TOOL -- $USERDATA_FAKEROOT_SCRIPT
		rm -f $USERDATA_FAKEROOT_SCRIPT
	else
		echo "warning: $USER_DATA_DIR not found!"
	fi
fi

if [ -f $UBOOT_IMG ]
then
        echo -n "create uboot.img..."
        ln -rsf $UBOOT_IMG $ROCKDEV/uboot.img
        echo "done."
else
        echo -e "\e[31m error: $UBOOT_IMG not found! \e[0m"
fi

if [ "$UBOOT_FORMAT_TYPE" = "fit" ]; then
        rm -f $ROCKDEV/trust.img
        echo "uboot fotmat type is fit, so ignore trust.img..."
else
if [ -f $TRUST_IMG ]
then
        echo -n "create trust.img..."
        ln -rsf $TRUST_IMG $ROCKDEV/trust.img
        echo "done."
else
        echo -e "\e[31m error: $TRUST_IMG not found! \e[0m"
fi
fi

if [ -f $LOADER ]
then
        echo -n "create loader..."
        ln -rsf $LOADER $ROCKDEV/MiniLoaderAll.bin
        echo "done."
elif [ -f $SPL ]
then
	echo -n "create spl..."
        ln -rsf $SPL $ROCKDEV/MiniLoaderAll.bin
        echo "done."
else
	echo -e "\e[31m error: $LOADER not found,or there are multiple loaders! \e[0m"
	rm $LOADER || true
fi

#if [ -f $SPINOR_LOADER ]
#then
#        echo -n "create spinor loader..."
#        ln -rsf $SPINOR_LOADER $ROCKDEV/MiniLoaderAll_SpiNor.bin
#        echo "done."
#else
#	rm $SPINOR_LOADER_PATH 2>/dev/null
#fi

if [ $BOOT_IMG ]
then
	if [ -f $BOOT_IMG ]
	then
		echo -n "create boot.img..."
		ln -rsf $BOOT_IMG $ROCKDEV/boot.img
		echo "done."
	else
		echo "warning: $BOOT_IMG not found!"
	fi
fi

if [ $CFG_RAMBOOT ]
then
	if [ -f $RAMBOOT_IMG ]
	then
	        echo -n "create boot.img..."
	        ln -rsf $RAMBOOT_IMG $ROCKDEV/boot.img
	        echo "done."
	else
		echo "warning: $RAMBOOT_IMG not found!"
	fi
fi

if [ "$RAMDISK_SECURITY_BOOTUP" = "true" ];then
	if [ -f $TOP_DIR/u-boot/boot.img ]
	then
	        echo -n "Enable ramdisk security bootup, create boot.img..."
	        ln -rsf $TOP_DIR/u-boot/boot.img $ROCKDEV/boot.img
	        echo "done."
	else
		echo "warning: $TOP_DIR/u-boot/boot.img  not found!"
	fi
fi

check_partition_size

echo -e "\e[36m Image: image in rockdev is ready \e[0m"
