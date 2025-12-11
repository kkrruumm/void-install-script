# void-install-script
TUI Shell script installer for Void Linux

This installer was primarily created to serve as an installer with encryption support while also having general installation options one would want, with sane defaults.

The overall goal of this installer is to deploy a system that is ready to use as soon as the installer exits.

At the moment, this installer does not have stable releases. The most recent commit should be considered the most recent stable release. Of course, if you run into bugs, please create an issue. (Or, if you're inclined, create a pull request to fix it.)

This script is not officially supported. Any issues should be filed here as opposed to any official Void Linux support area- if you're not sure if the issue you're facing stems from this installer, it would be best to create an issue on this repository before asking in the Void IRC or making a post on the subreddit.

![TUI Image](https://github.com/kkrruumm/void-install-script/blob/main/images/tuiscreenshot.png)

# Features
```
-Option to add user-created modules to be executed by the installer, see modules notes
-Included modules do various things, a few included ones:
--Option to enable system logging with socklog
--Option to install wifi firmware and basic utilities
--Option to install Flatpak with Flathub repository
--Option to install and preconfigure qemu and libvirt
--Option to install nftables with a default firewall config
--Various security related modules

-Option to choose between grub, zfsbootmenu (with zfs only), and UKI to boot the system
-Option to choose between dracut and tinyramfs (without zfs) initramfs generators

-Option to encrypt installation disk
--With UKI setup, encryption will encrypt both /boot and / using luks2
--With grub setup, encryption will encrypt both /boot and / using luks1

-Option to pre-install and pre-configure the following:
--Graphics drivers (amd, nvidia, intel, nvidia-nouveau, none)
--Networking (dhcpcd, NetworkManager, none)
--Audio server (pipewire, pulseaudio, none)

--DE or WM (gnome, i3, kde, mate, niri, river, sway, swayfx, wayfire, xfce, none)
---With i3, there is an option to install lightdm
---With sway, swayfx, wayfire, and niri there is an option to install greetd

--Or, choose to do none of these and install a bare-minimum system

-Option to choose between xfs, ext4, zfs, and btrfs filesystems

-Option to choose between LVM and a traditional install
-Option to choose between zram, swap partition, and normal swapfile
-Option to securely erase the installation disk with shred
-Option to choose between doas or sudo
-Option to choose your repository mirror
-Option to choose between linux, linux-lts, and linux-mainline kernels
-Configure partitions in the installer for home, swap, and root with LVM
-Support for both glibc and musl
-User creation and basic configuration
-Custom post_install functionality
```

# Instructions

1. Boot into a Void Linux live medium
2. Login as `anon` with password `voidlinux`
3. Run the following commands:
    - `sudo xbps-install -Su`
    - `sudo xbps-install -S git`
    - `git clone https://github.com/kkrruumm/void-install-script.git`
    - `cd void-install-script`
    - `sudo ./viss`
4. Follow on-screen steps
5. Done.

# UKI notes

UKI setup *will* provide full-disk-encryption as both / and /boot will be encrypted with luks2.

Do keep in mind potential security issues regarding weaker key derivation functions, such as pbkdf2 which is used with luks1, rather than argon2id with luks2.

UKIs *can* both be a bit touchy on some (non entirely UEFI standards compliant) motherboards, though this doesn't seem to be much of a problem as long as we "trick" boards into not deleting the boot entry.

The default UKI location is ``/boot/efi/EFI/boot/bootx64.efi``, and it is recommended to leave it in this location so as to not have to regenerate the boot entry with efibootmgr, but also to maintain compatibility with spotty UEFI implementations.

With UKIs, kernel parameters are set in ``/etc/kernel.d/post-install/60-ukify``, to update these, modify this file and run a reconfigure on your kernel.

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

If the module script requires a certain value that may or may not be set by the user, you may check if this variable is set at the top of the module file, and return 1 if it is not. If a module returns 1, it will not be shown in the modules menu. The esync module is an example of this as it requires a username in order to function.

If your module changes kernel parameters, and you make use of the setKernelParam wrapper function, the installer will automatically run ``update-grub`` or rebuild the UKI once all of the modules have run.

That's it!

Feel free to check out some of the installers included modules for further example.

# Hidden installer options

There are a few options that aren't exposed directly to the user because they can potentially be dangerous, but can be changed by creating a file that sets these variables and adding it as a flag when executing the installer.

This feature is also how one may define a `post_install` function to run whatever commands they like as the final thing the installer does.

Example: 
```
./installer.sh /path/to/file
```

Such file would contain any or all of the following options, and the following examples are set to their default values:

```
acpi="true"
intel_pstate="true"
hash="sha512"
keysize="512"
itertime="10000"
zfsiters="1000000"
basesystem="base-system" # Define base system packages instead of using metapackage
initrdhostonly="false"

post_install() {
    # do post-install stuff here
}
```

If none of these variables are set in the file, or no file is provided, the above defaults will be used.

- The toggle for ACPI can be set to false if you are facing ACPI related issues. This will set the `acpi=off` kernel parameter on the new install. Do not change this setting unless absolutely necessary.

- The toggle for `intel_pstate` can be set to false if you would like to disable intels power management. This is particularly useful on laptops to gain access to the "ondemand" governor and otherwise. This will set the `intel_pstate=disable` kernel parameter on the new install.

- `hash`, `keysize`, and `itertime` are all variables that change the LUKS settings for encrypted installations.

I do not recommend changing hash and keysize from their default values unless you are absolutely certain you would like to. Research this before changing values.

itertime is a bit less strict. As a TL;DR, the higher this value is, the longer brute-forcing this drive should take. 

The value here will equal the amount of time it takes to unlock the drive in milliseconds calculated for the system this is ran on. If this drive is then put into a system with a faster CPU, it will unlock quicker.

The LUKS default is "2000", or 2 seconds. The default in this installer has been raised with systems that have slower CPUs (and users that are more security conscious) in mind.

The fips140 compliant value here would be 600000 according to owasp, though this would result in a 10 minute disk unlock time.

- `zfsiters` sets the specific amount of iterations for the pbkdf2 kdf used by ZFS, as ZFS does not have a built in way to calculate this based on the amount of time the user would like to wait. Raise or lower as desired, with the same implications as itertime with LUKS.

- `initrdhostonly` will instruct the initramfs generator to generate a host-specific initramfs image when set to `true`.

- The `post_install` function may be defined if the user would like to run custom commands once installation has completed.

This function does not need to be defined, but if it is, this will be the last task the installer handles. This function has access to all of the variables defined by the installer, and has access to wrapper commands such as `system`, `install`, and `setKernelParam`.

A cool thing that could be done with this file (and as part of this post_install function) is switching based on which device the installer is being run on, do see [my file](https://github.com/kkrruumm/void-basesystem) for an example of this.

Outside of options that are potentially dangerous, "random" features that do not fit elsewhere can be added via this.

# zfs notes

ZFS support in this installer is considered highly experimental, and testing is needed. The deployed setup is likely to change over time.

If you would like to use ZFS, grab the [hrmpf](https://github.com/leahneukirchen/hrmpf/releases) ISO as detailed in the Void Linux [documentation](https://docs.voidlinux.org/installation/guides/zfs.html#installation-media), which includes the necessary things to deploy ZFS by default. Alternatively, one may build a Void Linux ISO manually that includes ZFS.

This installer is tested against the latest hrmpf image, and is the expected and recommended ISO to use when deploying ZFS.

For the time being, the only supported boot setup with ZFS is via [zfsbootmenu](https://github.com/zbm-dev/zfsbootmenu).

The only supported encryption setup is via ZFS native encryption, as zbm is currently unable to handle luks in this context by default. However, there are some [implications](https://forums.truenas.com/t/truenas-zfs-encryption-deduplication-for-home-server/13589/3) with ZFS native encryption the user should be aware of.

By default, the installer will bump the default amount of pbkdf iterations to 1,000,000 from 350,000. This is a specific amount of iterations due to ZFS' lack of ability to calculate based on the amount of time the user desires to wait, as opposed to something like LUKS.

The only supported swap method out of the box via this installer is zram due to ZFS [limitations](https://github.com/openzfs/zfs/issues/7734).

# btrfs notes

Do note that btrfs support in this installer is still considered experimental, meaning the deployed setup is likely to change over time.

Currently, the btrfs option will deploy a "typical" btrfs setup, with the following subvolumes:

- `@` - root
- `@home` - created if the user chooses to split off home
- `@snapshots` - mounted at `/.snapshots`
- `@swap` - created to disable compression as it seems like the `+m` attribute is currently non functional, mounted at `/swap`
- `@var` - copy-on-write disabled

A few other subvolumes are created, because the contents of which typically are undesired as part of snapshots and/or their contents should persist through rollbacks:

- `/root`
- `/tmp`
- `/srv`
- `/usr/local`
- `/boot/grub/x86_64-efi` - only if grub is the chosen bootloader

To some extent, this script tries to mirror the OpenSUSE btrfs setup, which is detailed [here](https://en.opensuse.org/SDB:BTRFS).

# Wrappers

There are wrapper functions for a handful of things, such as ``install`` and ``system``.

``system command`` will run "command" on the new install via chroot for enabling services or otherwise, rather than repetitively entering full chroot commands. This wrapper does not need to ``|| die``, as this is handled in the function that is called, however, ``commandFailure`` must be set before ``system command`` is run if the command should provide a specific output on command failure. 

``install package`` will install "package" on the new install, and also does not need to ``|| die``, as this is handled in the ``install`` function, and also must have ``commandFailure`` set before the command is run if it should return a specific output on command failure.

``setKernelParam "parameter"`` will add ``parameter`` to the new installations kernel parameters, does not need to ``|| die``, and also must have ``commandFailure`` set before the command is run if it should return a specific output on command failure. 

All of the current and future wrapper functions will be located in ``misc/libviss``.

# Misc notes

This installer only supports x86_64-efi. I currently have no plans to support anything else.

If you have found this script useful, do star this repository!

# Contributing

The best way to contribute to this would be to create a pull request adding the feature you would like.

Any new pull requests should target the `dev` branch. At the moment, the installer appears rather stable- the `dev` branch will provide a place to merge new changes, which after testing, can be merged into `main`.

If you would like a change to be made to the script, a request/suggestion in the issues tracker is also a wonderful place to start.

There *are* a few things to keep in mind- 

- No tab characters. Using 4 spaces in place of tab characters is appropriate.
- Try to follow the scripting and formatting style of the script in general, in order to keep things consistent.
- Contribute with the mindset that although something may be merged, it also may be mercilessly edited/modified/removed later.

# TODO
- Add manual partitioning
- Split security modules into their own menu
- Add more bootloader choices such as limine and systemd-boot
- You tell me, or, open a PR adding what you want.
