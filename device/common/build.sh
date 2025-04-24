#!/bin/bash

export LC_ALL=C
export LD_LIBRARY_PATH=
unset IMX_CFG_TOOLCHAIN

err_handler() {
	ret=$?
	[ "$ret" -eq 0 ] && return

	echo "ERROR: Running ${FUNCNAME[1]} failed!"
	echo "ERROR: exit code $ret from line ${BASH_LINENO[0]}:"
	echo "    $BASH_COMMAND"
	exit $ret
}
trap 'err_handler' ERR
set -eE

function finish_build(){
	echo "Running ${FUNCNAME[1]} succeeded."
	cd $TOP_DIR
}

function check_config(){
	unset missing
	for var in $@; do
		eval [ \$$var ] && continue

		missing="$missing $var"
	done

	[ -z "$missing" ] && return 0

	echo "Skipping ${FUNCNAME[1]} for missing configs: $missing."
	return 1
}

function choose_target_board()
{
	echo
	echo "You're building on Linux"
	echo "Lunch menu...pick a combo:"
	echo ""

	echo "0. default BoardConfig.mk"
	echo ${IMX_TARGET_BOARD_ARRAY[@]} | xargs -n 1 | sed "=" | sed "N;s/\n/. /"

	local INDEX
	read -p "Which would you like? [0]: " INDEX
	INDEX=$((${INDEX:-0} - 1))

	if echo $INDEX | grep -vq [^0-9]; then
		IMX_BUILD_TARGET_BOARD="${IMX_TARGET_BOARD_ARRAY[$INDEX]}"
	else
		echo "Lunching for Default BoardConfig.mk boards..."
		IMX_BUILD_TARGET_BOARD=BoardConfig.mk
	fi
}

function build_select_board()
{
	IMX_TARGET_BOARD_ARRAY=( $(cd ${TARGET_PRODUCT_DIR}/; ls BoardConfig*.mk | sort) )

	IMX_TARGET_BOARD_ARRAY_LEN=${#IMX_TARGET_BOARD_ARRAY[@]}
	if [ $IMX_TARGET_BOARD_ARRAY_LEN -eq 0 ]; then
		echo "No available Board Config"
		return
	fi

	choose_target_board

	ln -rfs $TARGET_PRODUCT_DIR/$IMX_BUILD_TARGET_BOARD device/.BoardConfig.mk
	echo "switching to board: `realpath $BOARD_CONFIG`"
}

function unset_board_config_all()
{
	local tmp_file=`mktemp`
	grep -oh "^export.*IMX_.*=" `find device -name "Board*.mk"` > $tmp_file
	source $tmp_file
	rm -f $tmp_file
}

CMD=`realpath $0`
COMMON_DIR=`dirname $CMD`
TOP_DIR=$(realpath $COMMON_DIR/../..)
cd $TOP_DIR

BOARD_CONFIG=$TOP_DIR/device/.BoardConfig.mk
TARGET_PRODUCT="$TOP_DIR/device/.target_product"
TARGET_PRODUCT_DIR=$(realpath ${TARGET_PRODUCT})

if [ ! -L "$BOARD_CONFIG" -a  "$1" != "lunch" ]; then
	build_select_board
fi
unset_board_config_all
[ -L "$BOARD_CONFIG" ] && source $BOARD_CONFIG
source device/common/Version.mk

function prebuild_uboot()
{
	UBOOT_COMPILE_COMMANDS="\
			${IMX_TRUST_INI_CONFIG:+../rkbin/RKTRUST/$IMX_TRUST_INI_CONFIG} \
			${IMX_SPL_INI_CONFIG:+../rkbin/RKBOOT/$IMX_SPL_INI_CONFIG} \
			${IMX_UBOOT_SIZE_CONFIG:+--sz-uboot $IMX_UBOOT_SIZE_CONFIG} \
			${IMX_TRUST_SIZE_CONFIG:+--sz-trust $IMX_TRUST_SIZE_CONFIG}"
	UBOOT_COMPILE_COMMANDS="$(echo $UBOOT_COMPILE_COMMANDS)"

	if [ "$IMX_LOADER_UPDATE_SPL" = "true" ]; then
		UBOOT_COMPILE_COMMANDS="--spl-new $UBOOT_COMPILE_COMMANDS"
		UBOOT_COMPILE_COMMANDS="$(echo $UBOOT_COMPILE_COMMANDS)"
	fi

	if [ "$IMX_RAMDISK_SECURITY_BOOTUP" = "true" ];then
		UBOOT_COMPILE_COMMANDS=" \
			--boot_img $(cd $TOP_DIR && realpath ./rockdev/boot.img) \
			--burn-key-hash $UBOOT_COMPILE_COMMANDS \
			${IMX_ROLLBACK_INDEX_BOOT:+--rollback-index-boot $IMX_ROLLBACK_INDEX_BOOT} \
			${IMX_ROLLBACK_INDEX_UBOOT:+--rollback-index-uboot $IMX_ROLLBACK_INDEX_UBOOT} "
		UBOOT_COMPILE_COMMANDS="$(echo $UBOOT_COMPILE_COMMANDS)"
	fi
}

function usagekernel()
{
	check_config IMX_KERNEL_DTS IMX_KERNEL_DEFCONFIG || return 0

	echo "cd kernel"
	echo "make ARCH=$IMX_ARCH $IMX_KERNEL_DEFCONFIG $IMX_KERNEL_DEFCONFIG_FRAGMENT"
	echo "make ARCH=$IMX_ARCH $IMX_KERNEL_DTS.img -j$IMX_JOBS"
}

function usageuboot()
{
	check_config IMX_UBOOT_DEFCONFIG || return 0
	prebuild_uboot

	cd uboot
	echo "cd uboot"
	if [ -n "$IMX_UBOOT_DEFCONFIG_FRAGMENT" ]; then
		if [ -f "configs/${IMX_UBOOT_DEFCONFIG}_defconfig" ]; then
			echo "make ${IMX_UBOOT_DEFCONFIG}_defconfig $IMX_UBOOT_DEFCONFIG_FRAGMENT"
		else
			echo "make ${IMX_UBOOT_DEFCONFIG}.config $IMX_UBOOT_DEFCONFIG_FRAGMENT"
		fi
		echo "./make.sh $UBOOT_COMPILE_COMMANDS"
	else
		echo "./make.sh $IMX_UBOOT_DEFCONFIG $UBOOT_COMPILE_COMMANDS"
	fi

	if [ "$IMX_IDBLOCK_UPDATE_SPL" = "true" ]; then
		echo "./make.sh --idblock --spl"
	fi

	finish_build
}

function usagerootfs()
{
	check_config IMX_ROOTFS_IMG || return 0

	if [ "${IMX_CFG_BUILDROOT}x" != "x" ];then
		echo "source envsetup.sh $IMX_CFG_BUILDROOT"
	else
		if [ "${IMX_CFG_RAMBOOT}x" != "x" ];then
			echo "source envsetup.sh $IMX_CFG_RAMBOOT"
		else
			echo "Not found config buildroot. Please Check !!!"
		fi
	fi

	case "${IMX_ROOTFS_SYSTEM:-buildroot}" in
		*)
			echo "make"
			;;
	esac
}

function usagerecovery()
{
	check_config IMX_CFG_RECOVERY || return 0

	echo "source envsetup.sh $IMX_CFG_RECOVERY"
	echo "$COMMON_DIR/mk-ramdisk.sh recovery.img $IMX_CFG_RECOVERY"
}

function usageramboot()
{
	check_config IMX_CFG_RAMBOOT || return 0

	echo "source envsetup.sh $IMX_CFG_RAMBOOT"
	echo "$COMMON_DIR/mk-ramdisk.sh ramboot.img $IMX_CFG_RAMBOOT"
}

function usagemodules()
{
	check_config IMX_KERNEL_DEFCONFIG || return 0

	echo "cd kernel"
	echo "make ARCH=$IMX_ARCH $IMX_KERNEL_DEFCONFIG"
	echo "make ARCH=$IMX_ARCH modules -j$IMX_JOBS"
}

function usage()
{
	echo "Usage: build.sh [OPTIONS]"
	echo "Available options:"
	echo "BoardConfig*.mk    -switch to specified board config"
	echo "lunch              -list current SDK boards and switch to specified board config"
	echo "uboot              -build uboot"
	echo "spl                -build spl"
	echo "loader             -build loader"
	echo "kernel             -build kernel"
	echo "modules            -build kernel modules"
	echo "toolchain          -build toolchain"
	echo "rootfs             -build default rootfs, currently build buildroot as default"
	echo "buildroot          -build buildroot rootfs"
	echo "ramboot            -build ramboot image"
	echo "multi-npu_boot     -build boot image for multi-npu board"
	echo "pcba               -build pcba"
	echo "recovery           -build recovery"
	echo "all                -build uboot, kernel, rootfs, recovery image"
	echo "cleanall           -clean uboot, kernel, rootfs, recovery"
	echo "firmware           -pack all the image we need to boot up system"
	echo "updateimg          -pack update image"
	echo "otapackage         -pack ab update otapackage image (update_ota.img)"
	echo "sdpackage          -pack update sdcard package image (update_sdcard.img)"
	echo "save               -save images, patches, commands used to debug"
	echo "allsave            -build all & firmware & updateimg & save"
	echo "check              -check the environment of building"
	echo "info               -see the current board building information"
	echo "app/<pkg>          -build packages in the dir of app/*"
	echo "external/<pkg>     -build packages in the dir of external/*"
	echo ""
	echo "Default option is 'allsave'."
}

function build_info(){
	if [ ! -L $TARGET_PRODUCT_DIR ];then
		echo "No found target product!!!"
	fi
	if [ ! -L $BOARD_CONFIG ];then
		echo "No found target board config!!!"
	fi

	echo "Current Building Information:"
	echo "Target Product: $TARGET_PRODUCT_DIR"
	echo "Target BoardConfig: `realpath $BOARD_CONFIG`"
	echo "Target Misc config:"
	echo "`env |grep "^IMX_" | grep -v "=$" | sort`"

	local kernel_file_dtb

	if [ "$IMX_ARCH" == "arm" ]; then
		kernel_file_dtb="${TOP_DIR}/kernel/arch/arm/boot/dts/${IMX_KERNEL_DTS}.dtb"
	else
		kernel_file_dtb="${TOP_DIR}/kernel/arch/arm64/boot/dts/${IMX_KERNEL_DTS}.dtb"
	fi

	rm -f $kernel_file_dtb

	cd kernel
	make ARCH=$IMX_ARCH dtbs -j$IMX_JOBS

	build_check_power_domain
}

function build_check_power_domain(){
	local dump_kernel_dtb_file
	local tmp_phandle_file
	local tmp_io_domain_file
	local tmp_regulator_microvolt_file
	local tmp_final_target
	local tmp_none_item
	local kernel_file_dtb_dts

	if [ "$IMX_ARCH" == "arm" ]; then
		kernel_file_dtb_dts="${TOP_DIR}/kernel/arch/arm/boot/dts/$IMX_KERNEL_DTS"
	else
		kernel_file_dtb_dts="${TOP_DIR}/kernel/arch/arm64/boot/dts/$IMX_KERNEL_DTS"
	fi

	dump_kernel_dtb_file=${kernel_file_dtb_dts}.dump.dts
	tmp_phandle_file=`mktemp`
	tmp_io_domain_file=`mktemp`
	tmp_regulator_microvolt_file=`mktemp`
	tmp_final_target=`mktemp`
	tmp_grep_file=`mktemp`

	dtc -I dtb -O dts -o ${dump_kernel_dtb_file} ${kernel_file_dtb_dts}.dtb 2>/dev/null
	if ! grep -Pzo "io-domains\s*{(\n|\w|-|;|=|<|>|\"|_|\s|,)*};" $dump_kernel_dtb_file 1>$tmp_grep_file 2>/dev/null; then
		echo "Not Found io-domains in ${kernel_file_dtb_dts}.dts"
		rm -f $tmp_grep_file
		return 0
	fi
	grep -a supply $tmp_grep_file > $tmp_io_domain_file
	rm -f $tmp_grep_file
	awk '{print "phandle = " $3}' $tmp_io_domain_file > $tmp_phandle_file


	while IFS= read -r item_phandle && IFS= read -u 3 -r item_domain
	do
		echo "${item_domain% *}" >> $tmp_regulator_microvolt_file
		tmp_none_item=${item_domain% *}
		cmds="grep -Pzo \"{(\\n|\w|-|;|=|<|>|\\\"|_|\s)*"$item_phandle\"

		eval "$cmds $dump_kernel_dtb_file | strings | grep "regulator-m..-microvolt" >> $tmp_regulator_microvolt_file" || \
			eval "sed -i \"/${tmp_none_item}/d\" $tmp_regulator_microvolt_file" && continue

		echo >> $tmp_regulator_microvolt_file
	done < $tmp_phandle_file 3<$tmp_io_domain_file

	while read -r regulator_val
	do
		if echo ${regulator_val} | grep supply &>/dev/null; then
			echo -e "\n\n\e[1;33m${regulator_val%*=}\e[0m" >> $tmp_final_target
		else
			tmp_none_item=${regulator_val##*<}
			tmp_none_item=${tmp_none_item%%>*}
			echo -e "${regulator_val%%<*} \e[1;31m$(( $tmp_none_item / 1000 ))mV\e[0m" >> $tmp_final_target
		fi
	done < $tmp_regulator_microvolt_file

	echo -e "\e[41;1;30m PLEASE CHECK BOARD GPIO POWER DOMAIN CONFIGURATION !!!!!\e[0m"
	echo -e "\e[41;1;30m <<< ESPECIALLY Wi-Fi/Flash/Ethernet IO power domain >>> !!!!!\e[0m"
	echo -e "\e[41;1;30m Check Node [pmu_io_domains] in the file: ${kernel_file_dtb_dts}.dts \e[0m"
	echo
	echo -e "\e[41;1;30m 请再次确认板级的电源域配置！！！！！！\e[0m"
	echo -e "\e[41;1;30m <<< 特别是Wi-Fi，FLASH，以太网这几路IO电源的配置 >>> ！！！！！\e[0m"
	echo -e "\e[41;1;30m 检查内核文件 ${kernel_file_dtb_dts}.dts 的节点 [pmu_io_domains] \e[0m"
	cat $tmp_final_target

	rm -f $tmp_phandle_file
	rm -f $tmp_regulator_microvolt_file
	rm -f $tmp_io_domain_file
	rm -f $tmp_final_target
	rm -f $dump_kernel_dtb_file
}

function build_check(){
	local build_depend_cfg="build-depend-tools.txt"
	common_product_build_tools="device/common/$build_depend_cfg"
	target_product_build_tools="device/$IMX_TARGET_PRODUCT/$build_depend_cfg"
	cat $common_product_build_tools $target_product_build_tools 2>/dev/null | while read chk_item
		do
			chk_item=${chk_item###*}
			if [ -z "$chk_item" ]; then
				continue
			fi

			dst=${chk_item%%,*}
			src=${chk_item##*,}
			echo "**************************************"
			if eval $dst &>/dev/null;then
				echo "Check [OK]: $dst"
			else
				echo "Please install ${dst%% *} first"
				echo "    sudo apt-get install $src"
			fi
		done
}

function build_pkg() {
	check_config IMX_CFG_BUILDROOT || check_config IMX_CFG_RAMBOOT || check_config IMX_CFG_RECOVERY || check_config IMX_CFG_PCBA || return 0

	local target_pkg=$1
	target_pkg=${target_pkg%*/}

	if [ ! -d $target_pkg ];then
		echo "build pkg: error: not found package $target_pkg"
		return 1
	fi

	if ! eval [ $IMX_package_mk_arrry ];then
		IMX_package_mk_arrry=( $(find buildroot/package/ -name "*.mk" | sort) )
	fi

	local pkg_mk pkg_config_in pkg_br pkg_final_target pkg_final_target_upper pkg_cfg

	for it in ${IMX_package_mk_arrry[@]}
	do
		pkg_final_target=$(basename $it)
		pkg_final_target=${pkg_final_target%%.mk*}
		pkg_final_target_upper=${pkg_final_target^^}
		pkg_final_target_upper=${pkg_final_target_upper//-/_}
		if grep "${pkg_final_target_upper}_SITE.*$target_pkg" $it &>/dev/null; then
			pkg_mk=$it
			pkg_config_in=$(dirname $pkg_mk)/Config.in
			pkg_br=BR2_PACKAGE_$pkg_final_target_upper

			for cfg in IMX_CFG_BUILDROOT IMX_CFG_RAMBOOT IMX_CFG_RECOVERY IMX_CFG_PCBA
			do
				if eval [ \$$cfg ] ;then
					pkg_cfg=$( eval "echo \$$cfg" )
					if grep -wq ${pkg_br}=y buildroot/output/$pkg_cfg/.config; then
						echo "Found $pkg_br in buildroot/output/$pkg_cfg/.config "
						make -C buildroot/output/$pkg_cfg ${pkg_final_target}-dirclean O=buildroot/output/$pkg_cfg
						make -C buildroot/output/$pkg_cfg ${pkg_final_target}-rebuild O=buildroot/output/$pkg_cfg
					else
						echo "[SKIP BUILD $target_pkg] NOT Found ${pkg_br}=y in buildroot/output/$pkg_cfg/.config"
					fi
				fi
			done
		fi
	done

	finish_build
}

function build_uboot(){
	check_config IMX_UBOOT_DEFCONFIG || return 0

	echo "============Start building uboot============"
	echo "TARGET_UBOOT_CONFIG=$IMX_UBOOT_DEFCONFIG"
	echo "========================================="

	cd uboot
	./make.sh imx6ull
	cd -
	
	finish_build
}

# TODO: build_spl can be replaced by build_uboot with define IMX_LOADER_UPDATE_SPL
function build_spl(){
	check_config IMX_SPL_DEFCONFIG || return 0

	echo "============Start building spl============"
	echo "TARGET_SPL_CONFIG=$IMX_SPL_DEFCONFIG"
	echo "========================================="

	cd uboot
	rm -f *spl.bin
	./make.sh $IMX_SPL_DEFCONFIG
	./make.sh --spl

	finish_build
}

function build_loader(){
	check_config IMX_LOADER_BUILD_TARGET || return 0

	echo "============Start building loader============"
	echo "IMX_LOADER_BUILD_TARGET=$IMX_LOADER_BUILD_TARGET"
	echo "=========================================="

	cd loader
	./build.sh $IMX_LOADER_BUILD_TARGET

	finish_build
}

function build_kernel(){
	check_config IMX_KERNEL_DTS IMX_KERNEL_DEFCONFIG || return 0

	echo "============Start building kernel============"
	echo "TARGET_ARCH          =$IMX_ARCH"
	echo "TARGET_KERNEL_CONFIG =$IMX_KERNEL_DEFCONFIG"
	echo "TARGET_KERNEL_DTS    =$IMX_KERNEL_DTS"
	echo "TARGET_KERNEL_CONFIG_FRAGMENT =$IMX_KERNEL_DEFCONFIG_FRAGMENT"
	echo "=========================================="

	cd kernel
	make ARCH=$IMX_ARCH $IMX_KERNEL_DEFCONFIG $IMX_KERNEL_DEFCONFIG_FRAGMENT
	make ARCH=$IMX_ARCH $IMX_KERNEL_DTS.img -j$IMX_JOBS
	if [ -f "$TOP_DIR/device/$IMX_TARGET_PRODUCT/$IMX_KERNEL_FIT_ITS" ]; then
		$COMMON_DIR/mk-fitimage.sh $TOP_DIR/kernel/$IMX_BOOT_IMG \
			$TOP_DIR/device/$IMX_TARGET_PRODUCT/$IMX_KERNEL_FIT_ITS
	fi


	echo -e "\t\n\n === Sign Boot.img === \n\n"
	cd zlg
	./sign-apply-imx6ull.sh || exit 1
	cp fit/boot-signed.img ../boot.img 
	cd -
	cp zlg/fit/boot-signed.img boot.img

	echo -e "\t\n === Sign End === \n\n"

	build_check_power_domain

	finish_build
}

function build_modules(){
	check_config IMX_KERNEL_DEFCONFIG || return 0

	echo "============Start building kernel modules============"
	echo "TARGET_ARCH          =$IMX_ARCH"
	echo "TARGET_KERNEL_CONFIG =$IMX_KERNEL_DEFCONFIG"
	echo "TARGET_KERNEL_CONFIG_FRAGMENT =$IMX_KERNEL_DEFCONFIG_FRAGMENT"
	echo "=================================================="

	cd kernel
	make ARCH=$IMX_ARCH $IMX_KERNEL_DEFCONFIG $IMX_KERNEL_DEFCONFIG_FRAGMENT
	make ARCH=$IMX_ARCH modules -j$IMX_JOBS

	finish_build
}

function build_toolchain(){
	check_config IMX_CFG_TOOLCHAIN || return 0

	echo "==========Start building toolchain =========="
	echo "TARGET_TOOLCHAIN_CONFIG=$IMX_CFG_TOOLCHAIN"
	echo "========================================="

	/usr/bin/time -f "you take %E to build toolchain" \
		$COMMON_DIR/mk-toolchain.sh $BOARD_CONFIG

	finish_build
}

function build_buildroot(){
	check_config IMX_CFG_BUILDROOT || return 0

	echo "==========Start building buildroot=========="
	echo "TARGET_BUILDROOT_CONFIG=$IMX_CFG_BUILDROOT"
	echo "========================================="

	/usr/bin/time -f "you take %E to build builroot" \
		$COMMON_DIR/mk-buildroot.sh $BOARD_CONFIG

	finish_build
}

function build_ramboot(){
	check_config IMX_CFG_RAMBOOT || return 0

	echo "=========Start building ramboot========="
	echo "TARGET_RAMBOOT_CONFIG=$IMX_CFG_RAMBOOT"
	echo "====================================="

	/usr/bin/time -f "you take %E to build ramboot" \
		$COMMON_DIR/mk-ramdisk.sh ramboot.img $IMX_CFG_RAMBOOT

	ln -rsf buildroot/output/$IMX_CFG_RAMBOOT/images/ramboot.img \
		rockdev/boot.img

	finish_build
}

function build_multi-npu_boot(){
	check_config IMX_MULTINPU_BOOT || return 0

	echo "=========Start building multi-npu boot========="
	echo "TARGET_RAMBOOT_CONFIG=$IMX_CFG_RAMBOOT"
	echo "====================================="

	/usr/bin/time -f "you take %E to build multi-npu boot" \
		$COMMON_DIR/mk-multi-npu_boot.sh

	finish_build
}


function build_rootfs(){
	check_config IMX_ROOTFS_IMG || return 0

	IMX_ROOTFS_DIR=.rootfs
	ROOTFS_IMG=${IMX_ROOTFS_IMG##*/}

	rm -rf $IMX_ROOTFS_IMG $IMX_ROOTFS_DIR
	mkdir -p ${IMX_ROOTFS_IMG%/*} $IMX_ROOTFS_DIR

	case "$1" in
		*)
			build_buildroot
			for f in $(ls buildroot/output/$IMX_CFG_BUILDROOT/images/rootfs.*);do
				ln -rsf $f $IMX_ROOTFS_DIR/
			done
			;;
	esac

	if [ ! -f "$IMX_ROOTFS_DIR/$ROOTFS_IMG" ]; then
		echo "There's no $ROOTFS_IMG generated..."
		exit 1
	fi

	ln -rsf $IMX_ROOTFS_DIR/$ROOTFS_IMG $IMX_ROOTFS_IMG

	cp buildroot/output/alientek_imx6ull/images/rootfs.ext2 /mnt/hgfs/share/rootfs.img
	finish_build
}

function build_recovery(){

	if [ "$IMX_UPDATE_SDCARD_ENABLE_FOR_AB" = "true" ] ;then
		IMX_CFG_RECOVERY=$IMX_UPDATE_SDCARD_CFG_RECOVERY
	fi

	check_config IMX_CFG_RECOVERY || return 0

	echo "==========Start building recovery=========="
	echo "TARGET_RECOVERY_CONFIG=$IMX_CFG_RECOVERY"
	echo "========================================"

	/usr/bin/time -f "you take %E to build recovery" \
		$COMMON_DIR/mk-ramdisk.sh recovery.img $IMX_CFG_RECOVERY

	finish_build
}

function build_pcba(){
	check_config IMX_CFG_PCBA || return 0

	echo "==========Start building pcba=========="
	echo "TARGET_PCBA_CONFIG=$IMX_CFG_PCBA"
	echo "===================================="

	/usr/bin/time -f "you take %E to build pcba" \
		$COMMON_DIR/mk-ramdisk.sh pcba.img $IMX_CFG_PCBA

	finish_build
}

function build_all(){
	echo "============================================"
	echo "TARGET_ARCH=$IMX_ARCH"
	echo "TARGET_PLATFORM=$IMX_TARGET_PRODUCT"
	echo "TARGET_UBOOT_CONFIG=$IMX_UBOOT_DEFCONFIG"
	echo "TARGET_SPL_CONFIG=$IMX_SPL_DEFCONFIG"
	echo "TARGET_KERNEL_CONFIG=$IMX_KERNEL_DEFCONFIG"
	echo "TARGET_KERNEL_DTS=$IMX_KERNEL_DTS"
	echo "TARGET_TOOLCHAIN_CONFIG=$IMX_CFG_TOOLCHAIN"
	echo "TARGET_BUILDROOT_CONFIG=$IMX_CFG_BUILDROOT"
	echo "TARGET_RECOVERY_CONFIG=$IMX_CFG_RECOVERY"
	echo "TARGET_PCBA_CONFIG=$IMX_CFG_PCBA"
	echo "TARGET_RAMBOOT_CONFIG=$IMX_CFG_RAMBOOT"
	echo "============================================"

	# NOTE: On secure boot-up world, if the images build with fit(flattened image tree)
	#       we will build kernel and ramboot firstly,
	#       and then copy images into u-boot to sign the images.
	if [ "$IMX_RAMDISK_SECURITY_BOOTUP" != "true" ];then
		#note: if build spl, it will delete loader.bin in uboot directory,
		# so can not build uboot and spl at the same time.
		if [ -z $IMX_SPL_DEFCONFIG ]; then
			build_uboot
		else
			build_spl
		fi
	fi

	build_loader
	build_kernel
	build_toolchain
	build_rootfs ${IMX_ROOTFS_SYSTEM:-buildroot}
	build_recovery
	build_ramboot

	if [ "$IMX_RAMDISK_SECURITY_BOOTUP" = "true" ];then
		#note: if build spl, it will delete loader.bin in uboot directory,
		# so can not build uboot and spl at the same time.
		if [ -z $IMX_SPL_DEFCONFIG ]; then
			build_uboot
		else
			build_spl
		fi
	fi

	finish_build
}

function build_cleanall(){
	echo "clean uboot, kernel, rootfs, recovery"

	cd uboot
	make distclean
	cd -
	cd kernel
	make distclean
	cd -
	rm -rf buildroot/output

	finish_build
}

function build_firmware(){
	./mkfirmware.sh $BOARD_CONFIG

	finish_build
}

function build_updateimg(){
	IMAGE_PATH=$TOP_DIR/rockdev
	PACK_TOOL_DIR=$TOP_DIR/tools/linux/Linux_Pack_Firmware

	cd $PACK_TOOL_DIR/rockdev

	if [ -f "$IMX_PACKAGE_FILE_AB" ]; then
		build_sdcard_package
		build_otapackage

		cd $PACK_TOOL_DIR/rockdev
		echo "Make Linux a/b update_ab.img."
		source_package_file_name=`ls -lh package-file | awk -F ' ' '{print $NF}'`
		ln -fs "$IMX_PACKAGE_FILE_AB" package-file
		./mkupdate.sh
		mv update.img $IMAGE_PATH/update_ab.img
		ln -fs $source_package_file_name package-file
	else
		echo "Make update.img"

		if [ -f "$IMX_PACKAGE_FILE" ]; then
			source_package_file_name=`ls -lh package-file | awk -F ' ' '{print $NF}'`
			ln -fs "$IMX_PACKAGE_FILE" package-file
			./mkupdate.sh
			ln -fs $source_package_file_name package-file
		else
			./mkupdate.sh
		fi
		mv update.img $IMAGE_PATH
	fi

	finish_build
}

function build_otapackage(){
	IMAGE_PATH=$TOP_DIR/rockdev
	PACK_TOOL_DIR=$TOP_DIR/tools/linux/Linux_Pack_Firmware

	echo "Make ota ab update_ota.img"
	cd $PACK_TOOL_DIR/rockdev
	if [ -f "$IMX_PACKAGE_FILE_OTA" ]; then
		source_package_file_name=`ls -lh $PACK_TOOL_DIR/rockdev/package-file | awk -F ' ' '{print $NF}'`
		ln -fs "$IMX_PACKAGE_FILE_OTA" package-file
		./mkupdate.sh
		mv update.img $IMAGE_PATH/update_ota.img
		ln -fs $source_package_file_name package-file
	fi

	finish_build
}

function build_sdcard_package(){

	check_config IMX_UPDATE_SDCARD_ENABLE_FOR_AB || return 0

	local image_path=$TOP_DIR/rockdev
	local pack_tool_dir=$TOP_DIR/tools/linux/Linux_Pack_Firmware
	local IMX_sdupdate_ab_misc=${IMX_SDUPDATE_AB_MISC:=sdupdate-ab-misc.img}
	local IMX_parameter_sdupdate=${IMX_PARAMETER_SDUPDATE:=parameter-sdupdate.txt}
	local IMX_package_file_sdcard_update=${IMX_PACKAGE_FILE_SDCARD_UPDATE:=sdcard-update-package-file}
	local sdupdate_ab_misc_img=$TOP_DIR/device/rockimg/$IMX_sdupdate_ab_misc
	local parameter_sdupdate=$TOP_DIR/device/rockimg/$IMX_parameter_sdupdate
	local recovery_img=$TOP_DIR/buildroot/output/$IMX_UPDATE_SDCARD_CFG_RECOVERY/images/recovery.img

	if [ $IMX_UPDATE_SDCARD_CFG_RECOVERY ]; then
		if [ -f $recovery_img ]; then
			echo -n "create recovery.img..."
			ln -rsf $recovery_img $image_path/recovery.img
		else
			echo "error: $recovery_img not found!"
			return 1
		fi
	fi


	echo "Make sdcard update update_sdcard.img"
	cd $pack_tool_dir/rockdev
	if [ -f "$IMX_package_file_sdcard_update" ]; then

		if [ $IMX_parameter_sdupdate ]; then
			if [ -f $parameter_sdupdate ]; then
				echo -n "create sdcard update image parameter..."
				ln -rsf $parameter_sdupdate $image_path/
			fi
		fi

		if [ $IMX_sdupdate_ab_misc ]; then
			if [ -f $sdupdate_ab_misc_img ]; then
				echo -n "create sdupdate ab misc.img..."
				ln -rsf $sdupdate_ab_misc_img $image_path/
			fi
		fi

		source_package_file_name=`ls -lh $pack_tool_dir/rockdev/package-file | awk -F ' ' '{print $NF}'`
		ln -fs "$IMX_package_file_sdcard_update" package-file
		./mkupdate.sh
		mv update.img $image_path/update_sdcard.img
		ln -fs $source_package_file_name package-file
		rm -f $image_path/$IMX_sdupdate_ab_misc $image_path/$IMX_parameter_sdupdate $image_path/recovery.img
	fi

	finish_build
}

function build_save(){
	IMAGE_PATH=$TOP_DIR/rockdev
	DATE=$(date  +%Y%m%d.%H%M)
	STUB_PATH=Image/"$IMX_KERNEL_DTS"_"$DATE"_RELEASE_TEST
	STUB_PATH="$(echo $STUB_PATH | tr '[:lower:]' '[:upper:]')"
	export STUB_PATH=$TOP_DIR/$STUB_PATH
	export STUB_PATCH_PATH=$STUB_PATH/PATCHES
	mkdir -p $STUB_PATH

	#Generate patches
	.repo/repo/repo forall -c \
		"$TOP_DIR/device/common/gen_patches_body.sh"

	#Copy stubs
	.repo/repo/repo manifest -r -o $STUB_PATH/manifest_${DATE}.xml
	mkdir -p $STUB_PATCH_PATH/kernel
	cp kernel/.config $STUB_PATCH_PATH/kernel
	cp kernel/vmlinux $STUB_PATCH_PATH/kernel
	mkdir -p $STUB_PATH/IMAGES/
	cp $IMAGE_PATH/* $STUB_PATH/IMAGES/

	#Save build command info
	echo "UBOOT:  defconfig: $IMX_UBOOT_DEFCONFIG" >> $STUB_PATH/build_cmd_info
	echo "KERNEL: defconfig: $IMX_KERNEL_DEFCONFIG, dts: $IMX_KERNEL_DTS" >> $STUB_PATH/build_cmd_info
	echo "BUILDROOT: $IMX_CFG_BUILDROOT" >> $STUB_PATH/build_cmd_info

	finish_build
}

function build_allsave(){
	rm -fr $TOP_DIR/rockdev
	build_all
	build_firmware
	build_updateimg
	build_save

	build_check_power_domain

	finish_build
}

#=========================
# build targets
#=========================

if echo $@|grep -wqE "help|-h"; then
	if [ -n "$2" -a "$(type -t usage$2)" == function ]; then
		echo "###Current SDK Default [ $2 ] Build Command###"
		eval usage$2
	else
		usage
	fi
	exit 0
fi

OPTIONS="${@:-allsave}"

[ -f "device/$IMX_TARGET_PRODUCT/$IMX_BOARD_PRE_BUILD_SCRIPT" ] \
	&& source "device/$IMX_TARGET_PRODUCT/$IMX_BOARD_PRE_BUILD_SCRIPT"  # board hooks

for option in ${OPTIONS}; do
	echo "processing option: $option"
	case $option in
		BoardConfig*.mk)
			option=device/$IMX_TARGET_PRODUCT/$option
			;&
		*.mk)
			CONF=$(realpath $option)
			echo "switching to board: $CONF"
			if [ ! -f $CONF ]; then
				echo "not exist!"
				exit 1
			fi

			ln -rsf $CONF $BOARD_CONFIG
			;;
		lunch) build_select_board ;;
		all) build_all ;;
		save) build_save ;;
		allsave) build_allsave ;;
		check) build_check ;;
		cleanall) build_cleanall ;;
		firmware) build_firmware ;;
		updateimg) build_updateimg ;;
		otapackage) build_otapackage ;;
		sdpackage) build_sdcard_package ;;
		toolchain) build_toolchain ;;
		spl) build_spl ;;
		uboot) build_uboot ;;
		loader) build_loader ;;
		kernel) build_kernel ;;
		modules) build_modules ;;
		rootfs|buildroot) build_rootfs $option ;;
		pcba) build_pcba ;;
		ramboot) build_ramboot ;;
		recovery) build_recovery ;;
		multi-npu_boot) build_multi-npu_boot ;;
		info) build_info ;;
		app/*|external/*) build_pkg $option ;;
		*) usage ;;
	esac
done
