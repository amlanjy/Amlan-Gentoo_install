# Amlan Gentoo Installer

A modular, experimental Gentoo Linux installer written in Bash.

This project automates the most repetitive and error-prone parts of a traditional Gentoo installation while intentionally preserving clear phase boundaries between the host system and the target Gentoo environment.

It is designed for **learning, experimentation, and real hardware installs**, not as a drop-in replacement for the official Gentoo Handbook.

---

## Philosophy

Gentoo is not hard because it is complex — it is hard because it is *manual*.

This installer:
- Automates the boring, mechanical steps
- Keeps irreversible decisions explicit
- Preserves Gentoo’s transparency instead of hiding it
- Treats installation as a **process**, not a magic button

The goal is not to abstract Gentoo away, but to **compress the ceremony**.

---

## Features

- **Guided Disk Installation**
  - Explicit disk selection and confirmation
  - GPT partitioning with BIOS boot support
  - Swap + root layout

- **Stage 3 Deployment**
  - User-selected OpenRC amd64 Stage 3 tarball
  - Proper extraction with ownership and attributes preserved

- **Optimized Build Configuration**
  - Automatic CPU core detection
  - Sensible `make.conf` defaults for faster compilation

- **Binary Kernel**
  - Uses `gentoo-kernel-bin` to avoid long kernel build times

- **OpenRC Init System**
  - Clean, traditional Gentoo setup
  - DHCP enabled on first boot

- **Two-Phase Design**
  - Host-side preparation
  - Chroot-side system configuration

---

## Supported Configuration

- **Architecture:** amd64  
- **Boot Mode:** BIOS (Legacy) with GPT  
- **Init System:** OpenRC  
- **Kernel:** gentoo-kernel-bin  
- **Target:** Bare-metal systems  

⚠️ UEFI systems are **not supported yet**.

---

## Requirements

- Gentoo LiveGUI or minimal Gentoo LiveCD
- Internet connection
- Root access
- Entire target disk available (will be wiped)

---

## Usage

1. Boot into a Gentoo Live environment.
2. Clone the repository:

       git clone https://github.com/amlanjy/Amlan-Gentoo_install.git
       cd Amlan-Gentoo_install
       chmod +x Amlan_gentoo.sh
       ./Amlan_gentoo.sh

# How the Installer Works

The installation is intentionally split into two logical phases:
Phase 1: Host System
Disk wiping and partitioning
Filesystem creation
Stage 3 download and extraction
Network and chroot preparation
Phase 2: Gentoo Chroot
Portage sync
Profile selection
World update
Locale and timezone configuration
Kernel and firmware installation
Bootloader setup
Network service enablement
This separation mirrors how Gentoo actually works and makes the process easier to understand and debug.


#⚠️ Disclaimer
#WARNING:

This installer performs destructive disk operations.
All data on the selected disk will be permanently erased.
Review the script before running it.
Use only on systems where data loss is acceptable.
You are fully responsible for the outcome.
Project Status
This project is experimental.
It is:
Suitable for learning and personal use
Tested on real hardware
Actively evolving
It is not intended to be:
A beginner-friendly Gentoo shortcut
A production-grade universal installer
