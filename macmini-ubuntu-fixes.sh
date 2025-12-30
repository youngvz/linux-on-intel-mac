#!/usr/bin/env bash
# macmini-ubuntu-fixes.sh
#
# Purpose:
#   Apply boot-stability + boot-time tweaks for Ubuntu on Intel Macs (T2/Apple EFI),
#   especially when booting from an external SSD and dealing with Apple EFI quirks.
#
# What this script does:
#   - Masks systemd-rfkill (prevents RF Kill state persistence failures)
#   - Masks + purges Plymouth (prevents VT stealing / blinking / boot hijack)
#   - Disables NetworkManager-wait-online (removes long boot delays)
#   - Masks systemd-udev-settle (avoid unnecessary boot waiting)
#   - Enables fstrim.timer (SSD maintenance)
#   - Disables snapd.socket + stops snapd (optionally purges snapd)
#
# What this script intentionally does NOT do:
#   - It does NOT modify GRUB. On Intel Macs + eGPU, kernel args are fragile and
#     should be edited manually and documented in the repo.
#
# Usage:
#   sudo bash macmini-ubuntu-fixes.sh
#
# Optional:
#   PURGE_SNAPD=1 sudo bash macmini-ubuntu-fixes.sh
#
set -euo pipefail

log()  { printf "\n\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m[ERR ]\033[0m %s\n" "$*"; exit 1; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "Run as root: sudo bash $0"
fi

PURGE_SNAPD="${PURGE_SNAPD:-0}"

log "Starting: Intel Mac Ubuntu stabilization + boot-time tuning"

# Track actions for a quick summary
declare -a CHANGES=()

# -----------------------------
# 1) rfkill persistence: disable/mask
# -----------------------------
log "Masking systemd-rfkill (prevents 'Load/Save RF Kill Switch Status' boot failure noise)"
systemctl mask --now systemd-rfkill.service >/dev/null 2>&1 || true
systemctl mask --now systemd-rfkill.socket  >/dev/null 2>&1 || true
CHANGES+=("Masked systemd-rfkill.service + systemd-rfkill.socket")

# -----------------------------
# 2) Plymouth: disable/mask + purge
# -----------------------------
log "Masking Plymouth units (prevents VT stealing / blinking boot logs)"
systemctl mask --now plymouth-start.service     >/dev/null 2>&1 || true
systemctl mask --now plymouth-quit.service      >/dev/null 2>&1 || true
systemctl mask --now plymouth-quit-wait.service >/dev/null 2>&1 || true
CHANGES+=("Masked Plymouth units")

log "Purging Plymouth packages (removes splash; helps avoid early-boot VT weirdness)"
apt-get update -y >/dev/null 2>&1 || true
apt-get purge -y plymouth plymouth-theme-ubuntu-text plymouth-theme-spinner >/dev/null 2>&1 || true
apt-get autoremove -y >/dev/null 2>&1 || true
CHANGES+=("Purged plymouth + themes (best-effort)")

# -----------------------------
# 3) Boot time: disable wait-online
# -----------------------------
log "Disabling NetworkManager-wait-online (removes unnecessary boot blocking)"
systemctl disable --now NetworkManager-wait-online.service >/dev/null 2>&1 || true
CHANGES+=("Disabled NetworkManager-wait-online.service")

# -----------------------------
# 4) Boot time: mask udev settle
# -----------------------------
log "Masking systemd-udev-settle (avoid blocking boot waiting for 'settle')"
systemctl mask --now systemd-udev-settle.service >/dev/null 2>&1 || true
CHANGES+=("Masked systemd-udev-settle.service")

# -----------------------------
# 5) Snap: disable socket + stop service
#     Optional purge to avoid surprises on desktops
# -----------------------------
log "Disabling snapd.socket (prevents early snap namespace/mount churn)"
systemctl disable --now snapd.socket >/dev/null 2>&1 || true
systemctl stop snapd.service >/dev/null 2>&1 || true
CHANGES+=("Disabled snapd.socket and stopped snapd.service (best-effort)")

if [[ "$PURGE_SNAPD" == "1" ]]; then
  warn "PURGE_SNAPD=1 set: purging snapd packages + removing leftover directories"
  apt-get purge -y snapd >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true

  if [[ -d /snap || -d /var/snap || -d /var/lib/snapd ]]; then
    rm -rf /snap /var/snap /var/lib/snapd 2>/dev/null || true
  fi
  CHANGES+=("Purged snapd + removed /snap, /var/snap, /var/lib/snapd (best-effort)")
else
  warn "Skipping snapd purge (set PURGE_SNAPD=1 to remove snapd entirely)"
fi

# -----------------------------
# 6) SSD maintenance: enable periodic TRIM
# -----------------------------
log "Enabling fstrim.timer (helps SSD performance over time)"
systemctl enable --now fstrim.timer >/dev/null 2>&1 || true
CHANGES+=("Enabled fstrim.timer")

# -----------------------------
# 7) GRUB: do NOT touch
# -----------------------------
warn "GRUB NOT modified by this script."
warn "On Intel Macs + eGPU, keep kernel args manual + documented (recommended)."

# -----------------------------
# 8) Final status summary
# -----------------------------
log "Done. Changes applied:"
for c in "${CHANGES[@]}"; do
  echo "  - $c"
done

echo
echo "---- failed units (if any) ----"
systemctl --failed || true

echo
echo "---- key unit states ----"
echo -n "NetworkManager-wait-online: "; systemctl is-enabled NetworkManager-wait-online.service 2>/dev/null || true
echo -n "snapd.socket: ";             systemctl is-enabled snapd.socket 2>/dev/null || true
echo -n "fstrim.timer: ";             systemctl is-enabled fstrim.timer 2>/dev/null || true
echo -n "systemd-rfkill.service: ";   systemctl is-enabled systemd-rfkill.service 2>/dev/null || true

log "Recommended: reboot now to validate a clean, fast boot."
echo "After reboot, run:"
echo "  systemd-analyze"
echo "  systemd-analyze critical-chain"
