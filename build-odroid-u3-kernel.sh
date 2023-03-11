#!/bin/bash

####################################
#  build own odroid-u3-plus kernel #
####################################

set -x

export KernelBranch=v6.1.16
export ARCH=arm
export SYSTEM_TYPE=odroid_u3
export SYSTEM_ARCH=armv7l
export DISTRO=bullseye

# get required binaries
apt-get install -y sudo make git build-essential u-boot-tools gcc-arm-linux-gnueabihf bc lzop flex bison libssl-dev libncurses-dev bc tree;
apt-get install -y systemtap-sdt-dev libelf-dev libslang2-dev libperl-dev liblzma-dev libzstd-dev libcap-dev libnuma-dev libbabeltrace-ctf-dev libtraceevent-dev;

# prepare directory structure
mkdir -p /compile/source /compile/result/stable /compile/doc

cd /compile/source;

# change preferredKernel to tags available at https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
git clone --depth 1 -b $KernelBranch https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git;

mv linux-stable linux-stable-exy;

cd /compile/doc;
git clone https://github.com/hexdump0815/kernel-config-options;
git clone https://github.com/hexdump0815/kernel-extra-patches;
git clone https://github.com/hexdump0815/linux-mainline-and-mali-generic-stable-kernel.git;
mv linux-mainline-and-mali-generic-stable-kernel stable;

# PATCHES ##########################################################################################################
cd /compile/source/linux-stable-exy;

# add cmdline option to set a fixed ethernet mac address on the kernel
# cmdline to avoid getting a randomone on each boot
patch -p1 < /compile/doc/stable/misc.exy/patches/eth-hw-addr-v6.0.patch

# add u3noplus dtb for the non plus version to fix reboot for it - has to be redone for each new kernel version
git checkout -- arch/arm/boot/dts/Makefile
cp arch/arm/boot/dts/exynos4412-odroidu3.dts arch/arm/boot/dts/exynos4412-odroidu3noplus.dts
cp arch/arm/boot/dts/exynos4412-odroid-common.dtsi arch/arm/boot/dts/exynos4412-odroid-common-u3noplus.dtsi
patch -p1 < /compile/doc/stable/misc.exy/patches/reboot-fix-u3noplus-v6.0.patch

# add mali support # initially left out - to include in later builds, if stable
# to verify paths
#patch -N -p1 < /compile/doc/stable/misc.exy/patches/exynos4412-mali-complete.patch
#cp -rv         /compile/doc/stable/misc.exy/patches/exynos4412-mali-complete/drivers/gpu/arm drivers/gpu
##patch -N -p1 < /compile/doc/stable/misc.exy/patches/devfreq-turbo-for-mali-gpu-driver-v5.9.patch
#patch -N -p1 < /compile/doc/stable/misc.exy/patches/export-cma-symbols.patch
##patch -N -p1 < /compile/doc/stable/misc.exy/dts-add-gpu-node-for-exynos4412.patch
##patch -N -p1 < /compile/doc/stable/misc.exy/dts-add-gpu-opp-table.patch
##patch -N -p1 < /compile/doc/stable/misc.exy/dts-setup-gpu-node.patch
##patch -N -p1 < /compile/doc/stable/misc.exy/dts-exynos-remove-new-gpu-node-v5.3.patch

scripts/kconfig/merge_config.sh -m arch/arm/configs/exynos_defconfig /compile/doc/kernel-config-options/docker-options.cfg /compile/doc/kernel-config-options/options-to-remove-generic.cfg /compile/doc/stable/misc.exy/options/options-to-remove-special.cfg /compile/doc/kernel-config-options/additional-options-generic.cfg /compile/doc/kernel-config-options/additional-options-armv7l.cfg /compile/doc/stable/misc.exy/options/additional-options-special.cfg
( cd /compile/doc/kernel-config-options ; git rev-parse --verify HEAD ) > /compile/doc/stable/misc.exy/options/kernel-config-options.version
make olddefconfig
make -j 4 zImage dtbs modules
cd tools/perf
make
cd ../power/cpupower
make
cd ../../..
export kver=`make kernelrelease`
echo ${kver}
# remove debug info if there and not wanted
# find . -type f -name '*.ko' | sudo xargs -n 1 objcopy --strip-unneeded

make modules_install
mkdir -p /lib/modules/${kver}/tools
cp -v tools/perf/perf /lib/modules/${kver}/tools
cp -v tools/power/cpupower/cpupower /lib/modules/${kver}/tools
cp -v tools/power/cpupower/libcpupower.so.0.0.1 /lib/modules/${kver}/tools/libcpupower.so.0

make headers_install INSTALL_HDR_PATH=/usr

cp -v .config /boot/config-${kver}
cp -v arch/arm/boot/zImage /boot/zImage-${kver}
mkdir -p /boot/dtb-${kver}
cp -v arch/arm/boot/dts/exynos4412-odroidu3.dtb /boot/dtb-${kver}
cp -v arch/arm/boot/dts/exynos4412-odroidu3noplus.dtb /boot/dtb-${kver}

cp -v System.map /boot/System.map-${kver}
cd /boot
update-initramfs -c -k ${kver}

mkimage -A arm -O linux -T ramdisk -a 0x0 -e 0x0 -n initrd.img-${kver} -d initrd.img-${kver} uInitrd-${kver}

tar cvzf /compile/source/linux-stable-exy/${kver}.tar.gz /boot/*-${kver} /lib/modules/${kver}
cp -v /compile/doc/stable/config.exy /compile/doc/stable/config.exy.old
cp -v /compile/source/linux-stable-exy/.config /compile/doc/stable/config.exy
cp -v /compile/source/linux-stable-exy/.config /compile/doc/stable/config.exy-${kver}
cp -v /compile/source/linux-stable-exy/*.tar.gz /compile/result/stable


##########################################################
#  Build odroid-u3 IMAGE using @hexdump0815 imagebuilder #
##########################################################

/scripts/extend-rootfs.sh
/scripts/recreate-swapfile.sh 2G
/scripts/install-buildtools.sh


git clone https://github.com/hexdump0815/imagebuilder /compile/local/imagebuilder
cd /compile/local/imagebuilder

./scripts/prepare.sh

cd /compile/local/
btrfs subvolume create /compile/local/imagebuilder-diskimage
chattr -R +C /compile/local/imagebuilder-diskimage
btrfs property set /compile/local/imagebuilder-diskimage compression none

./scripts/get-files.sh $SYSTEM_TYPE $SYSTEM_ARCH $DISTRO

mv /compile/result/stable/${kver}

./scripts/create-fs.sh $SYSTEM_TYPE $SYSTEM_ARCH $DISTRO

./scripts/create-image.sh $SYSTEM_TYPE $SYSTEM_ARCH $DISTRO
