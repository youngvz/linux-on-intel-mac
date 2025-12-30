# linux-on-intel-mac

Practical scripts and notes for running Ubuntu reliably on Intel-based Macs.

This repository contains post-install scripts, configuration tweaks, and operational guidance for stabilizing and tuning Ubuntu on Intel Macs using Apple EFI. The focus is on **predictable boot behavior**, **eliminating common firmware-related issues**, and **improving boot time**, especially when Ubuntu is installed on an external SSD.

These changes are based on real-world troubleshooting on Intel Mac hardware (including Mac mini 2018) and are intended to make the system boring, fast, and stable.

---

## Why this repo exists

Running Linux on Intel Macs works well, but Apple EFI introduces quirks that Ubuntu’s defaults don’t always handle cleanly. Common problems include:

- Boot hangs or blinking screens caused by Plymouth
- `systemd-rfkill` failures that block or disrupt boot
- Long boot times due to unnecessary wait services
- Unstable device enumeration when booting from external SSDs
- Confusing GRUB behavior due to disk reordering

This repo documents **the minimal set of changes** needed to avoid those issues without resorting to hacks or constant manual intervention.

---

## Target environment

**Tested on**
- Intel-based Macs (T2)
- macOS + Ubuntu dual-boot
- Ubuntu 22.04 LTS
- External SSD boot (USB / Thunderbolt)

**Likely applicable to**
- MacBook Pro (2018–2019)
- MacBook Air (Intel)
- Other Intel Macs using Apple EFI

**Out of scope**
- Apple Silicon (M1/M2/M3)
- Secure Boot enforcement
- Virtualization-only setups

---

## What the scripts do

The primary script applies the following changes:

### Boot stability
- Masks `systemd-rfkill` to prevent RF kill state persistence failures
- Removes Plymouth to avoid console/VT conflicts during boot
- Ensures GRUB uses stable kernel parameters

### Boot time improvements
- Disables `NetworkManager-wait-online`
- Masks `systemd-udev-settle`
- Delays or removes Snap-related mounts
- Enables periodic SSD TRIM

### Mac / EFI–specific tuning
- Preserves safe PCI and IOMMU kernel flags
- Disables USB autosuspend (helps with external SSDs and hubs)

All changes are **idempotent** and safe to re-run.

---

## Usage

Clone the repository:

```bash
git clone https://github.com/youngvz/linux-on-intel-mac.git
cd linux-on-intel-mac
