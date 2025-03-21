#!/bin/zsh
# Simple chrooter for stuff

# Define mountpoint
MOUNT_DIR=/tmp/mount

# Detect holo partitions
ROOTPART=$(sudo blkid | grep holo-root | cut -d ':' -f 1 | head -n 1)
if [ -n "${ROOTPART}" ]; then
	echo "HoloISO Installation found"
else
    echo "HoloISO Installation wasn't found on this device"
    echo "Exiting..."
    sleep 5
    exit 1
fi
HOMEPART=$(sudo blkid | grep holo-home | cut -d ':' -f 1 | head -n 1)
EFIPART=$(sudo blkid | grep HOLOEFI | cut -d ':' -f 1 | head -n 1)

# Re-mount stuff before proceeding
CHK_MNT=$(lsblk | grep -e ${MOUNT_DIR} -e /mnt)
if [ -n "${CHK_MNT}" ]; then
	sudo umount -l ${ROOTPART} 2>&1
fi

# Create an mountpoint
sudo mkdir -p ${MOUNT_DIR}

# Inform user about partition location
echo "Your HoloISO EFI Partition is located in ${EFIPART} partition."
echo "Your HoloISO Root Partition is located in ${ROOTPART} partition."
echo "Your HoloISO Home Partition is located in ${HOMEPART} partition."

# Mount partitions
sudo mount ${ROOTPART} ${MOUNT_DIR}
sudo mount ${HOMEPART} ${MOUNT_DIR}/home
sudo mount ${EFIPART} ${MOUNT_DIR}/boot/efi

# Check for version
echo "Your HoloISO Installation version: $(cat ${MOUNT_DIR}/etc/os-release | grep VARIANT_ID | cut -d '"' -f 2)\n"

# Chroot!
sudo arch-chroot ${MOUNT_DIR}