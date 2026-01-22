#!/bin/bash
set -euo pipefail

clear
echo "=============================================="
echo " AMLAN GENTOO UEFI INSTALLER (FIXED)"
echo "=============================================="

# --------------------------------------------------
# 1. Sanity checks
# --------------------------------------------------
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "Not booted in UEFI mode."; exit 1; }

# --------------------------------------------------
# 2. Disk + desktop selection
# --------------------------------------------------
lsblk -d -o NAME,SIZE,MODEL
read -rp "Target disk (e.g. /dev/sda or /dev/nvme0n1): " DRIVE
[[ -b "$DRIVE" ]] || { echo "Invalid disk."; exit 1; }

echo ""
echo "Desktop environment:"
echo "1) KDE Plasma"
echo "2) GNOME"
echo "3) XFCE"
echo "4) LXQt"
echo "5) Hyprland (Wayland)"
echo "6) None (CLI / Server)"
read -rp "Choice: " DESKTOP

echo ""
echo "THIS WILL ERASE ALL DATA ON $DRIVE"
read -rp "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || exit 1

# --------------------------------------------------
# 3. Partitioning (GPT + UEFI)
# --------------------------------------------------
sgdisk -Z "$DRIVE"
sgdisk -n 1:0:+512M -t 1:ef00 "$DRIVE"
sgdisk -n 2:0:+4G   -t 2:8200 "$DRIVE"
sgdisk -n 3:0:0     -t 3:8300 "$DRIVE"

if [[ "$DRIVE" =~ nvme ]]; then
  EFI="${DRIVE}p1"
  SWAP="${DRIVE}p2"
  ROOT="${DRIVE}p3"
else
  EFI="${DRIVE}1"
  SWAP="${DRIVE}2"
  ROOT="${DRIVE}3"
fi

# --------------------------------------------------
# 4. Filesystems
# --------------------------------------------------
mkfs.vfat -F32 "$EFI"
mkswap "$SWAP"
mkfs.ext4 "$ROOT"

swapon "$SWAP"
mount "$ROOT" /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount "$EFI" /mnt/gentoo/boot

# --------------------------------------------------
# 5. Stage3 install
# --------------------------------------------------
cd /mnt/gentoo
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# --------------------------------------------------
# 6. Portage config
# --------------------------------------------------
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

cat > /mnt/gentoo/etc/portage/make.conf <<EOF
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc)"
ACCEPT_LICENSE="*"
GRUB_PLATFORMS="efi-64"
EOF

# --------------------------------------------------
# 7. Mount pseudo-filesystems
# --------------------------------------------------
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

# --------------------------------------------------
# 8. Chroot script
# --------------------------------------------------
cat > /mnt/gentoo/chroot.sh <<EOF
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(gentoo) \$PS1"

emerge-webrsync
eselect profile set default/linux/amd64/17.1
emerge --update --deep --newuse @world

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo 'LANG="en_US.UTF-8"' > /etc/env.d/02locale
env-update && source /etc/profile

cat > /etc/fstab <<FSTAB
$ROOT  /     ext4  defaults,noatime  0 1
$EFI   /boot vfat  defaults          0 2
$SWAP  none  swap  sw                0 0
FSTAB

emerge sys-kernel/linux-firmware
emerge sys-kernel/gentoo-kernel-bin
eselect kernel set 1

emerge net-misc/dhcpcd
rc-update add dhcpcd default

emerge app-admin/syslog-ng
rc-update add syslog-ng default

# Desktop base stack
if [[ "$DESKTOP" != "6" ]]; then
  emerge sys-auth/elogind
  rc-update add elogind boot
  emerge x11-base/xorg-server x11-base/xorg-drivers media-libs/mesa x11-base/xwayland
fi

case "$DESKTOP" in
  1)
    emerge kde-plasma/plasma-meta kde-apps/kde-apps-meta x11-misc/sddm
    rc-update add sddm default
    ;;
  2)
    emerge gnome-base/gnome gnome-base/gdm
    rc-update add gdm default
    ;;
  3)
    emerge xfce-base/xfce4 xfce-extra/xfce4-goodies x11-misc/lightdm x11-misc/lightdm-gtk-greeter
    rc-update add lightdm default
    ;;
  4)
    emerge lxqt-base/lxqt-meta x11-misc/sddm
    rc-update add sddm default
    ;;
  5)
    emerge gui-wm/hyprland
    ;;
  6)
    ;;
esac

emerge sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg

echo "Set root password:"
passwd
EOF

chmod +x /mnt/gentoo/chroot.sh
chroot /mnt/gentoo /bin/bash /chroot.sh

# --------------------------------------------------
# 9. Finish
# --------------------------------------------------
echo "=============================================="
echo " INSTALL COMPLETE"
echo " Unmount and reboot"
echo "=============================================="
