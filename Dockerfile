FROM ubuntu:20.04 AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG CONFIG_DIR=./config
ARG CFGUSERNAME=rv
ARG CFGUSERHASH=$1$rv$sPaQWGxF5oB7q./00FQcn0

RUN apt update

RUN apt install -y autoconf \
	automake \
	autotools-dev \
	curl \
	cpio \
	debootstrap \
	kmod \
	python3 \
	libmpc-dev \
	libmpfr-dev \
	libgmp-dev \
	gawk \
	build-essential \
	bison \
	flex \
	git \
	texinfo \
	gperf \
	libtool \
	patchutils \
	python3-pkg-resources \
	bc \
	zlib1g-dev \
	libexpat-dev \
	swig \
	libssl-dev \
	python3-distutils \
	python3-dev \
	wget

RUN wget http://ftp.us.debian.org/debian/pool/main/d/debian-ports-archive-keyring/debian-ports-archive-keyring_2022.02.15_all.deb
RUN apt install -y ./debian-ports-archive-keyring_2022.02.15_all.deb

FROM base AS build-toolchain

RUN mkdir /build
WORKDIR /build
ENV cwd=/build

RUN git clone --recursive https://github.com/riscv/riscv-gnu-toolchain
WORKDIR riscv-gnu-toolchain
RUN git checkout 63f696c8f23f3eebf5f1af97fd8c66f6483a6393
RUN ./configure --prefix=${cwd}/riscv64-unknown-linux-gnu --with-arch=rv64gc --with-abi=lp64d
RUN make linux -j `nproc`
ENV PATH=${cwd}/riscv64-unknown-linux-gnu/bin:$PATH
WORKDIR /build

FROM build-toolchain AS build-boot0

RUN git clone https://github.com/smaeul/sun20i_d1_spl
WORKDIR sun20i_d1_spl
#RUN git checkout 0ad88bfdb723b1ac74cca96122918f885a4781ac
RUN make CROSS_COMPILE=${cwd}/riscv64-unknown-linux-gnu/bin/riscv64-unknown-linux-gnu- p=sun20iw1p1 mmc
WORKDIR /build

FROM build-boot0 AS build-opensbi

RUN git clone https://github.com/smaeul/opensbi
WORKDIR opensbi
#RUN git checkout d78eef34dfb1c08f0790b549344f977aecaa021e
RUN make CROSS_COMPILE=${cwd}/riscv64-unknown-linux-gnu/bin/riscv64-unknown-linux-gnu- PLATFORM=generic FW_PIC=y FW_OPTIONS=0x2

FROM build-opensbi AS build-u-boot

WORKDIR /build
RUN git clone https://github.com/smaeul/u-boot.git
WORKDIR u-boot
#RUN git checkout ac8ca120a5a8b98aad319c12f259c93f004395c9
RUN git checkout d1-wip
RUN make CROSS_COMPILE=${cwd}/riscv64-unknown-linux-gnu/bin/riscv64-unknown-linux-gnu- nezha_defconfig
RUN make -j `nproc` ARCH=riscv CROSS_COMPILE=${cwd}/riscv64-unknown-linux-gnu/bin/riscv64-unknown-linux-gnu- all V=1
WORKDIR /build
COPY config/toc1.cfg /build
RUN ./u-boot/tools/mkimage -T sunxi_toc1 -d toc1.cfg u-boot.toc1

FROM build-u-boot AS build-kernel

RUN git clone https://github.com/smaeul/linux
WORKDIR /build
RUN mkdir -p linux-build/arch/riscv/configs
COPY config/licheerv_linux_defconfig .
RUN cp licheerv_linux_defconfig linux-build/arch/riscv/configs/licheerv_defconfig
WORKDIR linux
RUN git checkout 06b026a8b7148f18356c5f809e51f013c2494587

WORKDIR /build
RUN yes '' | make ARCH=riscv -C linux O=${cwd}/linux-build licheerv_defconfig
RUN yes '' | make -j `nproc` -C linux-build ARCH=riscv CROSS_COMPILE=${cwd}/riscv64-unknown-linux-gnu/bin/riscv64-unknown-linux-gnu- V=1

FROM build-kernel AS build-rtl8723ds
RUN git clone https://github.com/lwfinger/rtl8723ds.git
WORKDIR rtl8723ds
RUN make -j `nproc` ARCH=riscv CROSS_COMPILE=${cwd}/riscv64-unknown-linux-gnu/bin/riscv64-unknown-linux-gnu- KSRC=${cwd}/linux-build modules
WORKDIR /build

FROM build-rtl8723ds AS create-rootfs

RUN debootstrap --arch=riscv64 --keyring /usr/share/keyrings/debian-ports-archive-keyring.gpg --components main,contrib,non-free --include=debian-ports-archive-keyring,pciutils,autoconf,automake,autotools-dev,curl,python3,libmpc-dev,libmpfr-dev,libgmp-dev,gawk,build-essential,bison,flex,texinfo,gperf,libtool,patchutils,bc,zlib1g-dev,wpasupplicant,htop,net-tools,wireless-tools,firmware-realtek,ntpdate,openssh-client,openssh-server,sudo,e2fsprogs,git,man-db,lshw,dbus,wireless-regdb,libsensors5,lm-sensors,swig,libssl-dev,python3-distutils,python3-dev,alien,fakeroot,dkms,libblkid-dev,uuid-dev,libudev-dev,libaio-dev,libattr1-dev,libelf-dev,python3-setuptools,python3-cffi,python3-packaging,libffi-dev,libcurl4-openssl-dev,python3-ply,iotop unstable rootfs http://deb.debian.org/debian-ports || true

FROM create-rootfs AS install-kmods

WORKDIR linux-build
RUN make modules_install ARCH=riscv INSTALL_MOD_PATH=../rootfs KERNELRELEASE=5.17.0-rc2-379425-g06b026a8b714
WORKDIR /build
RUN install -D -p -m 644 rtl8723ds/8723ds.ko rootfs/lib/modules/5.17.0-rc2-379425-g06b026a8b714/kernel/drivers/net/wireless/8723ds.ko
RUN rm rootfs/lib/modules/5.17.0-rc2-379425-g06b026a8b714/build
RUN rm rootfs/lib/modules/5.17.0-rc2-379425-g06b026a8b714/source
RUN depmod -a -b rootfs 5.17.0-rc2-379425-g06b026a8b714
RUN sh -c 'echo "8723ds" >> rootfs/etc/modules'

FROM install-kmods AS config

WORKDIR /build
RUN echo "root:$(openssl passwd -1 -salt root rootpwd):..." > rootfs/etc/shadow
COPY config/fstab rootfs/etc/fstab
COPY config/wpa_supplicant.conf rootfs/etc/wpa_supplicant/wpa_supplicant.conf
COPY config/interfaces rootfs/etc/network/interfaces
RUN mkdir -p rootfs/var/spool/cron/crontabs/
RUN sh -c 'echo "@reboot for i in 1 2 3 4 5; do /usr/sbin/ntpdate 0.europe.pool.ntp.org && break || sleep 15; done" >> rootfs/var/spool/cron/crontabs/root'
RUN chmod 600 rootfs/var/spool/cron/crontabs/root

FROM config AS add-user

WORKDIR /build
RUN useradd -R /build/rootfs -s /bin/bash USERNAME
RUN mkdir -p rootfs/home/$USERNAME
RUN chown 1000:1000 rootfs/home/$USERNAME
RUN sed -i '/$USERNAME:!:.../c\$USERNAME:$USERHASH:...' rootfs/etc/shadow
RUN cp rootfs/etc/skel/.bash* rootfs/home/$USERNAME/
RUN cp rootfs/etc/skel/.profile rootfs/home/$USERNAME/
RUN echo "sudo:x:27:$USERNAME" >> rootfs/etc/group

FROM add-user AS boot-script

WORKDIR /build
COPY config/u-boot-bootscr.txt .
RUN u-boot/tools/mkimage -T script -O linux -d u-boot-bootscr.txt boot.scr

FROM boot-script AS output

WORKDIR /build
RUN mkdir /output
RUN cp sun20i_d1_spl/nboot/boot0_sdcard_sun20iw1p1.bin /output/
RUN cp linux-build/arch/riscv/boot/Image.gz /output/
RUN tar -cJvf /output/rootfs.tar.xz rootfs

