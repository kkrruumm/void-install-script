# void-install-script
WIP Shell script installer for Void Linux

This installer was primarily created to serve as an installer with encryption support while also having general installation options one would want, with sane defaults.

# Features
```
-Experimental efistub support, see efistub notes

-Option to encrypt installation disk
--With efistup setup, encryption will encrypt / using luks2 defaults
--With grub setup, encryption will encrypt both /boot and / using luks1 defaults

-Option to pre-install and pre-configure the following;
--Graphics drivers (amd, nvidia, intel, nvidia-optimus, none)
--Networking (dhcpcd, NetworkManager, none)
--Audio server (pipewire, pulseaudio, none)
--DE or WM (gnome, kde, xfce, sway, i3, none)
--System logging with socklog
--Flatpak
--Or, choose to do none of these and install a bare-minimum system

-Option to securely erase the installation disk with shred
-Option to choose either doas or sudo
-Option to choose your repository mirror
-Option to choose between linux, linux-lts, and linux-mainline kernels
-Option to install wifi firmware and basic utilities
-Option to choose between xfs and ext4 filesystems
-Configure partitions in the installer for home, swap, and root with LVM
-Support for both glibc and musl libc implementations
-User creation and basic configuration
-Config support
```

# Instructions
```
Boot into a Void Linux live medium
Login as anon
sudo xbps-install -S git
git clone https://github.com/kkrruumm/void-install-script/
cd void-install-script
chmod +x installer.sh
sudo ./installer.sh
Follow on-screen steps
Done.
```
# Config usage
```
If you want to use the config feature, run the installer with ./installer.sh /path/to/myconfig.sh
Take a look at exampleconfig.sh for usage.

This feature is very barebones at the moment, and is in need of some work.
```

# efistub notes

efistub support should be considered experimental as of right now.

efistub setup will *not* provide full-disk-encryption as /boot will not be encrypted.

However, root will be encrypted using luks2 defaults instead of luks1, since grub is no longer a constraint here.

This setup would be very well complimented by secure boot.

# Notes

This installer is not officially supported, and is very work-in-progress. If you run into any problems please file them on this github page.

This installer only supports x86_64-efi. I currently have no plans to support anything else.

If you have found this script useful, do star this repository!


# Contributing

The best way to contribute to this would be to find ways to break the installer.

If you would like a change to be made to the script, a request/suggestion in the issues tracker is a wonderful place to start.

Niche requests for features that do not fit the scope of this installer are unlikely to be entertained, but do not hesitate to suggest ideas.


# TODO
```
-You tell me.
```
