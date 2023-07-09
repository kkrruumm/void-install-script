#!/bin/bash -e
RED='\033[0;31m'
NC='\033[0m'

chown root:root / || failureCheck
chmod 755 / || failureCheck

failureCheck() {
    echo -e "${RED}$commandFailure${NC}"
    echo "Installation will not proceed."
    exit 1
}

userPassword() {
    echo "Set the password for the user $createUser:"
    passwd $createUser || userPassword

    commandFailure="XBPS Reconfigure has failed."
    xbps-reconfigure -fa || failureCheck

    clear

    echo -e "Installation complete. \n"
    echo -e "If you are ready to reboot into your new system, enter 'reboot now'. \n"

    exit 0
}

rootPassword() {
    echo "Set your root password:"
    passwd root || rootPassword

    if [ $createUser != "skip" ]; then
        userPassword
    fi

    commandFailure="XBPS Reconfigure has failed."
    xbps-reconfigure -fa || failureCheck

    clear

    echo -e "Installation complete. \n"
    echo -e "If you are ready to reboot into your new system, enter 'reboot now'. \n"

    exit 0
}

echo -e "Enabling all services... \n"

if test -e "/usr/share/applications/pipewire.desktop" ; then
    commandFailure="Pipewire configuration has failed."
    echo "Enabling Pipewire..."
    ln -s /usr/share/applications/pipewire.desktop /etc/xdg/autostart/pipewire.desktop || echo -e "Autostart dir does not appear to exist... "
    ln -s /usr/share/applications/pipewire-pulse.desktop /etc/xdg/autostart/pipewire-pulse.desktop || echo -e "Autostart dir does not appear to exist... \n"
    ln -s /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d || failureCheck
    ln -s /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d || failureCheck
fi

commandFailure="Enabling all services has failed."

services=(gdm dbus sddm lightdm socklog-unix nanoklogd)

for i in "${services[@]}"
do
    if test -e "/etc/sv/$i" ; then
        echo -e "Enabling $i..."
        ln -s /etc/sv/$i /var/service || failureCheck
    fi
done

networkChoice=$(cat /tmp/networking)
if [ $networkChoice == "NetworkManager" ]; then
    echo "Enabling NetworkManager..."
    ln -s /etc/sv/NetworkManager /var/service || failureCheck
elif [ $networkChoice == "dhcpcd" ]; then
    echo "Enabling dhcpcd..."
    ln -s /etc/sv/dhcpcd /var/service || failureCheck
fi

if test -e "/bin/sway" ; then
    echo "Enabling elogind..."
    ln -s /etc/sv/elogind /var/service || failureCheck
fi

if test -e "/usr/bin/flatpak" ; then
    commandFailure="Adding flatpak repository has failed."
    echo -e "Adding flathub repo for flatpak... \n"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || failureCheck
fi

if test -e "/dev/mapper/void-home" ; then
    commandFailure="Mounting home directory has failed."
    mount /dev/mapper/void-home /home || failureCheck
fi

encryptionPrompt=$(cat /tmp/encryption)
bootloaderChoice=$(cat /tmp/bootChoice)
diskInput=$(cat /tmp/installDrive)

if [[ $diskInput == /dev/nvme* ]] || [[ $diskInput == /dev/mmcblk* ]]; then
    partition1="$diskInput"p1
    partition2="$diskInput"p2
else
    partition1="$diskInput"1
    partition2="$diskInput"2
fi

partVar=$(blkid -o value -s UUID $partition2)

if [ $encryptionPrompt == "y" ] || [ $encryptionPrompt == "Y" ]; then
    if [ $bootloaderChoice == "grub" ]; then
        commandFailure="Configuring LUKS key has failed."

        echo -e "Configuring LUKS key... \n"

        dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key || failureCheck
        echo -e "Enter your encryption passphrase: \n" || failureCheck
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

timezonePrompt=$(cat /tmp/selectTimezone)
commandFailure="Setting timezone has failed."
ln -sf /usr/share/zoneinfo/$timezonePrompt /etc/localtime || failureCheck
    
clear

suChoice=$(cat /tmp/suChoice)
if [ $suChoice == "doas" ]; then
    commandFailure="doas configuration has failed."
    touch /etc/doas.conf || failureCheck
    chown -c root:root /etc/doas.conf || failureCheck
    chmod -c 0400 /etc/doas.conf || failureCheck
    ln -s $(which doas) /usr/bin/sudo || failureCheck
fi

clear

echo -e "If you would like to create a new user, enter a username here. \n"
echo -e "If you do not want to add a user now, enter 'skip' \n"
read createUser

if [ $createUser == "skip" ]; then
    clear    
    rootPassword
else
    commandFailure="Creating user has failed."
    useradd $createUser -m -d /home/$createUser || failureCheck
    usermod -aG audio,video,input,kvm $createUser || failureCheck
    clear
    echo -e "Should user $createUser be a superuser? (y/n) \n"
    read superPrompt

    if [ $superPrompt == "y" ] || [ $superPrompt == "Y"]; then
        usermod -aG wheel $createUser || failureCheck
        if [ $suChoice == "sudo" ]; then
            sed -i -e 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers || failureCheck
        elif [ $suChoice == "doas" ]; then
            echo "permit :wheel" >> /etc/doas.conf || failureCheck
        fi
    fi

    clear

    rootPassword

fi
