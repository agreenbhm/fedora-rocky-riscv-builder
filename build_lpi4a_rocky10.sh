#!/bin/bash

build_kernel() {
    if [ ! -d $build_dir/thead-kernel ]; then
        #git clone --depth=1 https://github.com/revyos/thead-kernel.git -b lpi4a
        git clone --depth=1 https://github.com/revyos/th1520-linux-kernel.git -b th1520-lts thead-kernel
    fi
    cd thead-kernel
    if [ -f arch/riscv/configs/linux-thead-current_defconfig ]; then
        rm arch/riscv/configs/linux-thead-current_defconfig
    fi
    #cp $build_dir/config/linux-thead-current.config arch/riscv/configs/linux-thead-current_defconfig
    ln -sf $build_dir/thead-kernel/arch/riscv/configs/revyos_defconfig arch/riscv/configs/linux-thead-current_defconfig
    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- linux-thead-current_defconfig
    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j$(nproc)
    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- modules_install INSTALL_MOD_PATH=kmod
    cd $build_dir
    cp -rfp thead-kernel/kmod/lib/modules/* rootfs/lib/modules
}

build_u-boot() {
    if [ ! -d $build_dir/thead-u-boot ]; then
        #git clone --depth=1 https://github.com/chainsx/thead-u-boot.git -b extlinux
	git clone --depth=1 https://github.com/revyos/thead-u-boot.git -b th1520
    fi
    cd thead-u-boot
    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- light_lpi4a_defconfig
    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j$(nproc)
    cp u-boot-with-spl.bin $build_dir/firmware/lpi4a-8gb-u-boot-with-spl.bin

    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- clean

    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- light_lpi4a_16g_defconfig
    make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j$(nproc)
    cp u-boot-with-spl.bin $build_dir/firmware/lpi4a-16gb-u-boot-with-spl.bin
    cd $build_dir
}

build_opensbi() {
    if [ ! -d $build_dir/thead-opensbi ]; then
        git clone --depth=1 https://github.com/revyos/thead-opensbi.git -b lpi4a
    fi
    cd thead-opensbi
    make PLATFORM=generic FW_PIC=y CROSS_COMPILE=riscv64-linux-gnu- -j$(nproc)
    cp build/platform/generic/firmware/fw_dynamic.bin $build_dir/firmware
    cd $build_dir
}

mk_img() {
    cd $build_dir
    device=""
    LOSETUP_D_IMG
    UMOUNT_ALL
    size=`du -sh --block-size=1MiB ${build_dir}/rootfs | cut -f 1 | xargs`
    size=$(($size+720))
    losetup -D
    img_file=${build_dir}/sd.img
    dd if=/dev/zero of=${img_file} bs=1MiB count=$size status=progress && sync

    parted ${img_file} mklabel gpt mkpart primary fat32 32768s 524287s
    parted ${img_file} mkpart primary ext4 524288s 100%

    device=`losetup -f --show -P ${img_file}`
    trap 'LOSETUP_D_IMG' EXIT
    kpartx -va ${device}
    loopX=${device##*\/}
    partprobe ${device}

    sdbootp=/dev/mapper/${loopX}p1
    sdrootp=/dev/mapper/${loopX}p2
    
    mkfs.vfat -n rocky-boot ${sdbootp}
    mkfs.ext4 -L rocky-root ${sdrootp}
    mkdir -p ${root_mnt} ${boot_mnt}
    mount ${sdbootp} ${boot_mnt}
    mount ${sdrootp} ${root_mnt}

    if [ -d $boot_mnt/extlinux ]; then
        rm -rf $boot_mnt/extlinux
    fi

    mkdir -p $boot_mnt/extlinux

    line=$(blkid | grep $sdrootp)
    uuid=${line#*UUID=\"}
    uuid=${uuid%%\"*}
    
    echo "label Rocky Linux
    kernel /Image
    initrd /initrd.img
    fdtdir /
    append  console=ttyS0,115200 root=UUID=${uuid} rootfstype=ext4 rootwait rw earlycon clk_ignore_unused loglevel=7 eth=$ethaddr rootrwoptions=rw,noatime rootrwreset=yes init=/lib/systemd/systemd" \
    > $boot_mnt/extlinux/extlinux.conf

    cp $build_dir/firmware/light_aon_fpga.bin $boot_mnt
    cp $build_dir/firmware/light_c906_audio.bin $boot_mnt
    cp $build_dir/firmware/fw_dynamic.bin $boot_mnt
    cp $build_dir/thead-kernel/arch/riscv/boot/Image $boot_mnt
    cp $build_dir/thead-kernel/arch/riscv/boot/dts/thead/*lpi4a*dtb $boot_mnt

    echo "LABEL=rocky-root  / ext4    defaults,noatime 0 0" > ${build_dir}/rootfs/etc/fstab
    echo "LABEL=rocky-boot  /boot vfat    defaults,noatime 0 0" >> ${build_dir}/rootfs/etc/fstab

    if [ $(ls -1 ${build_dir}/rootfs/boot/ | wc -l) -gt 0 ]
    then
	cp -rfp ${build_dir}/rootfs/boot/* $boot_mnt
	rm -rf ${build_dir}/rootfs/boot/*
    fi

    rsync -avHAXq ${build_dir}/rootfs/* ${root_mnt}
    sync
    sleep 10

    umount $sdrootp
    umount $sdbootp

    LOSETUP_D_IMG
    UMOUNT_ALL

    losetup -D
    kpartx -d ${img_file}
}

comp_img() {
    if [ ! -f $build_dir/sd.img ]; then
        echo "sd flash file build failed!"
        exit 2
    fi

    xz -v sd.img
    mv sd.img.xz ${fedora_version}-Minimal-LicheePi-4A-riscv64-sd.img.xz

    sha256sum ${fedora_version}-Minimal-LicheePi-4A-riscv64-sd.img.xz >> ${fedora_version}-Minimal-LicheePi-4A-riscv64-sd.img.xz.sha256

}

build_dir=$(pwd)
boot_mnt=${build_dir}/boot_tmp
root_mnt=${build_dir}/root_tmp
rootfs_dir=${build_dir}/rootfs

source scripts/common.sh
source scripts/fedora_rootfs.sh

default_param
parseargs "$@" || help $?

install_reqpkg
init_base_system ${fedora_version}
install_riscv_pkgs
UMOUNT_ALL
build_kernel
build_u-boot
build_opensbi
mk_img
#comp_img
