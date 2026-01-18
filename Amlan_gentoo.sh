#!/bin/bash
# ==========================================================
#  AMLAN GENTOO INSTALLER
#  Host-side installer (BIOS + GPT + OpenRC)
# ==========================================================

set -euo pipefail

clear
echo "=================================================="
echo "        AMLAN GENTOO AUTOMATED INSTALLER"
echo "=================================================="

# --------------------------------------------------
# 1. Root Check
# --------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    exit 1
fi

# --------------------------------------------------
# 2. Disk Selection
# --------------------------------------------------
echo ""
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL
echo ""

read -rp "Enter target disk (example: /dev/sda or /dev/nvme0n1): " DRIVE

if [[ ! -b "$DRIVE" ]]; then
    echo "ERROR: $DRIVE is not a valid block device."
    exit 1
fi

echo ""
echo "⚠️  WARNING ⚠️"
echo "ALL DATA ON $DRIVE WILL BE PERMANENTLY ERASED."
echo ""
read -rp "Type EXACTLY 'YES' to continue: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 1
fi

# Save drive for chroot phase
mkdir -p /mnt/gentoo
echo "$DRIVE" > /mnt/gentoo/.install_drive

# --------------------------------------------------
# 3. Disk Preparation (GPT + BIOS)
# --------------------------------------------------
echo ""
echo "[+] Wiping disk signatures..."
wipefs -af "$DRIVE"

echo "[+] Creating GPT partition table..."
parted -s "$DRIVE" mklabel gpt

# BIOS boot partition
parted -s "$DRIVE" mkpart primary 1MiB 3MiB
parted -s "$DRIVE" set 1 bios_grub on

# Swap (4 GiB)
parted -s "$DRIVE" mkpart primary linux-swap 3MiB 4099MiB

# Root partition
parted -s "$DRIVE" mkpart primary ext4 4099MiB 100%

ROOT_PART="${DRIVE}3"
SWAP_PART="${DRIVE}2"

# --------------------------------------------------
# 4. Filesystems
# --------------------------------------------------
echo "[+] Formatting root filesystem..."
mkfs.ext4 -F "$ROOT_PART"

echo "[+] Enabling swap..."
mkswap "$SWAP_PART"
swapon "$SWAP_PART"

echo "[+] Mounting Gentoo root..."
mount "$ROOT_PART" /mnt/gentoo

# --------------------------------------------------
# 5. Stage 3 Installation
# --------------------------------------------------
cd /mnt/gentoo

echo ""
echo "Stage 3 (OpenRC amd64)"
read -rp "Paste Stage 3 tarball URL: " STAGE3_URL

wget "$STAGE3_URL"

echo "[+] Extracting Stage 3..."
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# --------------------------------------------------
# 6. make.conf Optimization
# --------------------------------------------------
echo "[+] Configuring make.conf..."
CORES=$(nproc)

cat > /mnt/gentoo/etc/portage/make.conf <<EOF
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j${CORES}"
ACCEPT_LICENSE="*"
EOF

# --------------------------------------------------
# 7. Network Configuration
# --------------------------------------------------
echo "[+] Copying DNS configuration..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# --------------------------------------------------
# 8. Mount Pseudo-filesystems
# --------------------------------------------------
echo "[+] Mounting pseudo-filesystems..."
mount -t proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

# --------------------------------------------------
# 9. Chroot Phase
# --------------------------------------------------
echo "[+] Writing chroot installer..."

cat > /mnt/gentoo/chroot_install.sh <<'EOF'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(gentoo-chroot) $PS1"

DRIVE=$(cat /.install_drive)

echo "[+] Syncing Portage..."
emerge-webrsync

echo "[+] Selecting OpenRC profile..."
eselect profile set default/linux/amd64/17.1

echo "[+] Updating world set (this takes time)..."
emerge --update --deep --newuse @world

echo "[+] Setting timezone..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

echo "[+] Generating locale..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo 'LANG="en_US.UTF-8"' > /etc/env.d/02locale
env-update && source /etc/profile

echo "[+] Installing firmware and binary kernel..."
emerge sys-kernel/linux-firmware
emerge sys-kernel/gentoo-kernel-bin

echo "[+] Installing GRUB..."
emerge sys-boot/grub
grub-install "$DRIVE"
grub-mkconfig -o /boot/grub/grub.cfg

echo "[+] Installing networking..."
emerge net-misc/dhcpcd
rc-update add dhcpcd default

echo ""
echo "Set root password:"
passwd

echo ""
echo "Gentoo base installation complete."
EOF

chmod +x /mnt/gentoo/chroot_install.sh

echo "[+] Entering chroot..."
chroot /mnt/gentoo /bin/bash /chroot_install.sh

echo ""
echo "=================================================="
echo " Installation finished."
echo " Exit chroot, unmount, and reboot."
echo "=================================================="
