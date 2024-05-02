#!/bin/bash -e
RED='\033[0;31m'
YELLOW='\e[1;33m'
NC='\033[0m'

failureCheck() {
    echo -e "${RED}$commandFailure${NC}"
    echo "Installation will not proceed."
    exit 1
}

exitFunction () {
    commandFailure="XBPS Reconfigure has failed."
    xbps-reconfigure -fa || failureCheck

    if [ $bootloaderChoice == "efistub" ]; then
        # We need to set our efistub boot entry as the default one to boot, or it seems that some systems will just ignore it.
        commandFailure="Setting default boot entry has failed."
        bootEntry=$(efibootmgr --unicode | grep "Void Linux with kernel" | while read c1 c2; do echo $c1; done | sed 's/Boot//g' | sed 's/*//g') || failureCheck
        efibootmgr --bootorder $bootEntry || failureCheck
    fi

    exit 0

}

userPassword() {
    echo -e "${YELLOW}Set the password for the user $createUser: ${NC}"
    passwd $createUser || userPassword

    exitFunction
}

rootPassword() {
    echo -e "${YELLOW}Set your root password: ${NC}"
    passwd root || rootPassword

    if [ -n "$createUser" ]; then
        userPassword
    fi

    exitFunction
}

commandFailure="Sourcing installer variable file on new system has failed."
if [ ! -e "/tmp/installerOptions" ]; then
    failureCheck
else
    . /tmp/installerOptions || failureCheck
fi

commandFailure="Setting root directory permissions has failed."
chown root:root / || failureCheck
chmod 755 / || failureCheck

echo -e "Enabling all services... \n"

if [ -e "/usr/share/applications/pipewire.desktop" ] && [ -e "/etc/xdg/autostart/" ]; then
    commandFailure="Pipewire configuration has failed."
    echo -e "Enabling Pipewire... \n"
    ln -s /usr/share/applications/pipewire.desktop /etc/xdg/autostart/pipewire.desktop || failureCheck 
    ln -s /usr/share/applications/pipewire-pulse.desktop /etc/xdg/autostart/pipewire-pulse.desktop || failureCheck
else
    echo -e "Cannot enable pipewire via DE autostart. This is likely not an error. \n"
fi

if [ -e "/usr/share/alsa/alsa.conf.d/50-pipewire.conf" ] && [ -e "/usr/share/alsa/alsa.conf.d/99-pipewire-default.conf" ]; then
    commandFailure="Pipewire configuration has failed."
    ln -s /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d || failureCheck
    ln -s /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d || failureCheck
fi

if [ -e /etc/sv/dbus ]; then
    commandFailure="Enabling dbus has failed."
    ln -s /etc/sv/dbus /var/service || failureCheck
fi

if [ -e "/dev/mapper/void-home" ]; then
    commandFailure="Mounting home directory has failed."
    mount /dev/mapper/void-home /home || failureCheck
fi

if [[ $diskInput == /dev/nvme* ]] || [[ $diskInput == /dev/mmcblk* ]]; then
    partition1="$diskInput"p1
    partition2="$diskInput"p2
else
    partition1="$diskInput"1
    partition2="$diskInput"2
fi

partVar=$(blkid -o value -s UUID $partition2)

if [ $encryptionPrompt == "Yes" ]; then
    if [ $bootloaderChoice == "grub" ]; then
        commandFailure="Configuring LUKS key has failed."

        echo -e "Configuring LUKS key... \n"

        dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key || failureCheck
        echo -e "${YELLOW}Enter your encryption passphrase: ${NC}\n" || failureCheck
        cryptsetup luksAddKey $partition2 /boot/volume.key || failureCheck
        chmod 000 /boot/volume.key || failureCheck
        chmod -R g-rwx,o-rwx /boot || failureCheck

        echo "void   UUID=$partVar   /boot/volume.key   luks" >> /etc/crypttab || failureCheck
        touch /etc/dracut.conf.d/10-crypt.conf || failureCheck
        dracutConf='install_items+=" /boot/volume.key /etc/crypttab "' || failureCheck
        echo "$dracutConf" >> /etc/dracut.conf.d/10-crypt.conf || failureCheck

        echo "LUKS key configured."
    elif [ $bootloaderChoice == "efistub" ]; then
        commandFailure="Configuring crypttab has failed."
        echo -e "Configuring crypttab... \n"
        echo "void        UUID=$partVar  none   luks" >> /etc/crypttab || failureCheck
    fi
fi

if [ $bootloaderChoice == "efistub" ]; then
    # Symlink to tell dracut to mount all filesystems listed
    commandFailure="Dracut fstab symlink has failed."
    ln -s /etc/fstab /etc/fstab.sys || failureCheck
elif [ $bootloaderChoice == "grub" ]; then
    echo -e "Running grub-install... \n"
    commandFailure="GRUB installation has failed."

    grub-install --removable --target=x86_64-efi --efi-directory=/boot/efi || failureCheck
fi

clear

commandFailure="Setting timezone has failed."
ln -sf /usr/share/zoneinfo/$timezonePrompt /etc/localtime || failureCheck
    
clear

if [ $suChoice == "doas" ]; then
    commandFailure="doas configuration has failed."
    touch /etc/doas.conf || failureCheck
    chown -c root:root /etc/doas.conf || failureCheck
    chmod -c 0400 /etc/doas.conf || failureCheck
    ln -s $(which doas) /usr/bin/sudo || failureCheck
fi

if [ -z "$createUser" ]; then
    clear    
    rootPassword
else
    commandFailure="Creating user has failed."
    useradd $createUser -m -d /home/$createUser || failureCheck
    usermod -aG audio,video,kvm $createUser || failureCheck
    clear
    echo -e "Should user $createUser be a superuser? (y/n) \n"
    read superPrompt

    if [ $superPrompt == "y" ] || [ $superPrompt == "Y" ]; then
        usermod -aG wheel $createUser || failureCheck
        if [ $suChoice == "sudo" ]; then
            sed -i -e 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers || failureCheck
        elif [ $suChoice == "doas" ]; then
            echo "permit :wheel" >> /etc/doas.conf || failureCheck
        fi
    fi

    case $desktopChoice in
        wayfire)
            # Modify default wayfire terminal after the user has been created
            echo -e "Modifying default wayfire terminal... \n"
            commandFailure="Changing Wayfire config has failed."
            if [ ! -d /home/$createUser/.config ]; then
                mkdir /home/$createUser/.config || failureCheck
            fi
            cp /usr/share/examples/wayfire/wayfire.ini /home/$createUser/.config/wayfire.ini || failureCheck
            sed -i -e 's/command_terminal = alacritty/command_terminal = foot/g' /home/$createUser/.config/wayfire.ini || failureCheck
            chown -Rf $createUser:$createUser /home/$createUser/.config || failureCheck
            ;;

        gnome)
            # Cursed fix for gdm not providing a Wayland option if the Nvidia driver is in use, found here: https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver
            echo -e "Modifying udev rules for gdm... \n"
            commandFailure="Modifying udev rules for gdm has failed."
            if [ -e /usr/bin/nvidia-smi ]; then
                if [ ! -d /etc/udev/rules.d ]; then
                    mkdir -p /etc/udev/rules.d || failureCheck
                fi
                ln -s /dev/null /etc/udev/rules.d/61-gdm.rules || failureCheck
            fi
            ;;
    esac

    clear

    rootPassword

fi
