# void-install-script
Shell script installer for Void Linux

This installer was primarily created to serve as an installer with encryption support while also having general installation options one would want, with sane defaults.

# Features
```
-Experimental efistub support, see efistub notes

-Option to add user-created modules to be executed by the installer, see modules notes
-Included modules do various things, a few included ones:
--Option to raise vm.max_map_count
--Option to enable system logging with socklog
--Option to install wifi firmware and basic utilities
--Option to install Flatpak with Flathub repository
--Option to install and preconfigure qemu and libvirt
--Option to install nftables with a default firewall config
--Option to enable esync by raising user ulimit

-Option to encrypt installation disk
--With efistup setup, encryption will encrypt / using luks2
--With grub setup, encryption will encrypt both /boot and / using luks1

-Option to pre-install and pre-configure the following;
--Graphics drivers (amd, nvidia, intel, nvidia-optimus, none)
--Networking (dhcpcd, NetworkManager, none)
--Audio server (pipewire, pulseaudio, none)
--DE or WM (gnome, kde, xfce, sway, i3, none)
--Or, choose to do none of these and install a bare-minimum system

-Option to securely erase the installation disk with shred
-Option to choose either doas or sudo
-Option to choose your repository mirror
-Option to choose between linux, linux-lts, and linux-mainline kernels
-Option to choose between xfs and ext4 filesystems
-Configure partitions in the installer for home, swap, and root with LVM
-Support for both glibc and musl
-User creation and basic configuration
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

# efistub notes

efistub support should be considered experimental as of right now.

efistub setup will *not* provide full-disk-encryption as /boot will not be encrypted.

However, root will be encrypted using luks2 instead of luks1, since grub is no longer a constraint here.

This setup would be very well complimented by secure boot.

# Modules notes

A barebones "module" system has been added to the installer to make adding misc features simpler and more organized.

To create a module, create a file in the 'modules' directory that comes with this installer, its name should be the title of your module.

Then, add at minimum the 3 required variables and 1 required function to this file.
If any of the 3 required variables or the 1 required function are missing, the installer will not import the module.

Example module file contents:

```
title=nameofmymodule
description="- This module does XYZ"
status=off

main() {
    # Do cool stuff here
}
```

The title variable here will both be the name of the entry in the TUI, but also the name of the file the installer will look for.

The description variable will be the extra information given to the user in the TUI along with the option and can be left empty, but must exist.

The status variable tells the installer whether or not the module should be enabled or disabled by default, valid values are on/off.

Inside of the main() function, you're free to add any commands you'd like to be executed, and you can access all variables set by the primary install script.



That's it!

Feel free to check out some of the installers included modules for further example.

# Misc notes

This installer is not officially supported, and is still fairly work-in-progress. If you run into any problems please file them on this github page.

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
