# void-install-script
TUI Shell script installer for Void Linux

This installer was primarily created to serve as an installer with encryption support while also having general installation options one would want, with sane defaults.

# Features
```
-Option to add user-created modules to be executed by the installer, see modules notes
-Included modules do various things, a few included ones:
--Option to enable system logging with socklog
--Option to install wifi firmware and basic utilities
--Option to install Flatpak with Flathub repository
--Option to install and preconfigure qemu and libvirt
--Option to install nftables with a default firewall config

-Option to choose between efistub and grub

-Option to encrypt installation disk
--With efistup setup, encryption will encrypt / using luks2
--With grub setup, encryption will encrypt both /boot and / using luks1

-Option to pre-install and pre-configure the following:
--Graphics drivers (amd, nvidia, intel, nvidia-nouveau, none)
--Networking (dhcpcd, NetworkManager, none)
--Audio server (pipewire, pulseaudio, none)
--DE or WM (gnome, kde, xfce, sway, swayfx, wayfire, i3, none)
--Or, choose to do none of these and install a bare-minimum system

-Option to choose between base-system and base-container base system meta packages
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

efistub setup will *not* provide full-disk-encryption as /boot will not be encrypted.

However, root will be encrypted using luks2 instead of luks1, since grub is no longer a constraint here.

Do keep in mind potential security issues regarding weaker key derivation functions, such as pbkdf2 which is used with luks1 here, rather than argon2id with luks2.

efistub *can* be a bit touchy on some (non entirely UEFI standards compliant) motherboards, though this doesn't seem to be much of a problem as long as we "trick" boards into not deleting the boot entry.

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

# Hidden installer options

There are a few options that aren't exposed directly to the user, but can be changed by creating a file that sets these variables and adding it as a flag when executing the installer.

Example: './installer.sh /path/to/file'

Such file would contain any or all of the following options, and the following examples are set to their default values:

```
acpi="true"
hash="sha512"
keysize="512"
itertime="10000"
```

The toggle for ACPI can be set to false if you are facing ACPI related issues. This will set the "acpi=off" kernel parameter on the new install. Do not change this setting unless absolutely necessary.

hash, keysize, and itertime are all variables that change the LUKS settings for encrypted installations.

I do not recommend changing hash and keysize from their default values unless you are absolutely certain you would like to. Research this before changing values.

itertime is a bit less strict. As a TL;DR, the higher this value is, the longer brute-forcing this drive should take. 

The value here will equal the amount of time it takes to unlock the drive in milliseconds calculated for the system this is ran on. If this drive is then put into a system with a faster CPU, it will unlock quicker.

The LUKS default is "2000", or 2 seconds. The default in this installer has been raised with systems that have slower CPUs (and users that are more security conscious) in mind.

The fips140 compliant value here would be 600000 according to owasp, though this would result in a 10 minute disk unlock time.

# Misc notes

This installer is not officially supported, and is still fairly work-in-progress. If you run into any problems please file them on this github page.

This installer only supports x86_64-efi. I currently have no plans to support anything else.

The base-system metapackage should be chosen in *most* scenarios, though using base-container provides a slightly more minimal install.

If you have found this script useful, do star this repository!

# Contributing

The best way to contribute to this would be to create a pull request adding the feature you would like.

If you would like a change to be made to the script, a request/suggestion in the issues tracker is also a wonderful place to start.

Niche requests for features that do not fit the scope of this installer are unlikely to be entertained, but do not hesitate to suggest ideas.

# TODO
```
-You tell me.
```
