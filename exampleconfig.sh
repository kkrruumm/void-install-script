#!/bin/bash

# This is a template config file used to define all of the variables the installer will ask for, to be taken as an example.
# The installer can be told to use the config file by running with ./installer.sh /path/to/myconfig.sh

diskInput="/dev/sda" # Define your install disk
swapPrompt="y" # Enable or disable swap (y/n)
swapInput="4G" # Define swap size
rootPrompt="full" # Define size of root partition, 'full' will consume the rest of the disk after bootloader and swap in this example. An example acceptable value would be '50G'
homePrompt="n" # Enable separate home partition (y/n) NOTE: If your root partition is set to 'full', having a separate home partition on the same disk is impossible.
homeInput="full" # Define size of home partition, an example acceptable value for this is '50G', 'full' will consume the rest of the disk after bootloader, swap, and root
encryptionPrompt="y" # Tells the installer if it should encrypt the installation (y/n)
wipePrompt="y" # Tells the installer if it should overwrite the disk with random data (y/n)
passInput="1" # Tells the installer how many times it should overwrite the disk with random data, only available if wipePrompt is set to 'y'
suChoice="doas" # Tells the installer if it should install 'sudo' or 'doas'
wifiChoice="n" # Tells the installer if it should install wifi firmware and utilities (iw, wpa_supplicant, wifi-firmware) (y/n)
kernelChoice="linux-lts" # Tells the installer which kernel it should install, another valid option here is 'linux'
bootloaderChoice="efistub" # Tells the installer which setup it should use to boot, another valid option here is 'grub'
fsChoice="xfs" # Tells the installer which filesystem it should setup, another valid option here is 'ext4'

hostnameInput="mothership" # Set the hostname of the computer you are installing to
timezonePrompt="America/New_York" # Set your timezone
installType="desktop" # Defines your install profile, desktop will allow things like graphics drivers, desktop environments, and otherwise to be set. Another acceptable value here is 'minimal' if you want a minimal install

# The following install options are ONLY available if you are using the desktop profile defined above.

graphicsChoice="amd" # Defines your graphics driver selection, acceptable values here include 'amd', 'intel', 'nvidia', and 'nvidia-optimus'; do note that nvidia drivers are incompatible with musl.
networkChoice="NetworkManager" # Defines your networking selection, another acceptable value here is 'dhcpcd'
audioChoice="pipewire" # Defines your audio server selection, acceptable values here include 'pipewire' and 'pulseaudio'
desktopChoice="gnome" # Defines your DE/WM selection, acceptable values here include 'gnome', 'kde', 'xfce', 'sway', and 'i3'
i3prompt="y" # Tells the installer if it should install lightdm with i3wm or not, this option is only available if desktopChoice is set to 'i3' (y/n)
logPrompt="y" # Tells the installer if it should setup socklog on the new system (y/n)
flatpakPrompt="y" # Tells the installer if it should install flatpak or not (y/n)

# If any of these values are not defined or set to 'skip', the installer will do nothing for said values.
