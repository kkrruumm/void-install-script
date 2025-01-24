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

drawDialog --msgbox "Welcome!\n\nThis is primarily a guided installer, but at any moment you may press the 'Map' button to jump around the installer in a non-linear way, or to go back and change settings.\n\nYou may use your TAB key, arrow keys, and Enter/Return to navigate this TUI.\n\nPressing Enter now will begin the installation process, but no changes will be made to the disk until you confirm your installation settings." 0 0

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

    if drawDialog --title "Partitioner - Encryption" --extra-button --extra-label "Map" --yesno "Should this installation be encrypted?" 0 0 ; then
        encryption="Yes"
        drawDialog --title "Partitioner - Wipe Disk" --yesno "Would you like to securely wipe the selected disk before setup?\n\nThis can take quite a long time depending on how many passes you choose.\n\nBe aware that doing this on an SSD is likely a bad idea." 0 0 &&
            wipedisk=$(drawDialog --title "Partitioner - Wipe Disk" --inputbox "How many passes would you like to do on this disk?\n\nSane values include 1-3. The more passes you choose, the longer this will take." 0 0)
    else
        [ "$?" == "3" ] && dungeonmap
        encryption="No"
    fi

    if drawDialog --title "Partitioner - LVM" --extra-button --extra-label "Map" --yesno "Would you like to use LVM?" 0 0 ; then
        lvm="Yes"
    else
        [ "$?" == "3" ] && dungeonmap
        lvm="No"
    fi

    if drawDialog --title "Disk Details" --extra-button --extra-label "Map" --no-cancel --title "Partitioner - Swap" --yesno "Would you like to use swap?" 0 0 ; then
        if [ "$lvm" == "Yes" ] || [ "$encryption" == "No" ]; then
            swapStyle=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --menu "What style of swap would you like to use?\n\nIf you are unsure, 'swapfile' is recommended." 0 0 0 "swapfile" "- On-filesystem swapfile" "zram" "- RAM in your RAM, but smaller" "partition" "- Traditional swap partition")
        else
            swapStyle=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --menu "What style of swap would you like to use?\n\nIf you are unsure, 'swapfile' is recommended." 0 0 0 "swapfile" "- On-filesystem swapfile" "zram" "- RAM in your RAM, but smaller")
        fi
    else
        [ "$?" == "3" ] && dungeonmap
    fi

    case "$swapStyle" in
        swapfile) swapSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --inputbox "How large would you like your swapfile to be?\n(Example: '4G')" 0 0) ;;
        zram) swapSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --inputbox "How large would you like your compressed ramdisk to be?\n(Example: '4G')" 0 0) ;;
        partition)
            swapSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Swap" --inputbox "How large would you like your swap partition to be?\n(Example: '4G')" 0 0)
            local sizeInput=$swapSize && diskCalculator && local diskIndicator=$(partitionerOutput)
        ;;
    esac

    rootSize=$(drawDialog --begin 2 2 --title "Disk Details" --extra-button --extra-label "Map" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Root" --inputbox "If you would like to limit the size of your root filesystem, such as to have a separate home partition, you can enter a value such as '50G' here.\n\nOtherwise, if you would like your root partition to take up the entire drive, enter 'full' here." 0 0)
    [ "$?" == "3" ] && dungeonmap

    if [ "$rootSize" == "full" ]; then
        local separateHomePossible="No"
    elif [ "$lvm" == "No" ] && [ "$encryption" == "Yes" ]; then
        local separateHomePossible="No"
    else
        local sizeInput=$rootSize && diskCalculator && local diskIndicator=$(partitionerOutput)
    fi

    [ "$separateHomePossible" != "No" ] &&
        if drawDialog --title "Partitioner - Home" --extra-button --extra-label "Map" --yesno "Would you like to have a separate home partition?" 0 0 ; then
            homeSize=$(drawDialog --begin 2 2 --title "Disk Details" --infobox "$diskIndicator" 0 0 --and-widget --no-cancel --title "Partitioner - Home" --inputbox "How large would you like your home partition to be?\n(Example: '100G')\n\nYou can choose to use the rest of your disk after the root partition by entering 'full' here." 0 0)
        else
            [ "$?" == "3" ] && dungeonmap
        fi

    filesystem=$(drawDialog --no-cancel --title "Partitioner - Filesystem" --extra-button --extra-label "Map" --menu "If you are unsure, choose 'ext4'" 0 0 0 "ext4" "" "xfs" "")
    [ "$?" == "3" ] && dungeonmap

    suConfig
}

suConfig() {
    su=$(drawDialog --no-cancel --title "SU Choice" --extra-button --extra-label "Map" --menu "If you are unsure, choose 'sudo'" 0 0 0 "sudo" "" "doas" "" "none" "")
    [ "$?" == "3" ] && dungeonmap

    kernelConfig
}

kernelConfig() {
    kernel=$(drawDialog --no-cancel --title "Kernel Choice" --extra-button --extra-label "Map" --menu "If you are unsure, choose 'linux'" 0 0 0 "linux" "- Normal Void kernel" "linux-lts" "- Older LTS kernel" "linux-mainline" "- Bleeding edge kernel")
    [ "$?" == "3" ] && dungeonmap

    bootloaderConfig
}

bootloaderConfig() {
    bootloader=$(drawDialog --no-cancel --title "Bootloader choice" --extra-button --extra-label "Map" --menu "If you are unsure, choose 'grub'" 0 0 0 "grub" "- Traditional bootloader" "uki" "- Unified Kernel Image" "none" "- Installs no bootloader (Advanced)")
    [ "$?" == "3" ] && dungeonmap

    hostnameConfig
}

hostnameConfig() {
    hostname=$(drawDialog --no-cancel --title "System Hostname" --extra-button --extra-label "Map" --inputbox "Set your system hostname." 0 0)
    [ "$?" == "3" ] && dungeonmap

    userConfig
}

userConfig() {
    username=$(drawDialog --title "Create User" --extra-button --extra-label "Map" --inputbox "What would you like your username to be?\n\nIf you do not want to set a user here, choose 'Skip'\n\nYou will be asked to set a password later." 0 0)
    [ "$?" == "3" ] && dungeonmap

    timezoneConfig
}

timezoneConfig() {
    # Most of this timezone section is taken from the normal Void installer.
    local areas=(Africa America Antarctica Arctic Asia Atlantic Australia Europe Indian Pacific)
    if area=$(IFS='|'; drawDialog --no-cancel --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${areas[@]}")) ; then
        read -a locations -d '\n' < <(find /usr/share/zoneinfo/$area -type f -printf '%P\n' | sort) || echo "Disregard exit code"
        local location=$(IFS='|'; drawDialog --no-cancel --title "Set Timezone" --menu "" 0 0 0 $(printf '%s||' "${locations[@]//_/ }"))
    fi
    local location=$(echo $location | tr ' ' '_')
    timezone="$area/$location"

    localeConfig
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

    repositoryConfig
}

repositoryConfig() {
    if drawDialog --title "Repository Mirror" --extra-button --extra-label "Map" --yesno "Would you like to set your repo mirror?\n\nIf not, repo-default will be used." 0 0 ; then
        xmirror
        repository=$(cat /etc/xbps.d/*-repository-main.conf | sed 's/repository=//g')
    else
        [ "$?" == "3" ] && dungeonmap
        [ "$libc" == "glibc" ] && repository="https://repo-default.voidlinux.org/current"
        [ "$libc" == "musl" ] && repository="https://repo-default.voidlinux.org/current/musl"
    fi

    [ "$libc" == "glibc" ] && ARCH="x86_64"
    [ "$libc" == "musl" ] && ARCH="x86_64-musl"

    graphicsConfig
}

graphicsConfig() {
    if [ "$libc" == "glibc" ]; then
        graphics=$(drawDialog --title 'Graphics Drivers' --extra-button --extra-label "Map" --checklist 'Select graphics drivers, or choose 'Skip' if you would like to skip:' 0 0 0 'intel' '' 'off' 'intel-32bit' '' 'off' 'amd' '' 'off' 'amd-32bit' '' 'off' 'nvidia' '- Proprietary driver' 'off' 'nvidia-32bit' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau driver (experimental)' 'off' 'nvidia-nouveau-32bit' '' 'off')
        [ "$?" == "3" ] && dungeonmap
    fi

    if [ "$libc" == "musl" ]; then
        graphics=$(drawDialog --title 'Graphics Drivers' --extra-button --extra-label "Map" --checklist 'Select graphics drivers, or choose 'Skip' if you would like to skip: ' 0 0 0 'intel' '' 'off' 'amd' '' 'off' 'nvidia-nouveau' '- Nvidia Nouveau driver (experimental)' 'off')
        [ "$?" == "3" ] && dungeonmap
    fi

    [ -n "$graphics" ] &&
        IFS=" " read -r -a graphicsArray <<< "$graphics"

    networkConfig
}

networkConfig() {
    network=$(drawDialog --no-cancel --title "Networking - DHCP client" --extra-button --extra-label "Map" --menu "If you are unsure, choose 'NetworkManager'\n\nIf 'none' is chosen, dhcpcd will still be included but not enabled." 0 0 0 "NetworkManager" "" "dhcpcd" "" "none" "")
    [ "$?" == "3" ] && dungeonmap

    audioConfig
}

audioConfig() {
    audio=$(drawDialog --no-cancel --title "Audio Server" --extra-button --extra-label "Map" --menu "If you are unsure, 'pipewire' is recommended." 0 0 0 "pipewire" "" "pulseaudio" "" "none" "")
    [ "$?" == "3" ] && dungeonmap

    desktopConfig
}

desktopConfig() {
    desktop=$(drawDialog --no-cancel --title "Desktop Environment" --extra-button --extra-label "Map" --menu "" 0 0 0 "gnome" "" "kde" "" "xfce" "" "sway" "" "swayfx" "" "wayfire" "" "i3" "" "none" "")
    [ "$?" == "3" ] && dungeonmap

    case "$desktop" in
        sway) drawDialog --extra-button --extra-label "Map" --msgbox "Sway will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in on the new installation." 0 0 ;;
        swayfx) drawDialog --extra-button --extra-label "Map" --msgbox "SwayFX will have to be started manually on login. This can be done by entering 'dbus-run-session sway' after logging in on the new installation." 0 0 ;;
        wayfire) drawDialog --extra-button --extra-label "Map" --msgbox "Wayfire will have to be started manually on login. This can be done by entering 'dbus-run-session wayfire' after logging in on the new installation." 0 0 ;;
        i3) drawDialog --title "" --extra-button --extra-label "Map" --yesno "Would you like to install lightdm with i3?" 0 0 && lightdm="Yes" ;;
    esac

    modulesConfig
}

modulesConfig() {
    # Unset to prevent duplicates
    [ -n "$modules" ] &&
        unset modulesDialogArray

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
    modules=( $(sh -c "dialog --stdout --title 'Extra Options' --extra-button --extra-label "Map" --no-mouse --backtitle "https://github.com/kkrruumm/void-install-script" --checklist 'Enable or disable extra install options: ' 0 0 0 $(echo "${modulesDialogArray[@]}")") )
    [ "$?" == "3" ] && dungeonmap

    confirm
}

confirm() {

    # Unset to prevent duplicates
    [ -n "$settings" ] &&
        unset settings

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
        settings+="Home size: $homeSize\n"

    settings+="Hostname: $hostname\n"
    settings+="Timezone: $timezone\n"
    settings+="Locale: $locale\n"

    [ -n "$username" ] &&
        settings+="User: $username\n"

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

    [ -n "$modules" ] &&
        settings+="Enabled modules: ${modules[@]}\n"

    drawDialog --yes-label "Install" --no-label "Exit" --extra-button --extra-label "Map" --title "Installation Overview" --yesno "Selecting 'Install' here will DESTROY ALL DATA on the chosen disk and install with the options below. \n\n
$settings\n
You can choose 'Restart' to go back to the beginning of the installer and change settings." 0 0

    case $? in
        0)
            _install
        ;;
        1)
            exit 0
        ;;
        3)
            dungeonmap
        ;;
    esac
}

dungeonmap() {
    waypoint=$(drawDialog --no-cancel --title "Dungeon Map" --menu "Choose a section to jump to:" 0 0 0 "Disk" "" "SU" "" "Kernel" "" "Bootloader" "" "Hostname" "" "User" "" "Timezone" "" "Locale" "" "Repository" "" "Graphics" "" "Network" "" "Audio" "" "Desktop" "" "Modules" "" "Overview" "")

    case "$waypoint" in
        Disk) diskConfig ;;
        SU) suConfig ;;
        Kernel) kernelConfig ;;
        Bootloader) bootloaderConfig ;;
        Hostname) hostnameConfig ;;
        User) userConfig ;;
        Timezone) timezoneConfig ;;
        Locale) localeConfig ;;
        Repository) repositoryConfig ;;
        Graphics) graphicsConfig ;;
        Network) networkConfig ;;
        Audio) audioConfig ;;
        Desktop) desktopConfig ;;
        Modules) modulesConfig ;;
        Overview) confirm ;;
    esac
}

_install() {
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
}

diskConfig
