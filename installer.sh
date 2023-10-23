#!/bin/bash
user=$(whoami)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\e[1;33m'
NC='\033[0m'

if [ "$user" != root ]; then
    echo -e "${RED}Please execute this script as root.${NC}"
    exit 1
fi

entry() {

    runDirectory=$(pwd)
    sysArch=$(uname -m)
    locale="LANG=en_US.UTF-8"
    libclocale="en_US.UTF-8 UTF-8"

    # This script will only work on UEFI systems.
    if [ -e "/sys/firmware/efi" ]; then
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

    if [ "$sysArch" != "x86_64" ]; then
        commandFailure="This systems CPU architecture is not currently supported by this install script."
        failureCheck
    fi

    if [ -e "$runDirectory/systemchroot.sh" ]; then
        echo -e "Secondary script found. Continuing... \n"
    else
        commandFailure="Secondary script appears to be missing. This could be because the name of it is incorrect, or it does not exist in $runDirectory."
        failureCheck
    fi

    echo -e "Testing network connectivity... \n"

    if ping -c 1 gnu.org &>/dev/null || ping -c 1 fsf.org &>/dev/null ; then
        echo -e "Network check succeeded. \n"
    else
        commandFailure="Network check failed. Please make sure your network is active."
        failureCheck
    fi

    echo -e "Begin void installer... \n"

    echo -e "Grabbing installer dependencies... \n"
    commandFailure="Dependency installation has failed."
    xbps-install -Suy xbps || failureCheck # Just incase xbps is out of date on the ISO
    xbps-install -Suy dialog bc parted void-repo-nonfree || failureCheck

    echo -e "Creating .dialogrc... \n"
    dialog --create-rc ~/.dialogrc
    # I find the default blue background of dialog to be a little bit irritating, changing it to black here.
    sed -i -e 's/screen_color = (CYAN,BLUE,ON)/screen_color = (BLACK,BLACK,ON)/g' ~/.dialogrc
    # Might as well tweak some other stuff too...
    sed -i -e 's/title_color = (BLUE,WHITE,ON)/title_color = (BLACK,WHITE,ON)/g' ~/.dialogrc

    diskConfiguration

}

diskConfiguration() {

    # We're going to define all disk options and use them later on so the user can verify the layout and return to entry to start over if something isn't correct, before touching the disks.
    diskPrompt=$(lsblk -d -o NAME,SIZE -n -e7)
    diskReadout=$(lsblk -o NAME,SIZE,TYPE -e7)

    if ! diskPrompt=$(drawDialog --begin 2 2 --title "Available Disks" --infobox "$diskReadout" 0 0 --and-widget --title "Partitioner" --menu 'The disk you choose will not be modified until you confirm your installation options.\n\nPlease choose the disk you would like to partition and install Void Linux to:' 0 0 0 $diskPrompt) ; then
        exit 0
    fi

    diskInput="/dev/$diskPrompt"

    diskSize=$(lsblk --output SIZE -n -d $diskInput)
    diskFloat=$(echo $diskSize | sed 's/G//g')
    diskAvailable=$(echo $diskFloat - 0.5 | bc)
    diskAvailable+="G"

    partOutput=$(partitionerOutput)

    if drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --title "Partitioner" --yesno "Would you like to have a swap partition?" 0 0 ; then
        swapPrompt="Yes"
        partOutput=$(partitionerOutput)
        
        swapInput=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "Partitioner" --inputbox "How large would you like your swap partition to be?\n(Example: '4G')" 0 0)

        sizeInput=$swapInput
        diskCalculator
        partOutput=$(partitionerOutput)
    fi

    rootPrompt=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "Partitioner" --inputbox "If you would like to limit the size of your root filesystem, such as to have a separate home partition, you can enter a value such as '50G' here.\n\nOtherwise, if you would like your root partition to take up the entire drive, enter 'full' here." 0 0)

    # If the user wants the root partition to take up all space after the EFI partition, a separate home on this disk isn't possible.
    if [ "$rootPrompt" == "full" ]; then
        separateHomePossible=0
        homePrompt="No"
    else
        sizeInput=$rootPrompt
        diskCalculator
        partOutput=$(partitionerOutput)

        separateHomePossible=1
    fi

    if [ "$separateHomePossible" == "1" ]; then
        if drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --title "Partitioner" --yesno "Would you like to have a separate home partition?" 0 0 ; then
            homePrompt="Yes"
            homeInput=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$partOutput" 0 0 --and-widget --no-cancel --title "Partitioner" --inputbox "How large would you like your home partition to be?\n(Example: '100G')\n\nYou can choose to use the rest of your disk after the root partition by entering 'full' here." 0 0)
            
            if [ "$homeInput" != "full" ]; then
                sizeInput=$homeInput
                diskCalculator
            fi
        else
            homePrompt="No"
        fi
    fi

    installOptions

}

installOptions() {

    if drawDialog --title "Encryption" --yesno "Should this installation be encrypted?" 0 0 ; then
        encryptionPrompt="Yes"
        if drawDialog --title "Wipe Disk" --yesno "Would you like to securely wipe the selected disk before setup?\n\nThis can take quite a long time depending on how many passes you choose." 0 0 ; then
            wipePrompt="Yes"
            passInput=$(drawDialog --title "Wipe Disk" --inputbox "How many passes would you like to do on this disk?\n\nSane values include 1-3. The more passes you choose, the longer this will take." 0 0)
        else
            wipePrompt="No"
            passInput=0
        fi
    fi

    # More filesystems such as btrfs can be added later.
    fsChoice=$(drawDialog --no-cancel --title "Filesystem choice" --menu "If you are unsure, choose 'ext4'" 0 0 0 "ext4" "" "xfs" "")

    suChoice=$(drawDialog --no-cancel --title "SU choice" --menu "If you are unsure, choose 'sudo'" 0 0 0 "sudo" "" "doas" "")

    kernelChoice=$(drawDialog --no-cancel --title "Kernel choice" --menu "If you are unsure, choose 'linux'" 0 0 0 "linux" "- Normal Void kernel" "linux-lts" "- Older LTS kernel" "linux-mainline" "- Bleeding edge kernel")

    bootloaderChoice=$(drawDialog --no-cancel --title "Bootloader choice" --menu "If you are unsure, choose 'grub'" 0 0 0 "grub" "- Traditional bootloader" "efistub" "- Boot kernel directly")

    hostnameInput=$(drawDialog --no-cancel --title "System hostname" --inputbox "Set your system hostname." 0 0)

    createUser=$(drawDialog --title "Create User" --inputbox "What would you like your username to be?\n\nIf you do not want to set a user here, choose 'Skip'\n\nYou will be asked to set a password later." 0 0)

    # Most of this timezone section is taken from the normal Void installer.
    areas=(Africa America Antarctica Arctic Asia Atlantic Australia Europe Indian Pacific)

    if area=$(IFS='|'; drawDialog --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${areas[@]}")) ; then
        read -a locations -d '\n' < <(find /usr/share/zoneinfo/$area -type f -printf '%P\n' | sort) || echo "Disregard exit code"
        location=$(IFS='|'; drawDialog --no-cancel --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${locations[@]//_/ }"))
    fi

    location=$(echo $location | tr ' ' '_')
    timezonePrompt="$area/$location"

    if drawDialog --title "Repository Mirror" --yesno "Would you like to set your repo mirror?" 0 0 ; then
        xmirror
        installRepo=$(cat /etc/xbps.d/*-repository-main.conf | sed 's/repository=//g')
    else
        if [ "$muslSelection" == "glibc" ]; then
            installRepo="https://repo-default.voidlinux.org/current"
        elif [ "$muslSelection" == "musl" ]; then
            installRepo="https://repo-default.voidlinux.org/current/musl"
        fi
    fi

    if [ "$muslSelection" == "glibc" ]; then
        ARCH="x86_64"
    elif [ "$muslSelection" == "musl" ]; then
        ARCH="x86_64-musl"
    fi

    installType=$(drawDialog --no-cancel --title "Profile Choice" --menu "Choose your installation profile:" 0 0 0 "minimal" " - Installs base system only, dhcpcd included for networking." "desktop" "- Provides extra optional install choices.")

    # Extra install options
    if [ "$installType" == "desktop" ]; then

        if [ "$muslSelection" == "glibc" ]; then
            graphicsChoice=$(drawDialog --title "Graphics Drivers" --menu "Both nvidia and nvidia-optimus include the proprietary official driver.\n\nChoose 'Skip' if you want to skip installing graphics drivers." 0 0 0 "intel" "" "amd" "" "nvidia" "" "nvidia-optimus" "")
        elif [ "$muslSelection" == "musl" ]; then
            graphicsChoice=$(drawDialog --title "Graphics Drivers" --menu "Note that nvidia drivers are incompatible with musl.\n\nChoose 'Skip' if you want to skip installing graphics drivers." 0 0 0 "intel" "" "amd" "")
        fi

        networkChoice=$(drawDialog --title "Networking" --menu "If you are unsure, choose 'NetworkManager'\n\nChoose 'Skip' if you want to skip." 0 0 0 "NetworkManager" "" "dhcpcd" "")

        audioChoice=$(drawDialog --title "Audio Server" --menu "If you are unsure, 'pipewire' is recommended.\n\nChoose 'Skip' if you want to skip." 0 0 0 "pipewire" "" "pulseaudio" "")

        desktopChoice=$(drawDialog --title "Desktop Environment" --menu "Choose 'Skip' if you want to skip." 0 0 0 "gnome" "" "kde" "" "xfce" "" "sway" "" "i3" "")

        if [ "$desktopChoice" == "i3" ]; then
            if drawDialog --title "" --yesno "Would you like to install lightdm with i3wm?" 0 0 ; then
                i3prompt="Yes"
            fi
        elif [ "$desktopChoice" == "sway" ]; then
            drawDialog --msgbox "Sway will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in to the new installation." 0 0
        fi

        # Extras
        read -a modulesList -d '\n' < <(ls modules/ | sort)
        commandFailure="Importing module has failed."

        for i in "${modulesList[@]}"
        do
            if [ -e "modules/$i" ] && checkModule ; then
                . "modules/$i" || failureCheck
                modulesDialogArray+=("'$title' '$description' '$status'")
            fi
        done

        # Using sh here as a simple solution to it misbehaving when ran normally
        modulesChoice=( $(sh -c "dialog --stdout --title 'Extra Options' --no-mouse --backtitle "https://github.com/kkrruumm/void-install-script" --checklist 'Enable or disable extra install options: ' 0 0 0 $(echo "${modulesDialogArray[@]}")") )

        confirmInstallationOptions
    elif [ "$installType" == "minimal" ]; then
        confirmInstallationOptions
    fi

}

confirmInstallationOptions() {  

    drawDialog --yes-label "Install" --no-label "Exit" --extra-button --extra-label "Restart" --title "Confirm Installation Choices" --yesno "    Selecting 'Install' here will install with the options below. \n\n
        Repo mirror: $installRepo \n
        Bootloader: $bootloaderChoice \n
        Kernel: $kernelChoice \n
        Install disk: $diskInput \n
        Encryption: $encryptionPrompt \n
        Wipe disk: $wipePrompt \n
        Number of disk wipe passes: $passInput \n
        Filesystem: $fsChoice \n
        SU Choice: $suChoice \n
        Create swap: $swapPrompt \n
        Swap size: $swapInput \n
        Root partition size: $rootPrompt \n
        Create separate home: $homePrompt \n
        Home size: $homeInput \n
        Hostname: $hostnameInput \n
        Timezone: $timezonePrompt \n
        User: $createUser \n
        Installation profile: $installType \n\n
        $( if [ -n "$modulesChoice" ]; then echo "Enabled modules: ${modulesChoice[@]}"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "Graphics drivers: $graphicsChoice"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "Networking: $networkChoice"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "Audio server: $audioChoice"; fi ) \n
        $( if [ $installType == "desktop" ]; then echo "DE/WM: $desktopChoice"; fi ) \n\n
        $( if [ $desktopChoice == "i3" ]; then echo "Install lightdm with i3: $i3prompt"; fi ) \n
    You can choose 'Restart' to go back to the beginning of the installer and change settings." 0 0

    case $? in 
        0)
            install
            ;;
        1)
            exit 0
            ;;
        3)
            entry
            ;;
        *)
            commandFailure="Invalid confirm settings exit code"
            failureCheck
            ;;
    esac
    
}

install() {

    if [ "$wipePrompt" == "Yes" ]; then
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

    if [ "$encryptionPrompt" == "Yes" ]; then
        echo "Configuring partitions for encrypted install..."

        # Cryptsetup options, not exposing to user directly but modify values here if you'd like.
        hash="sha512"
        keysize="512"
        itertime="10000" # Read comments below

        # The higher the itertime value, the longer brute forcing the drive will take.
        # The value here will equal the amount of time it takes to unlock the drive in milliseconds calculated for the system this is ran on.
        # However, due to this, if the drive is then put into a system with a faster CPU, it will unlock quicker. Raising this value on systems with slower CPUs may be a good idea.
        # 10 seconds should be a good enough default for this installer, with the luks default being 2 seconds.
        # The fips140 compliant value here would be 600000 according to owasp, though this would result in a 10 minute disk unlock time.

        echo -e "${YELLOW}Enter your encryption passphrase here, the stronger the better. ${NC}\n"
        if [ "$bootloaderChoice" == "grub" ]; then
            # We need to use luks1 and pbkdf2 to maintain compatibility with grub here.
            # It should be possible to replace the grub EFI binary to add luks2 support, but for the time being I'm going to leave this as luks1.
            cryptsetup luksFormat --type luks1 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf pbkdf2 --use-urandom $partition2 || failureCheck
        elif [ "$bootloaderChoice" == "efistub" ]; then
            # We get to use luks2 here, no need to maintain compatibility.
            cryptsetup luksFormat --type luks2 --batch-mode --verify-passphrase --hash $hash --key-size $keysize --iter-time $itertime --pbkdf argon2id --use-urandom $partition2 || failureCheck
        fi
        echo -e "${YELLOW}Opening new encrypted container... ${NC}\n"
        cryptsetup luksOpen $partition2 void || failureCheck
    else
        pvcreate $partition2 || failureCheck
        echo -e "Creating volume group... \n"
        vgcreate void $partition2 || failureCheck
    fi

    if [ "$encryptionPrompt" == "Yes" ]; then
        echo -e "Creating volume group... \n"
        vgcreate void /dev/mapper/void || failureCheck
    fi

    echo -e "Creating volumes... \n"

    if [ "$swapPrompt" == "Yes" ]; then
        echo -e "Creating swap volume..."
        lvcreate --name swap -L $swapInput void || failureCheck
        mkswap /dev/void/swap || failureCheck
    fi

    if [ "$rootPrompt" == "full" ]; then
        echo -e "Creating full disk root volume..."
        lvcreate --name root -l 100%FREE void || failureCheck
    else
        echo -e "Creating $rootPrompt disk root volume..."
        lvcreate --name root -L $rootPrompt void || failureCheck
    fi

    if [ "$fsChoice" == "ext4" ]; then
        mkfs.ext4 /dev/void/root || failureCheck
    elif [ "$fsChoice" == "xfs" ]; then
        mkfs.xfs /dev/void/root || failureCheck
    fi

    if [ "$separateHomePossible" == "1" ]; then
        if [ "$homePrompt" == "Yes" ]; then
            if [ "$homeInput" == "full" ]; then
                lvcreate --name home -l 100%FREE void || failureCheck
            else
                lvcreate --name home -L $homeInput void || failureCheck
            fi

            if [ "$fsChoice" == "ext4" ]; then
                mkfs.ext4 /dev/void/home || failureCheck
            elif [ "$fsChoice" == "xfs" ]; then
                mkfs.xfs /dev/void/home || failureCheck
            fi

        fi
    fi

    echo -e "Mounting partitions... \n"
    commandFailure="Mounting partitions has failed."
    mount /dev/void/root /mnt || failureCheck
    for dir in dev proc sys run; do mkdir -p /mnt/$dir ; mount --rbind /$dir /mnt/$dir ; mount --make-rslave /mnt/$dir ; done || failureCheck

    if [ "$bootloaderChoice" == "grub" ]; then
        mkdir -p /mnt/boot/efi || failureCheck
        mount $partition1 /mnt/boot/efi || failureCheck
    elif [ "$bootloaderChoice" == "efistub" ]; then
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
    if [ "$kernelChoice" == "linux-lts" ]; then
        echo "virtualpkg=linux-headers:linux-lts-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    elif [ "$kernelChoice" == "linux-mainline" ]; then
        echo "virtualpkg=linux-headers:linux-mainline-headers" >> /mnt/etc/xbps.d/headers.conf || failureCheck
    fi

    if [ "$bootloaderChoice" == "grub" ]; then
        echo -e "Installing grub... \n"
        commandFailure="Grub installation has failed."
        xbps-install -Sy -R $installRepo -r /mnt grub-x86_64-efi || failureCheck
    elif [ "$bootloaderChoice" == "efistub" ]; then
        echo -e "Installing efibootmgr... \n"
        commandFailure="efibootmgr installation has failed."
        xbps-install -Sy -R $installRepo -r /mnt efibootmgr || failureCheck
    fi

    if [ "$installRepo" != "https://repo-default.voidlinux.org/current" ] && [ "$installRepo" != "https://repo-default.voidlinux.org/current/musl" ]; then
        commandFailure="Repo configuration has failed."
        echo -e "Configuring mirror repo... \n"
        xmirror -s "$installRepo" -r /mnt || failureCheck
    fi

    commandFailure="$suChoice installation has failed."
    echo -e "Installing $suChoice... \n"
    if [ "$suChoice" == "sudo" ]; then
        xbps-install -Sy -R $installRepo -r /mnt sudo || failureCheck
    elif [ "$suChoice" == "doas" ]; then
        xbps-install -Sy -R $installRepo -r /mnt opendoas || failureCheck
    fi

    if [ "$encryptionPrompt" == "Yes" ]; then
        commandFailure="Cryptsetup installation has failed."
        echo -e "Installing cryptsetup... \n"
        xbps-install -Sy -R $installRepo -r /mnt cryptsetup || failureCheck
    fi

    echo -e "Base system installed... \n"
    sleep 1

    echo -e "Configuring fstab... \n"
    commandFailure="Fstab configuration has failed."
    partVar=$(blkid -o value -s UUID $partition1)
    if [ "$bootloaderChoice" == "grub" ]; then
        echo "UUID=$partVar 	/boot/efi	vfat	defaults	0	0" >> /mnt/etc/fstab || failureCheck
    elif [ "$bootloaderChoice" == "efistub" ]; then
        echo "UUID=$partVar     /boot       vfat    defaults    0   0" >> /mnt/etc/fstab || failureCheck
    fi
    echo "/dev/void/root  /     $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck

    if [ "$swapPrompt" == "Yes" ]; then
        echo "/dev/void/swap  swap  swap    defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    if [ "$homePrompt" == "Yes" ] && [ "$separateHomePossible" == "1" ]; then
        echo "/dev/void/home  /home $fsChoice     defaults              0       0" >> /mnt/etc/fstab || failureCheck
    fi

    if [ "$bootloaderChoice" == "efistub" ]; then
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
        commandFailure="efistub xbps configuration has failed."
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

    elif [ "$bootloaderChoice" == "grub" ]; then
        if [ "$encryptionPrompt" == "Yes" ]; then
            commandFailure="Configuring grub for full disk encryption has failed."
            echo -e "Configuring grub for full disk encryption... \n"
            partVar=$(blkid -o value -s UUID $partition2)
            sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 rd.lvm.vg=void rd.luks.uuid='$partVar'"/g' /mnt/etc/default/grub || failureCheck
            echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub || failureCheck
        fi
    fi

    if [ "$muslSelection" == "glibc" ]; then
        commandFailure="Locale configuration has failed."
        echo -e "Configuring locales... \n"
        echo $locale > /mnt/etc/locale.conf || failureCheck
        echo $libclocale >> /mnt/etc/default/libc-locales || failureCheck
    fi

    commandFailure="Hostname configuration has failed."
    echo -e "Setting hostname.. \n"
    echo $hostnameInput > /mnt/etc/hostname || failureCheck

    if [ "$installType" == "minimal" ]; then
        chrootFunction
    elif [ "$installType" == "desktop" ]; then

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

        if [ "$networkChoice" == "NetworkManager" ]; then
            commandFailure="NetworkManager installation has failed."
            echo -e "Installing NetworkManager... \n"
            xbps-install -Sy -R $installRepo -r /mnt NetworkManager || failureCheck
            echo -e "NetworkManager has been installed. \n"
        fi

        commandFailure="Audio server installation has failed."
        if [ "$audioChoice" == "pipewire" ]; then
            echo -e "Installing pipewire... \n"
            xbps-install -Sy -R $installRepo -r /mnt pipewire alsa-pipewire wireplumber || failureCheck
            mkdir -p /mnt/etc/alsa/conf.d || failureCheck
            mkdir -p /mnt/etc/pipewire/pipewire.conf.d || failureCheck

            # This is now required to start pipewire and its session manager 'wireplumber' in an appropriate order, this should achieve a desireable result system-wide.
            echo 'context.exec = [ { path = "/usr/bin/wireplumber" args = "" } ]' > /mnt/etc/pipewire/pipewire.conf.d/10-wireplumber.conf || failureCheck

            echo -e "Pipewire has been installed. \n"
        elif [ "$audioChoice" == "pulseaudio" ]; then
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
                if [ "$i3prompt" == "Yes" ]; then
                    echo -e "Installing lightdm... \n"
                    xbps-install -Sy -R $installRepo -r /mnt lightdm lightdm-gtk3-greeter || failureCheck
                    echo "lightdm has been installed."
                fi
                ;;

            *)
                echo -e "Continuing without GUI... \n"
                ;;

        esac

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
    
    syschrootVarPairs=("bootloaderChoice $bootloaderChoice" \
    "suChoice $suChoice" \
    "timezonePrompt $timezonePrompt" \
    "encryptionPrompt $encryptionPrompt" \
    "diskInput $diskInput" \
    "networkChoice $networkChoice" \
    "createUser $createUser")

    for i in "${syschrootVarPairs[@]}"
    do
        set -- $i || failureCheck
        echo "$1='$2'" >> /mnt/tmp/installerOptions || failureCheck
    done

    cp -f $runDirectory/systemchroot.sh /mnt/tmp/systemchroot.sh || failureCheck
    chroot /mnt /bin/bash -c "/bin/bash /tmp/systemchroot.sh" || failureCheck

    postInstall

}

drawDialog() {

    commandFailure="Displaying dialog window has failed."
    dialog --stdout --cancel-label "Skip" --no-mouse --backtitle "https://github.com/kkrruumm/void-install-script" "$@"

}

checkModule() {

    # We need to make sure a few variables at minimum exist before the installer should accept it.
    # Past this, I'm going to leave verifying correctness to the author of the module.
    if grep "title="*"" "modules/$i" && ( grep "status=on" "modules/$i" || grep "status=off" "modules/$i" ) && ( grep "description="*"" "modules/$i" ) && ( grep "main()" "modules/$i" ); then
        return 0
    else
        # Skip found module file if its contents do not comply.
        return 1
    fi

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

    if [ "$diskFloat" -lt 0 ]; then
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

postInstall() {

    if [ -z "$modulesChoice" ]; then
        clear

        echo -e "${GREEN}Installation complete.${NC} \n"
        echo -e "If you are ready to reboot into your new system, enter 'sudo reboot now' \n"
        exit 0
    else
        commandFailure="Executing module has failed."
        for i in "${modulesChoice[@]}"
        do
            # Source and execute each module
            . "modules/$i"  || failureCheck
            main
        done

        clear

        echo -e "${GREEN}Installation complete.${NC} \n"
        echo -e "If you are ready to reboot into your new system, enter 'sudo reboot now' \n"
        exit 0
    fi

}

entry
