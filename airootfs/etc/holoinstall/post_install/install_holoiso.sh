#!/bin/zsh
# HoloISO Installer v2
# This defines all of the current variables.
HOLO_INSTALL_DIR="${HOLO_INSTALL_DIR:-/mnt}"
IS_WIN600=$(cat /sys/devices/virtual/dmi/id/product_name | grep Win600)
IS_STEAMDECK=$(cat /sys/devices/virtual/dmi/id/product_name | grep Jupiter)

if [ -n "${IS_WIN600}" ]; then
	GAMEPAD_DRV="1"
fi

if [ -n "${IS_STEAMDECK}" ]; then
	FIRMWARE_INSTALL="1"
fi

check_mount(){
	if [ $1 != 0 ]; then
		echo "\nError: Something went wrong when mounting $2 partitions. Please try again!\n"
		echo 'Press any key to exit...'; read -k1 -s
		exit 1
	fi
}

check_download(){
	if [ $1 != 0 ]; then
		echo "\nError: Something went wrong when $2.\nPlease make sure you have a stable internet connection!\n"
		echo 'Press any key to exit...'; read -k1 -s
		exit 1
	fi
}

partitioning(){
	echo "Select your drive in popup:"

	DRIVEDEVICE=$(lsblk -d -o NAME | sed "1d" | awk '{ printf "FALSE""\0"$0"\0" }' | \
xargs -0 zenity --list --width=600 --height=512 --title="Select disk" --text="Select your disk to install HoloISO in below:\n\n $(lsblk -d -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,VENDOR,MODEL,SERIAL,MOUNTPOINT)" \
--radiolist --multiple --column ' ' --column 'Disks')
	
	DEVICE="/dev/${DRIVEDEVICE}"
	
	INSTALLDEVICE="${DEVICE}"

	if [ ! -b $DEVICE ]; then
		echo "$DEVICE not found! Installation Aborted!"
		exit 1
	fi
	lsblk $DEVICE | head -n2 | tail -n1 | grep disk > /dev/null 2>&1
	if [ $? != 0 ]; then
		echo "$DEVICE is not disk type! Installation Aborted!"
		echo "\nNote: If you wish to preform partition install.\nPlease specify the disk drive node first then select \"2\" for partition install."
		exit 1
	fi
	echo "\nChoose your partitioning type:"
	install=$(zenity --list --title="Choose your installation type:" --column="Type" --column="Name" 1 "Erase entire drive" \2 "Install alongside existing OS/Partition (Requires at least 50 GB of free space from the end)"  --width=700 --height=220)

	case $install in
		1)
			destructive=true
			# Umount twice to fully umount the broken install of steam os 3 before installing.
			umount $INSTALLDEVICE* > /dev/null 2>&1
			umount $INSTALLDEVICE* > /dev/null 2>&1
			$INST_MSG1
			if zenity --question --text "WARNING: The following drive is going to be fully erased. ALL DATA ON DRIVE ${DEVICE} WILL BE LOST! \n\n$(lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,VENDOR,MODEL,SERIAL,MOUNTPOINT ${DEVICE} | sed "1d")\n\nErase ${DEVICE} and begin installation?" --width=700
			then
				echo "\nWiping partitions..."
				sfdisk --delete ${DEVICE}
				wipefs -a ${DEVICE}
				echo "\nCreating new gpt partitions..."
				parted ${DEVICE} mklabel gpt
			else
				echo "\nNothing has been written.\nYou canceled the destructive install, please try again"
				echo 'Press any key to exit...'; read -k1 -s
				exit 1
			fi
			;;
		2)
			echo "\nHoloISO will be installed alongside existing OS/Partition.\nPlease make sure there are more than 24 GB on the >>END<< of free(unallocate) space available\n"
			parted $DEVICE print free
			echo "HoloISO will be installed on the following free (unallocated) space.\n"
			parted $DEVICE print free | tail -n2 | grep "Free Space"
			if [ $? != 0 ]; then
				echo "Error! No Free Space found on the end of the disk.\nNothing has been written.\nYou canceled the non-destructive install, please try again"
				exit 1
				echo 'Press any key to exit...'; read -k1 -s
			fi
				$INST_MSG1
			if zenity --question --text "HoloISO will be installed on the following free (unallocated) space.\nDoes this look reasonable?\n$(sudo parted ${DEVICE} print free | tail -n2 | grep "Free Space")" --width=500
			then
        		echo "\nBeginning installation..."
			else
				echo "\nNothing has been written.\nYou canceled the non-destructive install, please try again"
				echo 'Press any key to exit...'; read -k1 -s
				exit 1
        		fi
			;;
		esac

	numPartitions=$(grep -c ${DRIVEDEVICE}'[0-9]' /proc/partitions)
	
	echo ${DEVICE} | grep -q -P "^/dev/(nvme|loop|mmcblk)"
	if [ $? -eq 0 ]; then
		INSTALLDEVICE="${DEVICE}p"
		numPartitions=$(grep -c ${DRIVEDEVICE}p /proc/partitions)
	fi

	efiPartNum=$(expr $numPartitions + 1)
	rootPartNum=$(expr $numPartitions + 2)
	homePartNum=$(expr $numPartitions + 3)

	echo "\nCalculating start and end of free space..."
	diskSpace=$(awk '/'${DRIVEDEVICE}'/ {print $3; exit}' /proc/partitions)
	# <= 60GB: typical flash drive
	if [ $diskSpace -lt 60000000 ]; then
		digitMB=8
		realDiskSpace=$(parted ${DEVICE} unit MB print free|head -n2|tail -n1|cut -c 16-20)
	# <= 500GB: typical 512GB hard drive
	elif [ $diskSpace -lt 500000000 ]; then
		digitMB=8
		realDiskSpace=$(parted ${DEVICE} unit MB print free|head -n2|tail -n1|cut -c 20-25)
	# anything else: typical 1024GB hard drive
	else
		digitMB=9
		realDiskSpace=$(parted ${DEVICE} unit MB print free|head -n2|tail -n1|cut -c 20-26)
	fi

	if [ $destructive ]; then
		efiStart=2
	else
		efiStart=$(parted ${DEVICE} unit MB print free|tail -n2|sed s/'        '//|cut -c1-$digitMB|sed s/MB//|sed s/' '//g)
	fi
	efiEnd=$(expr $efiStart + 256)
	rootStart=$efiEnd
	rootEnd=$(expr $rootStart + 24000)

	if [ $efiEnd -gt $realDiskSpace ]; then
		echo "Not enough space available, please choose another disk and try again"
		exit 1
		echo 'Press any key to exit...'; read -k1 -s
	fi

	echo "\nCreating partitions..."
	parted ${DEVICE} mkpart primary fat32 ${efiStart}M ${efiEnd}M
	parted ${DEVICE} set ${efiPartNum} boot on
	parted ${DEVICE} set ${efiPartNum} esp on
	# If the available storage is less than 64GB, don't create /home.
	# If the boot device is mmcblk0, don't create an ext4 partition or it will break steamOS versions
	# released after May 20.
	if [ $diskSpace -lt 64000000 ] || [[ "${DEVICE}" =~ mmcblk0 ]]; then
		parted ${DEVICE} mkpart primary btrfs ${rootStart}M 100%
	else
		parted ${DEVICE} mkpart primary btrfs ${rootStart}M ${rootEnd}M
		parted ${DEVICE} mkpart primary ext4 ${rootEnd}M 100%
		home=true
	fi
	root_partition="${INSTALLDEVICE}${rootPartNum}"
	mkfs -t vfat ${INSTALLDEVICE}${efiPartNum}
	efi_partition="${INSTALLDEVICE}${efiPartNum}"
	fatlabel ${INSTALLDEVICE}${efiPartNum} HOLOEFI
	mkfs -t btrfs -f ${root_partition}
	btrfs filesystem label ${root_partition} holo-root
	if [ $home ]; then
		if [[ -n "$(sudo blkid | grep holo-home | cut -d ':' -f 1 | head -n 1)" ]]; then
			HOME_REUSE_TYPE=$(zenity --list --title="Warning" --text="A HoloISO home partition was detected at $(sudo blkid | grep holo-home | cut -d ':' -f 1 | head -n 1). Please select an appropriate action below:" --column="Type" --column="Name" 1 "Format it and start over" \2 "Reuse partition"  --width=500 --height=220)
				if [[ "${HOME_REUSE_TYPE}" == "1" ]]; then
					mkfs -t ext4 -F -O casefold ${INSTALLDEVICE}${homePartNum}
					home_partition="${INSTALLDEVICE}${homePartNum}"
					e2label "${INSTALLDEVICE}${homePartNum}" holo-home
				elif [[ "${HOME_REUSE_TYPE}" == "2" ]]; then
					echo "Home partition will be reused at $(sudo blkid | grep holo-home | cut -d ':' -f 1 | head -n 1)"
                    home_partition="${INSTALLDEVICE}${homePartNum}"
				fi
		else
			mkfs -t ext4 -O casefold ${INSTALLDEVICE}${homePartNum}
			home_partition="${INSTALLDEVICE}${homePartNum}"
			e2label "${INSTALLDEVICE}${homePartNum}" holo-home
		fi
	fi
	echo "\nPartitioning complete, mounting and installing."
}

base_os_install() {
	# Added failsafe check to prevent dualboot being fucked
	#OSROOT=/dev/disk/by-label/holo-root
	#OSHOME=/dev/disk/by-label/holo-home
	#if [[ -f "$OSROOT" ]]; then
    #	echo "It appears that HoloISO installation was found on your device"
	#	read "?Do you want to format your installation or start over? (yN) " OSROOT_REDO
	#	if [[ "${OSROOT_REDO}" == "y" ]] || [[ "${OSROOT_REDO}" == "Y" ]]; then
	#		mkfs -t vfat /dev/disk/by-label/HOLOEFI
	#		mkfs -t btrfs -f /dev/disk/by-label/holo-root
	#		if [[ -f "$OSHOME" ]]; then
	#			echo "Installation with home detected... Formatting..."
	#			mkfs -t ext4 -O casefold /dev/disk/by-label/holo-home
	#			home_partition="/dev/disk/by-label/holo-home"
	#		else
	#			echo "Home partition not required... Skipping..."
	#		fi
	#		root_partition="/dev/disk/by-label/holo-root"
	#		efi_partition="/dev/disk/by-label/HOLOEFI"
	#	elif [[ "${OSROOT_REDO}" == "n" ]] || [[ "${OSROOT_REDO}" == "N" ]]; then
	#		partitioning
	#	fi
	#else
	sleep 1
	clear
	partitioning
	#fi
	# Actual installer below:
	echo "${UCODE_INSTALL_MSG}"
	sleep 1
	clear
	mount -t btrfs -o subvol=/,compress-force=zstd:1,discard,noatime,nodiratime ${root_partition} ${HOLO_INSTALL_DIR} 
	check_mount $? root
	${CMD_MOUNT_BOOT}
	check_mount $? boot
	if [ $home ]; then
        mkdir -p ${HOLO_INSTALL_DIR}/home
		mount -t ext4 ${home_partition} ${HOLO_INSTALL_DIR}/home
		check_mount $? home
	fi
    rsync -axHAWXS --numeric-ids --info=progress2 --no-inc-recursive / ${HOLO_INSTALL_DIR} |    tr '\r' '\n' |    awk '/^ / { print int(+$2) ; next } $0 { print "# " $0 }' | zenity --progress --title="Installing base OS..." --text="Bootstrapping root filesystem...\nThis may take more than 10 minutes.\n" --width=500 --no-cancel --auto-close
	arch-chroot ${HOLO_INSTALL_DIR} install -Dm644 "$(find /usr/lib | grep vmlinuz | grep neptune)" "/boot/vmlinuz-$(cat /usr/lib/modules/*neptune*/pkgbase)"
	cp -r /etc/holoinstall/post_install/pacman.conf ${HOLO_INSTALL_DIR}/etc/pacman.conf
	arch-chroot ${HOLO_INSTALL_DIR} pacman-key --init
    arch-chroot ${HOLO_INSTALL_DIR} pacman -Rdd --noconfirm mkinitcpio-archiso
	arch-chroot ${HOLO_INSTALL_DIR} mkinitcpio -P
    arch-chroot ${HOLO_INSTALL_DIR} pacman -U --noconfirm $(find /etc/holoinstall/post_install/pkgs | grep pkg.tar.zst)
	arch-chroot ${HOLO_INSTALL_DIR} userdel -r liveuser
	check_download $? "installing base package"
	sleep 2
	clear
	
	sleep 1
	clear
	echo "\nBase system installation done, generating fstab..."
	genfstab -U -p /mnt >> /mnt/etc/fstab
	sleep 1
	clear

    echo "Configuring first boot user accounts..."
	rm ${HOLO_INSTALL_DIR}/etc/skel/Desktop/*
    arch-chroot ${HOLO_INSTALL_DIR} rm /etc/sddm.conf.d/* 
	mv /etc/holoinstall/post_install_shortcuts/steam.desktop /etc/holoinstall/post_install_shortcuts/desktopshortcuts.desktop ${HOLO_INSTALL_DIR}/etc/xdg/autostart
    mv /etc/holoinstall/post_install_shortcuts/steamos-gamemode.desktop ${HOLO_INSTALL_DIR}/etc/skel/Desktop

	# Setup password for root
	while true; do
		ROOTPASS=$(zenity --forms --title="Account configuration" --text="Set root/system administrator password" --add-password="Password for user root")
		if [ -z $ROOTPASS ]; then
			zenity --warning --text "No password was set for user \"root\"!" --width=300
			break
		fi
		echo
		ROOTPASS_CONF=$(zenity --forms --title="Account configuration" --text="Confirm your root password" --add-password="Password for user root")
		echo
		if [ $ROOTPASS = $ROOTPASS_CONF ]; then
			break
		fi
		zenity --warning --text "Passwords not match." --width=300
	done
	# Create user
	NAME_REGEX="^[a-z][-a-z0-9_]*\$"
	while true; do
		HOLOUSER=$(zenity --entry --title="Account creation" --text "Enter username for this installation:")
		if [ $HOLOUSER = "root" ]; then
			zenity --warning --text "User root already exists." --width=300
		elif [ -z $HOLOUSER ]; then
			zenity --warning --text "Please create a user!" --width=300
		elif [ ${#HOLOUSER} -gt 32 ]; then
			zenity --warning --text "Username length must not exceed 32 characters!" --width=400
		elif [[ ! $HOLOUSER =~ $NAME_REGEX ]]; then
			zenity --warning --text "Invalid username \"$HOLOUSER\"\nUsername needs to follow these rules:\n\n- Must start with a lowercase letter.\n- May only contain lowercase letters, digits, hyphens, and underscores." --width=500
		else
			break
		fi
	done
	# Setup password for user
	while true; do
		HOLOPASS=$(zenity --forms --title="Account configuration" --text="Set password for $HOLOUSER" --add-password="Password for user $HOLOUSER")
		echo
		HOLOPASS_CONF=$(zenity --forms --title="Account configuration" --text="Confirm password for $HOLOUSER" --add-password="Password for user $HOLOUSER")
		echo
		if [ -z $HOLOPASS ]; then
			zenity --warning --text "Please type password for user \"$HOLOUSER\"!" --width=300
			HOLOPASS_CONF=unmatched
		fi
		if [ $HOLOPASS = $HOLOPASS_CONF ]; then
			break
		fi
		zenity --warning --text "Passwords do not match." --width=300
	done
	
	echo "\nCreating user ${HOLOUSER}..."
	echo -e "${ROOTPASS}\n${ROOTPASS}" | arch-chroot ${HOLO_INSTALL_DIR} passwd root
	arch-chroot ${HOLO_INSTALL_DIR} useradd --create-home ${HOLOUSER}
	echo -e "${HOLOPASS}\n${HOLOPASS}" | arch-chroot ${HOLO_INSTALL_DIR} passwd ${HOLOUSER}
	echo "${HOLOUSER} ALL=(root) NOPASSWD:ALL" > ${HOLO_INSTALL_DIR}/etc/sudoers.d/${HOLOUSER}
	chmod 0440 ${HOLO_INSTALL_DIR}/etc/sudoers.d/${HOLOUSER}
	echo "127.0.1.1    ${HOLOHOSTNAME}" >> ${HOLO_INSTALL_DIR}/etc/hosts
	sleep 1
	clear

	echo "\nInstalling bootloader..."
	mkdir -p ${HOLO_INSTALL_DIR}/boot/efi
	mount -t vfat ${efi_partition} ${HOLO_INSTALL_DIR}/boot/efi
	arch-chroot ${HOLO_INSTALL_DIR} holoiso-grub-update
	sleep 1
	clear
}
full_install() {
	if [[ "${GAMEPAD_DRV}" == "1" ]]; then
		echo "You're running this on Anbernic Win600. A suitable gamepad driver will be installed."
		arch-chroot ${HOLO_INSTALL_DIR} pacman -U --noconfirm $(find /etc/holoinstall/post_install/pkgs_addon | grep win600-xpad-dkms)
	fi
	if [[ "${FIRMWARE_INSTALL}" == "1" ]]; then
		echo "You're running this on a Steam Deck. linux-firmware-neptune will be installed to ensure maximum kernel-side compatibility."
		arch-chroot ${HOLO_INSTALL_DIR} pacman -Rdd --noconfirm linux-firmware
		arch-chroot ${HOLO_INSTALL_DIR} pacman -U --noconfirm $(find /etc/holoinstall/post_install/pkgs_addon | grep linux-firmware-neptune)
		arch-chroot ${HOLO_INSTALL_DIR} mkinitcpio -P
	fi
	echo "\nConfiguring Steam Deck UI by default..."		
    ln -s /usr/share/applications/steam.desktop ${HOLO_INSTALL_DIR}/etc/skel/Desktop/steam.desktop
	echo -e "[General]\nDisplayServer=wayland\n\n[Autologin]\nUser=${HOLOUSER}\nSession=gamescope-wayland.desktop\nRelogin=true\n\n[X11]\n# Janky workaround for wayland sessions not stopping in sddm, kills\n# all active sddm-helper sessions on teardown\nDisplayStopCommand=/usr/bin/gamescope-wayland-teardown-workaround" >> ${HOLO_INSTALL_DIR}/etc/sddm.conf.d/autologin.conf
	arch-chroot ${HOLO_INSTALL_DIR} usermod -a -G rfkill ${HOLOUSER}
	arch-chroot ${HOLO_INSTALL_DIR} usermod -a -G wheel ${HOLOUSER}
	echo "Preparing Steam OOBE..."
	arch-chroot ${HOLO_INSTALL_DIR} sudo -u ${HOLOUSER} steam
	echo "Cleaning up..."
	cp /etc/skel/.bashrc ${HOLO_INSTALL_DIR}/home/${HOLOUSER}
    arch-chroot ${HOLO_INSTALL_DIR} rm -rf /etc/holoinstall
	sleep 1
	clear
}


# The installer itself. Good wuck.
echo "SteamOS 3 Installer"
echo "Start time: $(date)"
echo "Please choose installation type:"
HOLO_INSTALL_TYPE=$(zenity --list --title="Choose your installation type:" --column="Type" --column="Name" 1 "Install HoloISO, version $(cat /etc/os-release | grep VARIANT_ID | cut -d "=" -f 2 | sed 's/"//g') " \2 "Exit installer"  --width=700 --height=220)
if [[ "${HOLO_INSTALL_TYPE}" == "1" ]] || [[ "${HOLO_INSTALL_TYPE}" == "barebones" ]]; then
	echo "Installing SteamOS, barebones configuration..."
	base_os_install
	full_install
	zenity --warning --text="Installation finished! You may reboot now, or type arch-chroot /mnt to make further changes" --width=700 --height=50
else
	zenity --warning --text="Exiting installer..." --width=120 --height=50
fi

echo "End time: $(date)"
