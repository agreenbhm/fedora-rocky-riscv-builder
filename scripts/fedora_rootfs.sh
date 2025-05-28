#!/bin/bash

fedora_release_41="http://fedora.riscv.rocks/repos-dist/f41/latest/riscv64/Packages/f/fedora-release-41-29.noarch.rpm"
fedora_repos_41="http://fedora.riscv.rocks/repos-dist/f41/latest/riscv64/Packages/f/fedora-repos-41-1.1.riscv64.noarch.rpm"

fedora_release_42="http://fedora.riscv.rocks/repos-dist/f42/latest/riscv64/Packages/f/fedora-release-42-26.noarch.rpm"
fedora_repos_42="http://fedora.riscv.rocks/repos-dist/f42/latest/riscv64/Packages/f/fedora-repos-42-1.0.riscv64.noarch.rpm"

rocky_release_10="https://download.rockylinux.org/stg/rocky/10/BaseOS/riscv64/os/Packages/r/rocky-release-10.0-1.4.el10.noarch.rpm"
rocky_repos_10="https://download.rockylinux.org/stg/rocky/10/BaseOS/riscv64/os/Packages/r/rocky-repos-10.0-1.4.el10.noarch.rpm"

init_base_system() {
    fedora_version=$1
    
    if [ "x$fedora_version" == "x41" ]; then
        fedora_release=${fedora_release_41}
        fedora_repos=${fedora_repos_41}
    elif [ "x$fedora_version" == "x42" ]; then
        fedora_release=${fedora_release_42}
        fedora_repos=${fedora_repos_42}
    elif [ "x$fedora_version" == "xrocky10" ]; then
        fedora_release=${rocky_release_10}
        fedora_repos=${rocky_repos_10}
	fedora_version=10
    else
        echo "unsupported fedora/rocky version by this script."
        exit 2
    fi
    
    cd $build_dir
    if [ -d $build_dir/rootfs ]; then
        rm -rf rootfs
    fi
    mkdir rootfs
    mkdir -p rootfs/var/lib/rpm
    rpm --root $build_dir/rootfs/ --initdb

    rpm -ivh --nodeps --root $build_dir/rootfs/ ${fedora_release} --ignorearch
    rpm -ivh --nodeps --root $build_dir/rootfs/ ${fedora_repos} --ignorearch

    dnf --installroot=$build_dir/rootfs/ install dnf bash --nogpgcheck --forcearch riscv64 -y
    dnf --installroot=$build_dir/rootfs/ reinstall system-release --nogpgcheck --forcearch riscv64 -y
    
    sed -i "s|\$releasever|$fedora_version|g" ${rootfs_dir}/etc/yum.repos.d/*
    sed -i "s|\$basearch|riscv64|g" ${rootfs_dir}/etc/yum.repos.d/*
}

install_riscv_pkgs() {
    cd $build_dir

    cp -b /etc/resolv.conf ${rootfs_dir}/etc/resolv.conf

    mount --bind /dev ${rootfs_dir}/dev
    mount -t proc /proc ${rootfs_dir}/proc
    mount -t sysfs /sys ${rootfs_dir}/sys

    if [ "$fedora_version" == "10" ]
    then
        rm ${rootfs_dir}/etc/yum.repos.d/rocky-extras.repo
    fi

    chroot ${rootfs_dir} dnf makecache
    chroot ${rootfs_dir} dnf update -y
    chroot ${rootfs_dir} dnf install wpa_supplicant vim net-tools iproute iputils NetworkManager bluez passwd hostname -y --nogpgcheck
    chroot ${rootfs_dir} dnf install wget openssh-server openssh-clients parted chkconfig e2fsprogs dracut NetworkManager-wifi -y --nogpgcheck
    if [ "$fedora_version" != "10" ]
    then
        chroot ${rootfs_dir} dnf install alsa-utils haveged fedora-release-server realtek-firmware -y --nogpgcheck
        echo fedora-riscv > ${rootfs_dir}/etc/hostname
        rootpass='fedora'
    else
	chroot ${rootfs_dir} dnf install rocky-gpg-keys -y --nogpgcheck
        echo rocky-riscv > ${rootfs_dir}/etc/hostname
        rootpass='rocky'
    fi

    cp $build_dir/config/extend-root.sh ${rootfs_dir}/etc/rc.d/init.d/extend-root.sh
    chmod +x ${rootfs_dir}/etc/rc.d/init.d/extend-root.sh
    sed -i "s|#PermitRootLogin prohibit-password|PermitRootLogin yes|g" ${rootfs_dir}/etc/ssh/sshd_config

    cat << EOF | chroot ${rootfs_dir}  /bin/bash
    echo '$rootpass' | passwd --stdin root
    chkconfig --add extend-root.sh
    chkconfig extend-root.sh on
    dracut --no-kernel /boot/initrd.img
EOF

}
