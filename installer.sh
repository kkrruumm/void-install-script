#!/bin/bash -e
user=$(whoami)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ $user != root ]; then
    echo -e "${RED}Please execute this script as root.${NC}"
    exit 1
fi

# Check to see if there is a flag when executing installer.sh and make sure it's a .sh file to be imported as an installation config
if [ $# != 1 ]; then
    echo "Continuing without config file..."
    configDetected=0
elif [ $# == 1 ]; then
    echo "Attempting to use user-defined config file..."

    # Should be performing a much more exhaustive check on the config file before accepting it, WIP
    if [[ $1 == *.sh ]] ; then
        if grep 'diskInput' $1 ; then
            source $1
            configDetected=1
        fi
    else
        echo -e "${RED}User-defined config detected but is either misinput or the wrong file type.${NC}\n"
        echo -e "Please correct this error and run again. \n"
        exit 1
    fi
fi

entry() {

    configExported=0
    runDirectory=$(pwd)
    sysArch=$(uname -m)
    locale="LANG=en_US.UTF-8"
    libclocale="en_US.UTF-8 UTF-8"

    # This script will only work on UEFI systems.
    if test -e "/sys/firmware/efi" ; then
        echo -e "This system is UEFI. Continuing... \n"
    else
        commandFailure="This script only supports UEFI systems, but it appears we have booted as BIOS."
        failureCheck
    fi

    # Autodetection for glibc/musl
    if ldd --version | grep GNU ; then
        muslSelection="glibc"
    else
        muslSelection="musl"
    fi

    if [ $sysArch != "x86_64" ]; then
        commandFailure="This systems CPU architecture is not currently supported by this install script."
        failureCheck
    fi

    if test -e "$runDirectory/systemchroot.sh" ; then
        echo -e "Secondary script found. Continuing... \n"
    else
        commandFailure="Secondary script appears to be missing. This could be because it is incorrectly named, or simply does not exist."
        failureCheck
    fi

    clear

    echo -e "Testing network connectivity... \n"

    if ping -c 1 gnu.org &>/dev/null || ping -c 1 fsf.org &>/dev/null ; then
        echo -e "Network check succeeded. \n"
    else
        commandFailure="Network check failed. Please make sure your network is active."
        failureCheck
    fi

    clear

    echo -e "Begin void installer... \n"

    echo -e "Grabbing installer dependencies... \n"
    commandFailure="Dependency installation has failed."
    xbps-install -Sy bc fzf parted void-repo-nonfree || failureCheck
   
    if [ $configDetected == "1" ]; then
        confirmInstallationOptions
    else
        diskConfiguration
    fi

}

diskConfiguration() {

    # We're going to define all disk options and use them later on so the user can verify the layout and return to entry to start over if something isn't correct, before touching the disks.
    clear
    echo -e "AVAILABLE DISKS: \n"
    lsblk -o NAME,SIZE,TYPE -e7
    echo -e "The disk you choose will not be modified until you confirm your installation options. \n"
    echo -e "Please choose the disk you would like to partition and install Void Linux to: \n"
    diskPrompt=$(lsblk -d -o NAME -n -e7 | fzf --height 10%)

    diskInput="/dev/$diskPrompt"

    clear

    diskSize=$(lsblk --output SIZE -n -d $diskInput)
    diskFloat=$(echo $diskSize | sed 's/G//g')
    diskAvailable=$(echo $diskFloat - 0.5 | bc)
    diskAvailable+="G"

    partitionerOutput

    echo -e "Would you like to have a swap partition? (y/n) \n"
    read swapPrompt

    if [ $swapPrompt == "y" ] || [ $swapPrompt == "Y" ]; then
        clear

        partitionerOutput
        
        echo -e "How large would you like your swap partition to be? (Example: '4G') \n"
        read swapInput

        sizeInput=$swapInput
        diskCalculator
    fi

    clear
    
    partitionerOutput

    echo "If you would like to limit the size of your root filesystem, such as to have a separate home partition, you can enter a value such as '50G' here."
    echo -e "Otherwise, if you would like your root partition to take up the entire drive, enter 'full' here. \n"
    read rootPrompt

    # If the user wants the root partition to take up all space after the EFI partition, a separate home on this disk isn't possible.
    if [ $rootPrompt == "full" ]; then
        separateHomePossible=0
    else
        sizeInput=$rootPrompt
        diskCalculator

        separateHomePossible=1
    fi

    if [ $separateHomePossible == "1" ]; then
        clear

        partitionerOutput

        echo -e "Would you like to have a separate home partition on disk $diskInput (y/n) \n"
        read homePrompt

        if [ $homePrompt == "y" ] || [ $homePrompt == "Y" ]; then
            clear
            
            partitionerOutput

            echo "How large would you like your home partition to be? (Example: '100G')"
            echo -e "You can choose to use the rest of your disk after the root partition by entering 'full' here. \n"
            read homeInput
            
            if [ $homeInput != "full" ]; then
                sizeInput=$homeInput
                diskCalculator
            fi
        fi
    fi

    installOptions

}

installOptions() {

    clear

    echo -e "Should this installation be encrypted? (y/n) \n"
    read encryptionPrompt

    clear

    if [ $encryptionPrompt == "y" ] || [ $encryptionPrompt == "Y" ]; then
        clear
        echo -e "Would you like to securely wipe the selected disk before setup? (y/n) \n"
        echo -e "This can take quite a long time depending on how many passes you choose. \n"
        read wipePrompt

        if [ $wipePrompt == "y" ] || [ $wipePrompt == "Y" ]; then
            echo -e "How many passes would you like to do on this disk? \n"
            echo -e "Sane values include 1-3. The more passes you choose, the longer this will take. \n"
            read passInput
        fi
    fi

    clear

    echo -e "What filesystem would you like to use? \n"
    echo -e "If you are unsure, choose 'ext4' here. \n"
    fsChoice=$(echo -e "ext4\nxfs" | fzf --height 10%)

    clear

    echo -e "Would you like to use sudo or doas? \n"
    echo -e "If you are unsure, choose 'sudo' here. \n"
    suChoice=$(echo -e "sudo\ndoas" | fzf --height 10%)

    clear

    echo -e "Which kernel would you like to use? \n"
    echo -e "If you are unsure, choose 'linux' here. \n"
    kernelChoice=$(echo -e "linux\nlinux-lts\nlinux-mainline" | fzf --height 10%)

    clear

    echo -e "Would you like to use grub or efistub? \n"
    echo -e "If you are unsure, choose 'grub' here. \n"
    # Will remove annoying red text once efistub has been properly tested.
    echo -e "${RED}efistub support should be considered an experimental feature. ${NC}\n"
    bootloaderChoice=$(echo -e "grub\nefistub" | fzf --height 10%)

    clear

    echo -e "Do you want to install firmware and utilities for wifi? (y/n) \n"
    echo -e "This option will include the packages 'iw', 'wpa_supplicant', and 'wifi-firmware'. \n"
    read wifiChoice

    clear

    echo -e "What do you want this computer to be called on the network? (Hostname) \n"
    read hostnameInput

    clear

    echo -e "Timezone selection... \n"
    echo -e "You can type here to search for your timezone. \n"
    timezonePrompt=$(awk '/^Z/ { print $2 }; /^L/ { print $3 }' /usr/share/zoneinfo/tzdata.zi | sort | fzf --height 10%)

    clear

    echo -e "Would you like to choose a repo mirror? (y/n) \n"
    echo -e "Tier 1 mirrors are recommended. If you choose 'n', repo-default will be used. \n"
    read mirrorInput

    if [ $mirrorInput == "Y" ] || [ $mirrorInput == "y" ]; then
        xmirror
        installRepo=$(cat /etc/xbps.d/*-repository-main.conf | sed 's/repository=//g')
    else
        if [ $muslSelection == "glibc" ]; then
            installRepo="https://repo-default.voidlinux.org/current"
        elif [ $muslSelection == "musl" ]; then
            installRepo="https://repo-default.voidlinux.org/current/musl"
        fi
    fi

    if [ $muslSelection == "glibc" ]; then
        ARCH="x86_64"
    elif [ $muslSelection == "musl" ]; then
        ARCH="x86_64-musl"
    fi

    clear

    echo -e "Would you like a minimal installation or a desktop installation? \n"
    echo -e "The minimal installation does not configure networking, graphics drivers, DE/WM, etc. \n"
    echo -e "The desktop installation will allow you to configure networking, install graphics drivers, choose an audio server, and install a DE or WM from this installer with sane defaults. \n"
    echo -e "If you choose the minimal installation, dhcpcd will be included by default and can be enabled in the new install for networking. \n"

    installType=$(echo -e "desktop\nminimal" | fzf --height 10%)

    clear

    # Extra install options
    if [ $installType == "desktop" ]; then

        echo -e "If you would like to install graphics drivers, please choose here. \n"
        echo -e "Both 'nvidia' and 'nvidia-optimus' include the proprietary official driver. \n"
        if [ $muslSelection == "musl" ]; then
            echo -e "Note that nvidia drivers are not compatible with musl. \n"
        fi
        echo -e "If you would like to skip installing graphics drivers here, choose 'skip' \n"

        if [ $muslSelection == "glibc" ]; then
            graphicsChoice=$(echo -e "skip\nnvidia-optimus\nnvidia\nintel\namd" | fzf --height 10%)
        elif [ $muslSelection == "musl" ]; then
            graphicsChoice=$(echo -e "skip\nintel\namd" | fzf --height 10%)
        fi

        clear

        echo -e "If you would like the installer to install NetworkManager or enable dhcpcd, choose one here. \n"
        echo -e "If you are unsure, choose 'NetworkManager'. If you would like to skip this, choose 'skip' \n"

        networkChoice=$(echo -e "skip\nNetworkManager\ndhcpcd" | fzf --height 10%)

        clear

        echo -e "Choose the audio server you would like to install, 'pipewire' is recommended here. \n"
        echo -e "If you would like to skip installing an audio server, choose 'skip' here. \n"

        audioChoice=$(echo -e "skip\npipewire\npulseaudio" | fzf --height 10%)

        clear

        echo -e "Choose the desktop environment or window manager you would like to install. \n"
        echo -e "If you would like to skip installing an DE/WM, choose 'skip' here. (Such as to install one that isn't in this list) \n"

        desktopChoice=$(echo -e "skip\ni3\nsway\nxfce\nkde\ngnome" | fzf --height 10%)

        if [ $desktopChoice == "i3" ]; then
            clear
            echo -e "Would you like to install lightdm with i3wm? (y/n) \n"
            read i3prompt
        elif [ $desktopChoice == "sway" ]; then
            clear
            echo -e "Sway will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in to the new installation. \n"
            read -p "Press Enter to continue." </dev/tty
        fi

        clear

        echo -e "Would you like to enable logging on the new installation with socklog? (y/n) \n"
        echo -e "This can be extremely useful for troubleshooting. \n"
        read logPrompt

        clear

        echo -e "Would you like to install flatpak? (y/n) \n"
        read flatpakPrompt

        confirmInstallationOptions
    elif [ $installType == "minimal" ]; then
        confirmInstallationOptions
    fi

}

confirmInstallationOptions() {  

    # If a config is being used, we need to set some variables that weren't defined earlier in the script
    if [ $configDetected == "1" ]; then
        if [ $rootPrompt != "full" ]; then
            separateHomePossible=1
        else
            separateHomePossible=0
        fi

        if [ -z $installRepo ]; then
            if [ $muslSelection == "glibc" ]; then
                installRepo="https://repo-default.voidlinux.org/current"
            elif [ $muslSelection == "musl" ]; then
                installRepo="https://repo-default.voidlinux.org/current/musl"
            fi
        fi
    fi

    clear

    if [ $configExported == 1 ]; then
        echo -e "${GREEN}This config has been successfully exported to $(pwd)/exportedconfig.sh ${NC} \n"
        configExported=0
    fi

    echo "Your disk will not be touched until you select 'confirm'"
    if [ $configDetected == "0" ]; then
        echo -e "If these choices are in any way incorrect, you may select 'restart' to go back to the beginning of the installer and start over."
    elif [ $configDetected == "1" ]; then
        echo -e "If these choices are in any way incorrect, you may select 'exit' to close the installer and make changes to your config."
    fi
    echo -e "If the following choices are correct, you may select 'confirm' to proceed with the installation. \n"
    echo -e "Selecting 'confirm' here will destroy all data on the selected disk and install with the options below. \n"

    echo -e "Detected libc: $muslSelection \n"

    echo "Repo mirror: $installRepo"
    echo "Bootloader: $bootloaderChoice"
    echo "Kernel: $kernelChoice"
    echo "Install disk: $diskInput"
    echo "Encryption: $encryptionPrompt"
    if [ $encryptionPrompt == "y" ] || [ $encryptionPrompt == "Y" ]; then
        echo "Wipe disk: $wipePrompt"
        if [ $wipePrompt == "y" ] || [ $wipePrompt == "Y" ]; then
            echo "Number of passes: $passInput"
        fi
    fi
    echo "Filesystem: $fsChoice"
    echo "SU choice: $suChoice"
    echo "Install wifi firmware: $wifiChoice"
    echo "Create swap: $swapPrompt"
    if [ $swapPrompt == "y" ] || [ $swapPrompt == "Y" ]; then
        echo "Swap size: $swapInput"
    fi
    echo "Root partition size: $rootPrompt"
    if [ $separateHomePossible == "1" ]; then
        echo "Create separate home: $homePrompt"
        if [ $homePrompt == "y" ] || [ $homePrompt == "Y" ]; then
            echo "Home size: $homeInput"
        fi
    fi
    echo "Hostname: $hostnameInput"
    echo -e "Timezone: $timezonePrompt \n"

    echo "Installation profile: $installType"
    if [ $installType == "desktop" ]; then
        echo "Graphics drivers: $graphicsChoice"
        echo "Networking: $networkChoice"
        echo "Audio server: $audioChoice"
        echo "DE/WM: $desktopChoice"
        if [ $desktopChoice == "i3" ]; then
            echo "Install lightdm with i3: $i3prompt"
        fi 
        echo "Enable system logging: $logPrompt"
        echo "Install flatpak: $flatpakPrompt"
    fi

    if [ $configDetected == "0" ]; then
        confirmInstall=$(echo -e "exit\nconfirm\nrestart\nexport as config" | fzf --height 10%)
    elif [ $configDetected == "1" ]; then
        confirmInstall=$(echo -e "exit\nconfirm" | fzf --height 10%)
    fi

    case $confirmInstall in
        confirm)
            install
            ;;

        restart)
            entry
            ;;

        exit)
            exit 0
            ;;
        "export as config")
            exportConfig
            ;;
        *)
            exit 1
            ;;
    esac

}

install() {

    if [ $wipePrompt == "y" ] || [ $wipePrompt == "Y" ]; then
        commandFailure="Disk erase has failed."
        clear
        echo -e "Beginning disk secure erase with $passInput passes and then overwriting with zeroes. \n"
        shred --verbose --random-source=/dev/urandom -n$passInput --zero $diskInput || failureCheck
    fi

    clear
    echo "Begin disk partitioning..."

    # We need to wipe out any existing VG on the chosen disk before the installer can continue, this is somewhat scuffed but works.
    deviceVG=$(pvdisplay $diskInput* | grep "VG Name" | while read c1 c2; do echo $c2; done | sed 's/Name//g')

    if [ -z $deviceVG ]; then
        echo -e "Existing VG not found, no need to do anything... \n"
    else
        commandFailure="VG Destruction has failed."
        echo -e "Existing VG found... \n"
        echo -e "Wiping out existing VG... \n"

        vgchange -a n $deviceVG || failureCheck
        vgremove $deviceVG || failureCheck
    fi

    # Make EFI boot partition and secondary partition to store lvm
    commandFailure="Disk partitioning has failed."
    wipefs -a $diskInput || failureCheck
    parted $diskInput mklabel gpt || failureCheck
    parted $diskInput mkpart primary 0% 500M --script || failureCheck
    parted $diskInput set 1 esp on --script || failureCheck
    parted $diskInput mkpart primary 500M 100% --script || failureCheck

    if [[ $diskInput == /dev/nvme* ]] || [[ $diskInput == /dev/mmcblk* ]]; then
        partition1="$diskInput"p1
        partition2="$diskInput"p2
    else
        partition1="$diskInput"1
        partition2="$diskInput"2
    fi

    mkfs.vfat $partition1 || failureCheck

    clear

    if [ $encryptionPrompt == "y" ] || [ $encryptionPrompt == "Y" ]; then
        echo "Configuring partitions for encrypted install..."
        echo -e "Enter your encryption passphrase here, the stronger the better. \n"
        if [ $bootloaderChoice == "grub" ]; then
            cryptsetup luksFormat --type luks1 $partition2 || failureCheck
        elif [ $bootloaderChoice == "efistub" ]; then
            # We get to use luks2 defaults for efistub setups since grubs lack of Argon2id support is not a problem here, sweet.
            cryptsetup luksFormat --type luks2 $partition2 || failureCheck
        fi
        echo -e "Opening new encrypted container... \n"
        cryptsetup luksOpen $partition2 void || failureCheck
    else
        pvcreate $partition2 || failureCheck
        echo -e "Creating volume group... \n"
        vgcreate void $partition2 || failureCheck
    fi

    if [ $encryptionPrompt == "y" ] || [ $encryptionPrompt == "Y" ]; then
        echo -e "Creating volume group... \n"
        vgcreate void /dev/mapper/void || failureCheck
    fi

    echo -e "Creating volumes... \n"

    if [ $swapPrompt == "y" ] || [ $swapPrompt == "Y" ]; then
        echo -e "Creating swap volume..."
        lvcreate --name swap -L $swapInput void || failureCheck
        mkswap /dev/void/swap || failureCheck
    fi

    if [ $rootPrompt == "full" ]; then
        echo -e "Creating full disk root volume..."
        lvcreate --name root -l 100%FREE void || failureCheck
    else
        echo -e "Creating $rootPrompt disk root volume..."
        lvcreate --name root -L $rootPrompt void || failureCheck
    fi

    if [ $fsChoice == "ext4" ]; then
        mkfs.ext4 /dev/void/root || failureCheck
    elif [ $fsChoice == "xfs" ]; then
        mkfs.xfs /dev/void/root || failureCheck
    fi

    if [ $separateHomePossible == "1" ]; then
        if [ $homePrompt == "y" ] || [ $homePrompt == "Y" ]; then
            if [ $homeInput == "full" ]; then
                lvcreate --name home -l 100%FREE void || failureCheck
            else
                lvcreate --name home -L $homeInput void || failureCheck
            fi

            if [ $fsChoice == "ext4" ]; then
                mkfs.ext4 /dev/void/home || failureCheck
            elif [ $fsChoice == "xfs" ]; then
                mkfs.xfs /dev/void/home || failureCheck
            fi

        fi
    fi

    echo -e "Mounting partitions... \n"
    commandFailure="Mounting partitions has failed."
    mount /dev/void/root /mnt || failureCheck
    for dir in dev proc sys run; do mkdir -p /mnt/$dir ; mount --rbind /$dir /mnt/$dir ; mount --make-rslave /mnt/$dir ; done || failureCheck

    if [ $bootloaderChoice == "grub" ]; then
        mkdir -p /mnt/boot/efi || failureCheck
        mount $partition1 /mnt/boot/efi || failureCheck
    elif [ $bootloaderChoice == "efistub" ]; then
        mkdir -p /mnt/boot || failureCheck
        mount $partition1 /mnt/boot || failureCheck
    fi

    echo -e "Copying keys... \n"
    commandFailure="Copying XBPS keys has failed."
    mkdir -p /mnt/var/db/xbps/keys || failureCheck
    cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys || failureCheck

    echo -e "Installing base system... \n"
    commandFailure="Base system installation has failed."
    sleep 1

    XBPS_ARCH=$ARCH xbps-install -Sy -R $installRepo -r /mnt base-minimal $kernelChoice ncurses libgcc bash file less man-pages mdocml pciutils usbutils dhcpcd kbd iproute2 iputils ethtool kmod acpid eudev lvm2 void-artwork || failureCheck

    # The dkms package will install headers for 'linux' rather than '$kernelChoice' unless we create a virtual package here, and we do not need both.
    if [ $kernelChoice == "linux-lts" ]; then
        echo "virtualpkg=linux-headers:linux-lts-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    elif [ $kernelChoice == "linux-mainline" ]; then
        echo "virtualpkg=linux-headers:linux-mainline-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    fi

    if [ $bootloaderChoice == "grub" ]; then
        echo -e "Installing grub... \n"
        commandFailure="Grub installation has failed."
        xbps-install -Sy -R $installRepo -r /mnt grub-x86_64-efi || failureCheck
    elif [ $bootloaderChoice == "efistub" ]; then
        echo -e "Installing efibootmgr... \n"
        commandFailure="efibootmgr installation has failed."
        xbps-install -Sy -R $installRepo -r /mnt efibootmgr || failureCheck
    fi

    if [ $installRepo != "https://repo-default.voidlinux.org/current" ] && [ $installRepo != "https://repo-default.voidlinux.org/current/musl" ]; then
        commandFailure="Repo configuration has failed."
        echo -e "Configuring mirror repo... \n"
        xmirror -s "$installRepo" -r /mnt || failureCheck
    fi

    commandFailure="$suChoice installation has failed."
    echo -e "Installing $suChoice... \n"
    if [ $suChoice == "sudo" ]; then
        xbps-install -Sy -R $installRepo -r /mnt sudo || failureCheck
    elif [ $suChoice == "doas" ]; then
        xbps-install -Sy -R $installRepo -r /mnt opendoas || failureCheck
    fi

    if [ $encryptionPrompt == "y" ] || [ $encryptionPrompt == "Y" ]; then
        commandFailure="Cryptsetup installation has failed."
        echo -e "Installing cryptsetup... \n"
        xbps-install -Sy -R $installRepo -r /mnt cryptsetup || failureCheck
    fi

    if [ $wifiChoice == "y" ] || [ $wifiChoice == "Y" ]; then
        commandFailure="Wifi firmware and utility installation has failed."
        echo -e "Installing wifi firmware and utilities... \n"
        xbps-install -Sy -R $installRepo -r /mnt iw wpa_supplicant wifi-firmware || failureCheck
    fi

    echo -e "Base system installed... \n"
    sleep 1

    echo -e "Configuring fstab... \n"
    commandFailure="Fstab configuration has failed."
    partVar=$(blkid -o value -s UUID $partition1)
    if [ $bootloaderChoice == "grub" ]; then
        echo "UUID=$partVar 	/boot/efi	vfat	defaults	0	0" >> /mnt/etc/fstab || failureCheck
    elif [ $bootloaderChoice == "efistub" ]; then
        echo "UUID=$partVar     /boot       vfat    defaults    0   0" >> /mnt/etc/fstab || failureCheck
    fi
    echo "/dev/void/root  /     $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck

    if [ $swapPrompt == "y" ] || [ $swapPrompt == "Y" ]; then
        echo "/dev/void/swap  swap  swap    defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    if [ $homePrompt == "y" ] && [ $separateHomePossible == "1" ]; then
        echo "/dev/void/home  /home $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    if [ $bootloaderChoice == "efistub" ]; then
        echo "Configuring dracut for efistub boot..."
        commandFailure="Dracut configuration has failed."
        echo 'hostonly="yes"' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck
        echo 'use_fstab="yes"' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck

        echo 'install_items+=" /etc/crypttab "' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck
        echo 'add_drivers+=" vfat nls_cp437 nls_iso8859_1 "' >> /mnt/etc/dracut.conf.d/30.conf || failureCheck

        echo "Moving runit service for efistub boot..."
        commandFailure="Moving runit service has failed."
        mv /mnt/etc/runit/core-services/03-filesystems.sh{,.bak} || failureCheck

        echo "Configuring xbps for efistub boot..."
        commaindFailure="efistub xbps configuration has failed."
        echo "noextract=/etc/runit/core-services/03-filesystems.sh" >> /mnt/etc/xbps.d/xbps.conf || failureCheck

        echo "Editing efibootmgr for efistub boot..."
        commandFailure="efibootmgr configuration has failed."
        sed -i -e 's/MODIFY_EFI_ENTRIES=0/MODIFY_EFI_ENTRIES=1/g' /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
        echo DISK="$diskInput" >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck
        echo 'PART="1"' >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck

        # An empty BOOTX64.EFI file needs to exist at the default/fallback efi location to stop some motherboards from nuking our efistub boot entry
        mkdir -p /mnt/boot/EFI/BOOT || failureCheck
        touch /mnt/boot/EFI/BOOT/BOOTX64.EFI || failureCheck

        echo 'OPTIONS="loglevel=4 rd.lvm.vg=void"' >> /mnt/etc/default/efibootmgr-kernel-hook || failureCheck

    elif [ $bootloaderChoice == "grub" ]; then
        if [ $encryptionPrompt == "Y" ] || [ $encryptionPrompt == "y" ]; then
            commandFailure="Configuring grub for full disk encryption has failed."
            echo -e "Configuring grub for full disk encryption... \n"
            partVar=$(blkid -o value -s UUID $partition2)
            sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.lvm.vg=void rd.luks.uuid='$partVar'"/g' /mnt/etc/default/grub || failureCheck # I really need to change how this is done, I know it's awful.
            echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub || failureCheck
        fi
    fi

    if [ $muslSelection == "glibc" ]; then
        commandFailure="Locale configuration has failed."
        echo -e "Configuring locales... \n"
        echo $locale > /mnt/etc/locale.conf || failureCheck
        echo $libclocale >> /mnt/etc/default/libc-locales || failureCheck
    fi

    commandFailure="Hostname configuration has failed."
    echo -e "Setting hostname.. \n"
    echo $hostnameInput > /mnt/etc/hostname || failureCheck

    if [ $installType == "minimal" ]; then
        chrootFunction
    elif [ $installType == "desktop" ]; then

        commandFailure="Graphics driver installation has failed."

        case $graphicsChoice in

            amd)
                echo -e "Installing AMD graphics drivers... \n"
                xbps-install -Sy -R $installRepo -r /mnt mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi mesa-vdpau || failureCheck
                echo -e "AMD graphics drivers have been installed. \n"
                ;;

            nvidia)
                echo -e "Installing NVIDIA graphics drivers... \n"
                xbps-install -Sy -R $installRepo -r /mnt void-repo-nonfree || failureCheck
                xmirror -s "$installRepo" -r /mnt || failureCheck
                xbps-install -Sy -R $installRepo -r /mnt nvidia || failureCheck
                echo -e "NVIDIA graphics drivers have been installed. \n"
                ;;

            intel)
                echo -e "Installing INTEL graphics drivers... \n"
                xbps-install -Sy -R $installRepo -r /mnt mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel || failureCheck
                echo -e "INTEL graphics drivers have been installed. \n"
                ;;

            nvidia-optimus)
                echo -e "Installing INTEL and NVIDIA graphics drivers... \n"
                xbps-install -Sy -R $installRepo -r /mnt void-repo-nonfree || failureCheck
                xmirror -s "$installRepo" -r /mnt || failureCheck
                xbps-install -Sy -R $installRepo -r /mnt nvidia mesa-dri vulkan-loader mesa-vulkan-intel intel-video-accel || failureCheck
                echo -e "INTEL and NVIDIA graphics drivers have been installed. \n"
                ;;

            *)
                echo -e "Continuing without graphics drivers... \n"
                ;;

        esac

        if [ $networkChoice == "NetworkManager" ]; then
            commandFailure="NetworkManager installation has failed."
            echo -e "Installing NetworkManager... \n"
            xbps-install -Sy -R $installRepo -r /mnt NetworkManager || failureCheck
            echo -e "NetworkManager has been installed. \n"
        fi

        commandFailure="Audio server installation has failed."
        if [ $audioChoice == "pipewire" ]; then
            echo -e "Installing pipewire... \n"
            xbps-install -Sy -R $installRepo -r /mnt pipewire alsa-pipewire wireplumber || failureCheck
            mkdir -p /mnt/etc/alsa/conf.d || failureCheck
            mkdir -p /mnt/etc/pipewire/pipewire.conf.d || failureCheck

            # This is now required to start pipewire and its session manager 'wireplumber' in an appropriate order, this should achieve a desireable result system-wide.
            echo 'context.exec = [ { path = "/usr/bin/wireplumber" args = "" } ]' > /mnt/etc/pipewire/pipewire.conf.d/10-wireplumber.conf || failureCheck

            echo -e "Pipewire has been installed. \n"
        elif [ $audioChoice == "pulseaudio" ]; then
            echo -e "Installing pulseaudio... \n"
            xbps-install -Sy -R $installRepo -r /mnt pulseaudio alsa-plugins-pulseaudio || failureCheck
            echo -e "Pulseaudio has been installed. \n"
        fi

        commandFailure="GUI installation has failed."

        case $desktopChoice in

            gnome)
                echo -e "Installing Gnome desktop environment... \n"
                xbps-install -Sy -R $installRepo -r /mnt gnome-core gnome-disk-utility gnome-console gnome-tweaks gnome-browser-connector gnome-text-editor xdg-user-dirs xorg-minimal || failureCheck
                echo -e "Gnome has been installed. \n"
                sleep 1
                ;;

            kde)
                echo -e "Installing KDE desktop environment... \n"
                xbps-install -Sy -R $installRepo -r /mnt kde5 kde5-baseapps xdg-user-dirs xorg-minimal || failureCheck
                echo -e "KDE has been installed. \n"
                sleep 1
                ;;

            xfce)
                echo -e "Installing XFCE desktop environment... \n"
                xbps-install -Sy -R $installRepo -r /mnt xfce4 lightdm lightdm-gtk3-greeter xorg-minimal xdg-user-dirs xorg-fonts || failureCheck
                echo -e "XFCE has been installed. \n"
                sleep 1
                ;;

            sway)
                echo -e "Installing Sway window manager... \n"
                xbps-install -Sy -R $installRepo -r /mnt sway elogind foot xorg-fonts || failureCheck
                echo -e "Sway has been installed. \n"
                sleep 1
                ;;

            i3)
                echo -e "Installing i3wm... \n"
                xbps-install -Sy -R $installRepo -r /mnt xorg-minimal xinit xterm i3 xorg-fonts || failureCheck
                echo -e "i3wm has been installed. \n"
                if [ $i3prompt == "y" ] || [ $i3prompt == "Y" ]; then
                    echo -e "Installing lightdm... \n"
                    xbps-install -Sy -R $installRepo -r /mnt lightdm lightdm-gtk3-greeter || failureCheck
                    echo "lightdm has been installed."
                fi
                ;;

            *)
                echo -e "Continuing without GUI... \n"
                ;;

        esac

        if [ $flatpakPrompt == "y" ] || [ $flatpakPrompt == "Y" ]; then
            commandFailure="Flatpak installation has failed."
            echo -e "Installing flatpak... \n"
            xbps-install -Sy -R $installRepo -r /mnt flatpak || failureCheck
            echo -e "Flatpak has been installed. \n"
        fi

        if [ $logPrompt == "y" ] || [ $logPrompt == "Y" ]; then
            commandFailure="Socklog installation has failed."
            echo -e "Installing socklog... \n"
            xbps-install -Sy -R $installRepo -r /mnt socklog-void || failureCheck
            echo -e "Socklog has been installed. \n"
        fi

        clear

        echo -e "Desktop setup completed. \n"
        echo -e "The system will now chroot into the new installation for final setup... \n"
        sleep 1

        chrootFunction
    fi

}

# Passing some stuff over to the new install to be used by the secondary script
chrootFunction() {

    commandFailure="System chroot has failed."
    cp /etc/resolv.conf /mnt/etc/resolv.conf || failureCheck
    echo "$bootloaderChoice" >> /mnt/tmp/bootChoice || failureCheck
    echo "$suChoice" >> /mnt/tmp/suChoice || failureCheck
    echo "$timezonePrompt" >> /mnt/tmp/selectTimezone || failureCheck
    echo "$encryptionPrompt" >> /mnt/tmp/encryption || failureCheck
    echo "$diskInput" >> /mnt/tmp/installDrive || failureCheck
    echo "$networkChoice" >> /mnt/tmp/networking || failureCheck
    cp -f $runDirectory/systemchroot.sh /mnt/tmp/systemchroot.sh || failureCheck
    chroot /mnt /bin/bash -c "/bin/bash /tmp/systemchroot.sh" || failureCheck

}

failureCheck() {

    echo -e "${RED}$commandFailure${NC}"
    echo "Installation will not proceed."
    exit 1

}

diskCalculator() {

    diskOperand=$(echo $sizeInput | sed 's/G//g')
    diskFloat=$(echo $diskFloat - $diskOperand | bc)
    diskAvailable=$(echo $diskFloat - 0.5 | bc)
    diskAvailable+="G"

    if [ $diskFloat -lt 0 ]; then
        clear
        echo -e "${RED}Used disk space cannot exceed the maximum capacity of the chosen disk. Have you over-provisioned your disk? ${NC}\n"
        read -p "Press Enter to start disk configuration again." </dev/tty
        diskConfiguration
    fi

    return 0

}

partitionerOutput() {

    echo -e "Disk: $diskInput"
    echo -e "Disk size: $diskSize"
    echo -e "Available disk space: $diskAvailable \n"

    return 0

}

exportConfig() {
    commandFailure="Exporting installer options as a config has failed."
    echo -e "#!/bin/bash \n" >> "$runDirectory"/exportedconfig.sh || failureCheck
    echo -e "# This is an auto-generated void-install-script config created on $(date) \n" >> "$runDirectory"/exportedconfig.sh || failureCheck

    exportedVarPairs=("installRepo $installRepo" \
    "diskInput $diskInput" \
    "swapPrompt $swapPrompt" \
    "swapInput $swapInput" \
    "rootPrompt $rootPrompt" \
    "homePrompt $homePrompt" \
    "homeInput $homeInput" \
    "encryptionPrompt $encryptionPrompt" \
    "wipePrompt $wipePrompt" \
    "passInput $passInput" \
    "suChoice $suChoice" \
    "wifiChoice $wifiChoice" \
    "kernelChoice $kernelChoice" \
    "bootloaderChoice $bootloaderChoice" \
    "fsChoice $fsChoice" \
    "hostnameInput $hostnameInput" \
    "timezonePrompt $timezonePrompt" \
    "installType $installType" \
    "graphicsChoice $graphicsChoice" \
    "networkChoice $networkChoice" \
    "audioChoice $audioChoice" \
    "desktopChoice $desktopChoice" \
    "i3prompt $i3prompt" \
    "logPrompt $logPrompt" \
    "flatpakPrompt $flatpakPrompt")

    for i in "${exportedVarPairs[@]}"
    do
        set -- $i || failureCheck
        echo "$1='$2'" >> "$runDirectory"/exportedconfig.sh || failureCheck
    done

    configExported=1
    confirmInstallationOptions
}

entry
