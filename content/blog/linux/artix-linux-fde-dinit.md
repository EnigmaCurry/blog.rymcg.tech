---
title: "Artix Linux Workstation with Dinit and Sway"
date: 2026-04-05T00:00:00-06:00
tags: ['linux', 'artix', 'home-manager', 'sway']
---

This guide documents setting up [Artix Linux](https://artixlinux.org/)
with [dinit](https://github.com/davmac314/dinit) on a ThinkPad X1
Carbon laptop. Artix is an Arch-based distribution that does not use systemd. This setup includes full disk encryption with LUKS +
LVM (including encrypted `/boot`), a sway Wayland desktop managed by Nix home-manager
([sway-home](https://github.com/EnigmaCurry/sway-home)), and a
setup for development with rootless Podman containers and libvirt QEMU
virtual machines.

## Hardware

- ThinkPad X1 Carbon (i7-10610U, 16GB RAM)
- 1TB NVMe SSD (`/dev/nvme0n1`)

## Partition Layout

```
/dev/nvme0n1   - 1TB NVMe SSD with GPT partition table
/dev/nvme0n1p1 - EFI System Partition (ESP), 1 GB, FAT32 (unencrypted)
/dev/nvme0n1p2 - LUKS encrypted → LVM container
  ├── lvm-volBoot - /boot, 1 GB
  ├── lvm-volSwap - swap, 16 GB
  └── lvm-volRoot - / root (remaining ~935 GB)
```

Only the ESP is unencrypted (required by UEFI firmware). Everything else
including `/boot` is inside the LUKS container. On boot, you enter your
LUKS passphrase **twice**: once for GRUB (to read `/boot`) and once for
the initramfs `encrypt` hook (to mount root).

## Create Bootable USB

Download the base ISO and write it with
[Fedora Media Writer](https://flathub.org/apps/org.fedoraproject.MediaWriter)
or `dd`:

- ISO: `artix-base-dinit-20260402-x86_64.iso`
- Mirror: `https://mirror.math.princeton.edu/pub/artixlinux/`

## Boot Live Environment

### Connect to WiFi

```bash
nmtui
```

Select "Activate a connection" and configure WiFi.

### Enable SSH

```bash
dinitctl start sshd
```

Default live credentials: `artix` / `artix` (or `root` / `artix`).

SSH in from another machine:

```bash
ssh root@<ip-address>
```

## Disk Partitioning

### Install Dependencies

```bash
pacman -Sy --noconfirm gptfdisk parted cryptsetup lvm2 dosfstools
```

### Set Variables

List available disks and identify your target drive:

```bash
lsblk -d -o NAME,SIZE,MODEL
```

Set your disk as a temporary environment variable:

```bash
DISK=/dev/nvme0n1
```

### Erase the Disk

**WARNING: This destroys all data on the target disk.**

```bash
sgdisk --zap-all ${DISK}
blkdiscard ${DISK}
```

This wipes the partition table and TRIMs the entire SSD. LUKS encryption
makes remaining data inaccessible. A full `dd if=/dev/urandom` overwrite
is unnecessary for a fresh install and would add significant SSD wear.

### Create Partitions

```bash
parted -s ${DISK} mklabel gpt

# EFI System Partition (1 GB)
parted -s -a optimal ${DISK} mkpart "ESP" fat32 0% 1024MiB
parted -s ${DISK} set 1 esp on

# LUKS partition (rest of disk)
parted -s -a optimal ${DISK} mkpart "LUKS" ext4 1024MiB 100%
parted -s ${DISK} set 2 lvm on

parted -s ${DISK} print
```

## Setup Encryption and Logical Volumes

### LUKS Setup

```bash
cryptsetup benchmark  # loads kernel crypto modules

cryptsetup --verbose --type luks1 --cipher serpent-xts-plain64 --key-size 512 \
  --hash sha512 --iter-time 10000 --use-random --verify-passphrase luksFormat ${DISK}p2

cryptsetup luksOpen ${DISK}p2 lvm-system
```

### LVM Setup

```bash
pvcreate /dev/mapper/lvm-system
vgcreate lvmSystem /dev/mapper/lvm-system

lvcreate --contiguous y --size 1G lvmSystem --name volBoot
lvcreate --contiguous y --size 16G lvmSystem --name volSwap
lvcreate --contiguous y --extents +100%FREE lvmSystem --name volRoot
```

### Format Partitions

```bash
mkfs.fat -F32 -n ESP ${DISK}p1
mkfs.ext4 -L BOOT /dev/lvmSystem/volBoot
mkswap -L SWAP /dev/lvmSystem/volSwap   # note the UUID printed here
mkfs.ext4 -L ROOT /dev/lvmSystem/volRoot
```

### Mount Partitions

```bash
swapon /dev/lvmSystem/volSwap
mount /dev/lvmSystem/volRoot /mnt
mkdir /mnt/boot
mount /dev/lvmSystem/volBoot /mnt/boot
mkdir /mnt/boot/efi
mount ${DISK}p1 /mnt/boot/efi
```

## Install Base System

```bash
basestrap /mnt base base-devel dinit elogind-dinit
basestrap /mnt linux-hardened linux-hardened-headers linux-firmware
basestrap /mnt lvm2 lvm2-dinit cryptsetup cryptsetup-dinit device-mapper-dinit
basestrap /mnt grub efibootmgr dosfstools
basestrap /mnt networkmanager networkmanager-dinit
basestrap /mnt openssh openssh-dinit
basestrap /mnt nano vi less
```

## System Configuration

### Copy WiFi config from live environment

```bash
cp -r /etc/NetworkManager/system-connections /mnt/etc/NetworkManager/
```

### Generate fstab

```bash
fstabgen -U /mnt >> /mnt/etc/fstab
```

Enable TRIM for SSD:

```bash
sed -i "s/relatime/relatime,discard/g" /mnt/etc/fstab
```

tmpfs for /tmp (8G = half RAM):

```bash
echo 'tmpfs    /tmp    tmpfs    rw,nosuid,nodev,relatime,size=8G,mode=1777    0 0' >> /mnt/etc/fstab
```

### chroot

```bash
artix-chroot /mnt /bin/bash --login
export USERNAME=ryan  # set your desired username
```

### Set root password

```bash
passwd
```

### Initialize keyring

```bash
pacman -Sy --noconfirm
pacman-key --init
pacman-key --populate artix
```

### Locale

```bash
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

### Timezone

```bash
ln -sf /usr/share/zoneinfo/US/Mountain /etc/localtime
hwclock --systohc
```

### Hostname

```bash
echo "yourhostname" > /etc/hostname
```

### Remap Caps Lock to Control

```bash
# Console/TTY
echo -e 'include "/usr/share/kbd/keymaps/i386/qwerty/us.map.gz"\nkeycode 58 = Control' > /usr/share/kbd/keymaps/personal.map
echo 'KEYMAP=personal' > /etc/vconsole.conf

# X11
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
    Option "XkbOptions" "ctrl:nocaps"
EndSection
EOF
```

Wayland compositors (sway, etc.) need their own config added later.

### Disable XON/XOFF flow control

Prevents `Ctrl+S` from freezing the terminal:

```bash
echo 'stty -ixon' >> /etc/profile
```

### mkinitcpio

```bash
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf block encrypt keyboard keymap consolefont lvm2 resume filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -p linux-hardened
```

### GRUB Configuration

```bash
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
SWAP_UUID=$(blkid -s UUID -o value /dev/lvmSystem/volSwap)

sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=${LUKS_UUID}:lvm-system:allow-discards loglevel=3 quiet resume=UUID=${SWAP_UUID} net.ifnames=0\"/" /etc/default/grub

echo 'GRUB_ENABLE_CRYPTODISK="y"' >> /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT="15"/' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE="menu"/' /etc/default/grub
sed -i 's/^GRUB_GFXMODE=.*/GRUB_GFXMODE="auto"/' /etc/default/grub
```

### GRUB Installation (UEFI)

```bash
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=artix --recheck
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable  # fallback
grub-mkconfig -o /boot/grub/grub.cfg
```

## Enable Services (dinit)

The `dinitctl --offline enable` command is broken on the 20260402 live
ISO, so services are enabled by creating symlinks directly:

```bash
ln -s /etc/dinit.d/lvm2 /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/NetworkManager /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/elogind /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/dbus /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/sshd /etc/dinit.d/boot.d/
```

### Optional services

```bash
pacman -S --noconfirm openntpd openntpd-dinit syslog-ng syslog-ng-dinit acpid acpid-dinit cronie cronie-dinit
ln -s /etc/dinit.d/ntpd /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/syslog-ng /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/acpid /etc/dinit.d/boot.d/
ln -s /etc/dinit.d/cronie /etc/dinit.d/boot.d/
```

### Useful packages

```bash
pacman -S --noconfirm bash-completion lsof strace wget htop zip unzip p7zip unrar
pacman -S --noconfirm hdparm smartmontools hwinfo dmidecode
pacman -S --noconfirm rsync nmap inetutils net-tools whois
```

## Create User Account

```bash
useradd -m -G wheel -s /bin/bash ${USERNAME}
passwd ${USERNAME}
```

Enable sudo for the wheel group:

```bash
EDITOR=nano visudo
```

Uncomment the line: `%wheel ALL=(ALL:ALL) ALL`

## Finish Installation

Exit the chroot:

```bash
exit
```

Then unmount and reboot:

```bash
umount -R /mnt
swapoff -a
vgchange -an lvmSystem
cryptsetup luksClose lvm-system
sync
reboot
```

## First Boot

After logging in:

```bash
sudo swapon /dev/lvmSystem/volSwap
sudo pacman -Syu --noconfirm
```

Verify mkinitcpio hooks survived the upgrade:

```bash
grep "^HOOKS" /etc/mkinitcpio.conf
# Should contain: encrypt lvm2 resume
# If not, re-add them and run: mkinitcpio -p linux-hardened
```

## Rootless Podman

```bash
sudo pacman -S --noconfirm podman crun slirp4netns fuse-overlayfs
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 ${USERNAME}

# linux-hardened disables unprivileged user namespaces; rootless podman needs them
sudo mkdir -p /etc/sysctl.d
echo 'kernel.unprivileged_userns_clone=1' | sudo tee /etc/sysctl.d/userns.conf
sudo sysctl -w kernel.unprivileged_userns_clone=1
```

## QEMU/libvirt

```bash
sudo pacman -S --noconfirm qemu-full virt-manager libvirt libvirt-dinit dnsmasq
sudo dinitctl enable libvirtd
sudo dinitctl start libvirtd
```

User is not added to the `libvirt` group. virt-manager will prompt for
a password via polkit (lxpolkit) when connecting to `qemu:///system`.

## Nix Package Manager

Artix repos don't have a nix package, so use the single-user install.
No daemon or service needed — fine for a personal laptop.

```bash
curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
```

Source the nix profile:

```bash
. ~/.nix-profile/etc/profile.d/nix.sh
nix --version

# Make nix available for all login sessions via /etc/profile.d/
sudo ln -s ~/.nix-profile/etc/profile.d/nix.sh /etc/profile.d/nix.sh
```

## Sway Desktop with Nix Home Manager

Install sway and audio stack from pacman (they need system-level access):

```bash
sudo pacman -S --noconfirm sway xorg-xwayland dunst libnotify lxsession ttf-font-awesome
sudo pacman -S --noconfirm pipewire pipewire-pulse wireplumber pavucontrol
sudo pacman -S --noconfirm pipewire-dinit wireplumber-dinit
```

### User-level dinit for PipeWire

Artix with dinit needs a per-user dinit instance to manage PipeWire
services. Set up the user boot service and symlinks:

```bash
mkdir -p ~/.config/dinit.d/boot.d
cat > ~/.config/dinit.d/boot <<'EOF'
type = internal
waits-for.d = boot.d
EOF
ln -s /etc/dinit.d/user/dbus ~/.config/dinit.d/boot.d/
ln -s /etc/dinit.d/user/pipewire ~/.config/dinit.d/boot.d/
ln -s /etc/dinit.d/user/wireplumber ~/.config/dinit.d/boot.d/
```

Create a user dinit service for pipewire-pulse (PulseAudio compatibility):

```bash
sudo tee /etc/dinit.d/user/pipewire-pulse <<'EOF'
type = process
command = /usr/bin/pipewire-pulse
depends-on = pipewire
EOF
ln -s /etc/dinit.d/user/pipewire-pulse ~/.config/dinit.d/boot.d/
```

Start user dinit on TTY login (before sway):

```bash
sudo tee /etc/profile.d/dinit-user.sh <<'EOF'
# Start user-level dinit instance on TTY login (non-systemd)
if command -v dinit >/dev/null 2>&1 && ! command -v systemctl >/dev/null 2>&1; then
    if ! dinitctl list >/dev/null 2>&1; then
        rm -f /run/user/$(id -u)/dinitctl
        dinit --user --ready-fd 3 3>/dev/null &
    fi
fi
EOF
```

### Install sway-home

[sway-home](https://github.com/EnigmaCurry/sway-home) manages dotfiles
and user packages declaratively via Nix home-manager:

```bash
sudo pacman -S --noconfirm git just

mv ~/.config ~/.config.orig 2>/dev/null
mv ~/.bashrc ~/.bashrc.orig 2>/dev/null
mv ~/.bash_profile ~/.bash_profile.orig 2>/dev/null

mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf

mkdir -p ~/git/vendor/enigmacurry
git clone https://github.com/enigmacurry/sway-home \
  ~/git/vendor/enigmacurry/sway-home
cd ~/git/vendor/enigmacurry/sway-home
just hm-install
```

Restart your shell session to pick up the new environment.

## Login Manager (greetd + tuigreet)

[greetd](https://git.sr.ht/~kennylevinsen/greetd) is a minimal login
daemon, and [tuigreet](https://github.com/apognu/tuigreet) gives it a
clean console TUI where you select your user and session (sway, shell,
etc.).

```bash
sudo pacman -S --noconfirm greetd greetd-tuigreet greetd-dinit
```

Configure greetd to use tuigreet with sway as the default session:

```bash
sudo tee /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 7

[default_session]
command = "tuigreet --time --remember --remember-session --sessions /usr/share/wayland-sessions"
user = "greeter"
EOF
```

Create a sway desktop entry so tuigreet can discover it:

```bash
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/sway.desktop <<'EOF'
[Desktop Entry]
Name=Sway
Exec=sway
Type=Application
EOF
```

Enable and start the service:

```bash
sudo ln -s /etc/dinit.d/greetd /etc/dinit.d/boot.d/
sudo dinitctl start greetd
```

You should now see the tuigreet login screen. Select `Sway` as your
session and log in.

## Troubleshooting

### "device '/dev/mapper/lvmSystem-volRoot' not found. Skipping fsck."

The `encrypt` hook was lost from `/etc/mkinitcpio.conf` (can happen
after upgrades). Boot from live USB, decrypt and mount, chroot, re-add
`encrypt` to HOOKS, and run `mkinitcpio -p linux-hardened`.

### Recovery from Live USB

```bash
sudo su
cryptsetup benchmark
cryptsetup luksOpen /dev/nvme0n1p2 lvm-system
vgchange -ay lvmSystem
mount /dev/lvmSystem/volRoot /mnt
mount /dev/lvmSystem/volBoot /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot/efi
artix-chroot /mnt /bin/bash
```
