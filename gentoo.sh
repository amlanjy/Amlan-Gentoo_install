#!/bin/bash
set -euo pipefail

clear
echo "=============================================="
echo " MINIMAL GENTOO UEFI INSTALLER (MANUAL DISK)"
echo "=============================================="

# ------------------ FIXED SETTINGS ------------------
HOSTNAME="gentoo"
USERNAME="lapu"
USERPASS="Amjych"
ROOTPASS="6895"

# --------------------------------------------------
# Sanity checks
# --------------------------------------------------
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "Not booted in UEFI mode."; exit 1; }

# --------------------------------------------------
# Disk selection
# --------------------------------------------------
lsblk -d -o NAME,SIZE,MODEL
read -rp "Select target disk (e.g. /dev/sda, /dev/nvme0n1): " DRIVE
[[ -b "$DRIVE" ]] || { echo "Invalid disk."; exit 1; }

echo ""
echo "You will now manually partition $DRIVE"
echo "Create:"
echo "  - EFI System Partition"
echo "  - Linux root partition"
echo "  - Linux swap partition"
echo ""
read -rp "Press ENTER to open cfdisk..." _
cfdisk "$DRIVE"

echo ""
lsblk "$DRIVE"
echo ""

read -rp "Enter EFI partition  (e.g. /dev/sda1): " EFI
read -rp "Enter ROOT partition (e.g. /dev/sda2): " ROOT
read -rp "Enter SWAP partition (e.g. /dev/sda3): " SWAP

[[ -b "$EFI"  ]] || { echo "EFI partition not found."; exit 1; }
[[ -b "$ROOT" ]] || { echo "Root partition not found."; exit 1; }
[[ -b "$SWAP" ]] || { echo "Swap partition not found."; exit 1; }

echo ""
echo "EFI :  $EFI"
echo "ROOT:  $ROOT"
echo "SWAP:  $SWAP"
echo ""
echo "FINAL WARNING: these partitions will be formatted / initialized"
read -rp "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# --------------------------------------------------
# Filesystems
# --------------------------------------------------
umount -R "$EFI"  2>/dev/null || true
umount -R "$ROOT" 2>/dev/null || true
swapoff "$SWAP"   2>/dev/null || true

mkfs.vfat -F32 "$EFI"
mkfs.ext4 "$ROOT"
mkswap "$SWAP"
swapon "$SWAP"

mount "$ROOT" /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount "$EFI" /mnt/gentoo/boot

# --------------------------------------------------
# Stage3
# --------------------------------------------------
cd /mnt/gentoo
wget -c --tries=5 --timeout=30 \
  https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc.tar.xz

tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# --------------------------------------------------
# Portage config (MINIMAL, NO JUNK)
# --------------------------------------------------
cat > /mnt/gentoo/etc/portage/make.conf <<EOF
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j4"

# Global philosophy: no systemd, no DEs, no GUI unless explicitly enabled
USE="-systemd -kde -plasma -gnome -elogind -wayland -X -qt5 -qt6 -gtk"

ACCEPT_LICENSE="*"
GRUB_PLATFORMS="efi-64"
EOF

# --------------------------------------------------
# Mount pseudo-filesystems
# --------------------------------------------------
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys && mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev && mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run && mount --make-slave /mnt/gentoo/run

# --------------------------------------------------
# UUIDs for fstab
# --------------------------------------------------
EFI_UUID=$(blkid -s UUID -o value "$EFI")
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
SWAP_UUID=$(blkid -s UUID -o value "$SWAP")

# --------------------------------------------------
# Chroot script
# --------------------------------------------------
cat > /mnt/gentoo/chroot.sh <<EOF
#!/bin/bash
set -euo pipefail
source /etc/profile

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

emerge-webrsync
eselect news read >/dev/null 2>&1 || true

ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc || true

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo 'LANG="en_US.UTF-8"' > /etc/env.d/02locale
env-update && source /etc/profile

cat > /etc/fstab <<FSTAB
UUID=$ROOT_UUID  /      ext4  defaults,noatime  0 1
UUID=$EFI_UUID   /boot  vfat  defaults          0 2
UUID=$SWAP_UUID  none   swap  sw                0 0
FSTAB

emerge sys-kernel/linux-firmware sys-kernel/gentoo-kernel-bin
eselect kernel set 1

emerge net-misc/dhcpcd sudo app-admin/syslog-ng
rc-update add dhcpcd default
rc-update add syslog-ng default

useradd -m -G wheel -s /bin/bash $USERNAME
mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

echo "root:$ROOTPASS" | chpasswd
echo "$USERNAME:$USERPASS" | chpasswd

emerge sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg
EOF

chmod +x /mnt/gentoo/chroot.sh
chroot /mnt/gentoo /bin/bash /chroot.sh

echo "=============================================="
echo " INSTALL COMPLETE — REBOOT SAFELY"
echo "=============================================="
