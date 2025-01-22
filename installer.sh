#!/bin/bash

# This script is an "orchestrator" for the other scripts that exist in the "setup" directory, and is only responsible for setting values and displaying the TUI.
# This keeps the installer cleaner and easier to manipulate.

# Source installer library
. "$(pwd)/lib/libviss" ||
    { echo "$(pwd)/lib/libvis not found. Cannot continue." ; exit 1 ; }

# Source basic installer setup script
. "$(pwd)/setup/setupinstaller" ||
    { commandFailure="$(pwd)/setup/setupinstaller not found. Cannot continue." ; die ; }

# Source hidden settings file, if there is one.
if [ "$#" == "1" ]; then
    . "$1" ||
        { commandFailure="Sourcing hidden options file has failed." ; die ; }
fi

# Default to voids base-system unless otherwise defined in the hidden settings file
[ -z "$basesystem" ] &&
    basesystem="base-system"

# Each section of the installer will have its own function, so the user can go back to a specific spot to change something.
diskConfig() {
    local diskList=$(lsblk -d -o NAME,SIZE -n -e7)
    local diskIndicator=$(lsblk -o NAME,SIZE,TYPE -e7)

    if diskInput=$(drawDialog --begin 2 2 --title "Available Disks" --infobox "$diskIndicator" 0 0 --and-widget --title "Partitioner" --menu "The disk you choose will not be modified until you confirm your installation options.\n\nPlease choose the disk you would like to partition and install Void Linux to:" 0 0 0 $diskList) ; then
        diskInput="/dev/$diskInput"
    else
        exit 0
    fi

    diskSize=$(lsblk --output SIZE -n -d "$diskInput")
    diskFloat=$(echo "$diskSize" | sed 's/G//g')
    diskAvailable=$(echo "$diskFloat" - 0.5 | bc)
    diskAvailable+="G"

    local diskIndicator=$(partitionerOutput)

    if drawDialog --title "Partitioner - Encryption" --yesno "Should this installation be encrypted?" 0 0 ; then
        encryption="Yes"
        drawDialog --title "Partitioner - Wipe Disk" --yesno "Would you like to securely wipe the selected disk before setup?\n\nThis can take quite a long time depending on how many passes you choose.\n\nBe aware that doing this on an SSD is likely a bad idea." 0 0 &&
            wipedisk=$(drawDialog --title "Partitioner - Wipe Disk" --inputbox "How many passes would you like to do on this disk?\n\nSane values include 1-3. The more passes you choose, the longer this will take." 0 0)
    else
        encryption="No"
    fi

    if drawDialog --title "Partitioner - LVM" --yesno "Would you like to use LVM?" 0 0 ; then
        lvm="Yes"
    else
        lvm="No"
    fi

    drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --yesno "Would you like to use swap?" 0 0 &&
        if [ "$lvm" == "Yes" ] || [ "$encryption" == "No" ]; then
            swapStyle=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --menu "What style of swap would you like to use?\n\nIf you are unsure, 'swapfile' is recommended." 0 0 0 "swapfile" "- On-filesystem swapfile" "zram" "- RAM in your RAM, but smaller" "partition" "- Traditional swap partition")
        else
            swapStyle=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --menu "What style of swap would you like to use?\n\nIf you are unsure, 'swapfile' is recommended." 0 0 0 "swapfile" "- On-filesystem swapfile" "zram" "- RAM in your RAM, but smaller")
        fi

    case "$swapStyle" in
        swapfile) swapSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --inputbox "How large would you like your swapfile to be?\n(Example: '4G')" 0 0) ;;
        zram) swapSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --inputbox "How large would you like your compressed ramdisk to be?\n(Example: '4G')" 0 0) ;;
        partition)
            swapSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --inputbox "How large would you like your swap partition to be?\n(Example: '4G')" 0 0)
            local sizeInput=$swapSize && diskCalculator && local diskIndicator=$(partitionerOutput)
        ;;
    esac

    rootSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Root" --inputbox "If you would like to limit the size of your root filesystem, such as to have a separate home partition, you can enter a value such as '50G' here.\n\nOtherwise, if you would like your root partition to take up the entire drive, enter 'full' here." 0 0)

    if [ "$rootSize" == "full" ]; then
        local separateHomePossible="No"
    elif [ "$lvm" == "No" ] && [ "$encryption" == "Yes" ]; then
        local separateHomePossible="No"
    else
        local sizeInput=$rootSize && diskCalculator && local diskIndicator=$(partitionerOutput)
    fi

    [ "$separateHomePossible" != "No" ] &&
        drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --title "Partitioner - Home" --yesno "Would you like to have a separate home partition?" 0 0 &&
            homeSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Home" --inputbox "How large would you like your home partition to be?\n(Example: '100G')\n\nYou can choose to use the rest of your disk after the root partition by entering 'full' here." 0 0)

    filesystem=$(drawDialog --no-cancel --title "Partitioner - Filesystem" --menu "If you are unsure, choose 'ext4'" 0 0 0 "ext4" "" "xfs" "")
}

suConfig() {
    su=$(drawDialog --no-cancel --title "SU Choice" --menu "If you are unsure, choose 'sudo'" 0 0 0 "sudo" "" "doas" "" "none" "")
}

kernelConfig() {
    kernel=$(drawDialog --no-cancel --title "Kernel Choice" --menu "If you are unsure, choose 'linux'" 0 0 0 "linux" "- Normal Void kernel" "linux-lts" "- Older LTS kernel" "linux-mainline" "- Bleeding edge kernel")
}

bootloaderConfig() {
    bootloader=$(drawDialog --no-cancel --title "Bootloader choice" --menu "If you are unsure, choose 'grub'" 0 0 0 "grub" "- Traditional bootloader" "uki" "- Unified Kernel Image (experimental)" "none" "- Installs no bootloader (Advanced)")
}

hostnameConfig() {
    hostname=$(drawDialog --no-cancel --title "System Hostname" --inputbox "Set your system hostname." 0 0)
}

userConfig() {
    username=$(drawDialog --title "Create User" --inputbox "What would you like your username to be?\n\nIf you do not want to set a user here, choose 'Skip'\n\nYou will be asked to set a password later." 0 0)
}

timezoneConfig() {
    # Most of this timezone section is taken from the normal Void installer.
    local areas=(Africa America Antarctica Arctic Asia Atlantic Australia Europe Indian Pacific)
    if area=$(IFS='|'; drawDialog --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${areas[@]}")) ; then
        read -a locations -d '\n' < <(find /usr/share/zoneinfo/$area -type f -printf '%P\n' | sort) || echo "Disregard exit code"
        local location=$(IFS='|'; drawDialog --no-cancel --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${locations[@]//_/ }"))
    fi
    local location=$(echo $location | tr ' ' '_')
    timezone="$area/$location"
}

localeConfig() {
    # This line is also taken from the normal Void installer.
    localeList=$(grep -E '\.UTF-8' /etc/default/libc-locales | awk '{print $1}' | sed -e 's/^#//')

    for i in $localeList
    do
        # We don't need to specify an item here, only a tag and print it to stdout
        tmp+=("$i" $(printf '\u200b')) # Use a zero width unicode character for the item
    done

    local localeChoice=$(drawDialog --no-cancel --title "Locale Selection" --menu "Please choose your system locale." 0 0 0 ${tmp[@]})
    locale="LANG=$localeChoice"
    libclocale="$localeChoice UTF-8"
}

repositoryConfig() {
    if drawDialog --title "Repository Mirror" --yesno "Would you like to set your repo mirror?" 0 0 ; then
        xmirror
        repository=$(cat /etc/xbps.d/*-repository-main.conf | sed 's/repository=//g')
    else
        [ "$libc" == "glibc" ] && repository="https://repo-default.voidlinux.org/current"
        [ "$libc" == "musl" ] && repository="https://repo-default.voidlinux.org/current/musl"
    fi

    [ "$libc" == "glibc" ] && ARCH="x86_64"
    [ "$libc" == "musl" ] && ARCH="x86_64-musl"
}

installConfig() {
    profile=$(drawDialog --no-cancel --title "Profile Choice" --menu "Choose your installation profile:" 0 0 0 "minimal" " - Installs base system only, dhcpcd included for networking." "desktop" "- Provides extra optional install choices.")
}

graphicsConfig() {
    [ "$libc" == "glibc" ] &&
        graphics=$(drawDialog --title 'Graphics Drivers' --checklist 'Select graphics drivers: ' 0 0 0 'intel' '' 'off' 'intel-32bit' '' 'off' 'amd' '' 'off' 'amd-32bit' '' 'off' 'nvidia' '- Proprietary driver' 'off' 'nvidia-32bit' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau driver (experimental)' 'off' 'nvidia-nouveau-32bit' '' 'off')
    [ "$libc" == "musl" ] &&
        graphics=$(drawDialog --title 'Graphics Drivers' --checklist 'Select graphics drivers: ' 0 0 0 'intel' '' 'off' 'amd' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau driver (experimental)' 'off')

    [ -n "$graphics" ] &&
        IFS=" " read -r -a graphicsArray <<< "$graphics"
}

networkConfig() {
    network=$(drawDialog --title "Networking" --menu "If you are unsure, choose 'NetworkManager'\n\nChoose 'Skip' if you want to skip." 0 0 0 "NetworkManager" "" "dhcpcd" "")
}

audioConfig() {
    audio=$(drawDialog --title "Audio Server" --menu "If you are unsure, 'pipewire' is recommended.\n\nChoose 'Skip' if you want to skip." 0 0 0 "pipewire" "" "pulseaudio" "")
}

desktopConfig() {
    desktop=$(drawDialog --title "Desktop Environment" --menu "Choose 'Skip' if you want to skip." 0 0 0 "gnome" "" "kde" "" "xfce" "" "sway" "" "swayfx" "" "wayfire" "" "i3" "")

    case "$desktop" in
        sway) drawDialog --msgbox "Sway will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in on the new installation." 0 0 ;;
        swayfx) drawDialog --msgbox "SwayFX will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in on the new installation." 0 0 ;;
        wayfire) drawDialog --msgbox "Wayfire will have to be started manually on login. This can be done by entering 'dbus-run-session wayfire' after logging in on the new installation." 0 0 ;;
        i3) drawDialog --title "" --yesno "Would you like to install lightdm with i3?" 0 0 && lightdm="Yes" ;;
    esac
}

modulesConfig() {
    read -a modulesList -d '\n' < <(ls modules/ | sort)

    for i in "${modulesList[@]}"
    do
        if [ -e "modules/$i" ] && checkModule ; then
            . "modules/$i" || 
                { commandFailure="Importing $i module has failed." ; die ; }
            modulesDialogArray+=("'$title' '$description' '$status'")
        fi
    done

    # Using dash here as a simple solution to it misbehaving when ran with bash
    modules=( $(sh -c "dialog --stdout --title 'Extra Options' --no-mouse --backtitle "https://github.com/kkrruumm/void-install-script" --checklist 'Enable or disable extra install options: ' 0 0 0 $(echo "${modulesDialogArray[@]}")") )
}

confirm() {

    drawDialog --yes-label "Install" --no-label "Exit" --extra-button --extra-label "Restart" --title "Confirm Installation Choices" --yesno "Selecting 'Install' here will DESTROY ALL DATA on the chosen partitions and install with the options below. \n\n
$settings\n
You can choose 'Restart' to go back to the beginning of the installer and change settings." 0 0

    case $? in
        0)
            return 0
            ;;
        1)
            exit 0
            ;;
        3)
            diskConfig
            ;;
        *)
            commandFailure="Invalid confirm settings exit code"
            failureCheck
            ;;
    esac
}

diskConfig
suConfig
kernelConfig
bootloaderConfig
hostnameConfig
userConfig
timezoneConfig
localeConfig
repositoryConfig
installConfig

[ "$profile" != "minimal" ] &&
    { graphicsConfig ; networkConfig ; audioConfig ; desktopConfig ; modulesConfig ; }

# Construct confirm menu
# I know this is a fucking mess, but it's better than the previous in-line logic.
[ "$basesystem" != "base-system" ] &&
    settings="Base system: custom\n"

settings+="Repo mirror: $repository\n"
settings+="Bootloader: $bootloader\n"
settings+="Kernel: $kernel\n"
settings+="Target disk: $diskInput\n"
settings+="Encryption: $encryption\n"

if [ "$encryption" == "Yes" ] && [ -n "$wipedisk" ]; then
    settings+="Disk wipe passes: $wipedisk\n"
elif [ "$encryption" == "Yes" ]; then
    settings+="Disk wipe passes: none\n"
fi

settings+="LVM: $lvm\n"
settings+="Filesystem: $filesystem\n"

if [ -n "$swapStyle" ]; then
    settings+="Swap style: $swapStyle\n"
    settings+="Swap size: $swapSize\n"
else
    settings+="Swap style: none\n"
fi

settings+="Root size: $rootSize\n"

[ -n "$homeSize" ] &&
    settings+="Home size: $homeSize"

settings+="Hostname: $hostname\n"
settings+="Timezone: $timezone\n"
settings+="Locale: $locale\n"

[ -n "$username" ] &&
    settings+="User: $username\n"

settings+="Profile: $profile\n"

[ -n "$modules" ] &&
    settings+="Enabled modules: ${modules[@]}\n"

if [ "$profile" == "desktop" ]; then
        [ -n "$desktop" ] &&
            settings+="DE/WM: $desktop\n"

        [ -n "$network" ] &&
            settings+="DHCP client: $network\n"

        [ -n "$audio" ] &&
            settings+="Audio server: $audio\n"

        [ -n "$graphics" ] &&
            settings+="Graphics drivers: $graphics\n"

        [ "$desktop" == "i3" ] && [ -n "$lightdm" ] &&
            settings+="Install lightdm with i3?: $lightdm"
fi

confirm

. "$(pwd)"/setup/setupdisk
. "$(pwd)"/setup/setupbase
. "$(pwd)"/setup/setupdesktop

commandFailure="System chroot has failed."
cp /etc/resolv.conf /mnt/etc/resolv.conf || die

syschrootVarPairs=("bootloader $bootloader" \
"su $su" \
"timezone $timezone" \
"encryption $encryption" \
"diskInput $diskInput" \
"username $username" \
"desktop $desktop" \
"esp $esp" \
"root $root" \
"swap $swap")

for i in "${syschrootVarPairs[@]}"
do
    set -- $i || die
    echo "$1='$2'" >> /mnt/tmp/installerOptions || die
done

cp -f "$(pwd)"/lib/libviss /mnt/tmp/libviss || die
cp -f "$(pwd)"/setup/setupchroot /mnt/tmp/setupchroot || die
chroot /mnt /bin/bash -c "/bin/bash /tmp/setupchroot" || die

clear

[ -z "$modules"  ] &&
    for i in ${modules[@]}
    do
        . "modules/$i" ||
            { commandFailure="Executing $i module has failed." ; die ; }
        main
    done

clear
echo -e "${GREEN}Installation complete.${NC}"
echo "Please remove installation media and reboot."
echo -e "Otherwise, you may run 'chroot /mnt' for further config.\n"
exit 0
