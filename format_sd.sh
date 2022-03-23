#!/bin/bash

DISK=sdh

if [ -z "$1" ]
then
	echo "You need to specify what disk to modify! (ex. sda, sdb, etc.)"
	exit 1
fi

DEVICE=/dev/$1

OUTPUT=output
ROOTFS=licheerv-debian-rootfs.tar.xz

BOOTBIN=$OUTPUT/boot0_sdcard_sun20iw1p1.bin
UBOOT=$OUTPUT/u-boot.toc1

if [ -z ${DRY_RUN+x} ]
then
	echo "WARNING! DRY RUN DISABLED!"
else
	echo "DRY RUN ENABLED"
fi

echo
echo "We're about to make permanent changes to $DEVICE!"
read -p "Are you sure you want to continue? (y/n): " -n 1 -r
echo # move to new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
	exit 1
fi

exit 1

if [ -z ${DRY_RUN+x} ]
then
	dd if=/dev/zero of=$DEVICE bs=1M count=200
	parted -s -a optimal -- $DEVICE mklabel gpt
	parted -s -a optimal -- $DEVICE mkpart primary ext2 40MiB 100MiB
	parted -s -a optimal -- $DEVICE mkpart primary ext4 100MiB -1GiB
	parted -s -a optimal -- $DEVICE mkpart primary linux-swap -1GiB 100%
fi

if [ -z ${DRY_RUN+x} ]
then
	mkfs.ext2 ${DEVICE}1
	mkfs.ext4 ${DEVICE}2
	mkswap ${DEVICE}3

	dd if=$BOOTBIN of=$DEVICE bs=8192 seek=16
	dd if=$UBOOT of=$DEVICE bs=512 seek=32800
fi


mkdir -p /mnt/sdcard_boot
mkdir -p /mnt/sdcard_rootfs

if [ -z ${DRY_RUN+x} ]
then
	mount ${DEVICE}1 /mnt/sdcard_boot
	cp $OUTPUT/Image.gz /mnt/sdcard_boot
	cp $OUTPUT/boot.scr /mnt/sdcard_boot
	umount /mnt/sdcard_boot
fi

if [ -z ${DRY_RUN+x} ]
then
	mount ${DEVICE}2 /mnt/sdcard_rootfs
	tar xfJ $OUTPUT/$ROOTFS -C /mnt/sdcard_rootfs
	umount /mnt/sdcard_rootfs
fi

rm -rf /mnt/sdcard_boot
rm -rf /mnt/sdcard_rootfs

