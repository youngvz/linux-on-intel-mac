#!/usr/bin/env bash
# macmini-ubuntu-fixes.sh
#
# Purpose:
#   Apply the boot-stability + boot-time tweaks we implemented for Ubuntu 22.04
#   running from an external SSD on a 2018 Intel Mac mini (T2/Apple EFI).
#
# What this script does:
#   - Masks systemd-rfkill (prevents RF Kill state persistence failures)
#   - Removes Plymouth (prevents VT blinking / boot log hijacking)
#   - Disables NetworkManager-wait-online (removes long boot delays)
#   - Masks systemd-udev-settle (avoid unnecessary boot waiting)
#   - Disables snapd socket + stops snapd, optionally purges snapd (you already did)
#   - Enables fstrim.timer (SSD maintenance)
#   - Optionally updates GRUB kernel args (keeps your existing args, removes quiet/splash)
#
# Safe/idempotent: re-running should be fine.
#
# Usage:
#   sudo bash macmini-ubuntu-fixes.sh
#
set -euo pipefail

log()  { printf "\n\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31m[ERR ]\033[0m %s\n" "$*"; exit 1; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "Run as root: sudo bash $0"
fi

log "Starting: Mac mini external-SSD Ubuntu stabilization + boot-time tuning"

# -----------------------------
# 1) rfkill persistence: disable/mask
# -----------------------------
log "Masking systemd-rfkill (prevents 'Load/Save RF Kill Switch Status' boot failure noise)"
systemctl mask --now systemd-rfkill.service >/dev/null 2>&1 || true
systemctl mask --now systemd-rfkill.socket  >/dev/null 2>&1 || true

# -----------------------------
# 2) Plymouth: disable/mask + purge
# -----------------------------
log "Masking Plymouth units (prevents VT stealing / blinking boot logs)"
systemctl mask --now plymouth-start.service     >/dev/null 2>&1 || true
systemctl mask --now plymouth-quit.service      >/dev/null 2>&1 || true
systemctl mask --now plymouth-quit-wait.service >/dev/null 2>&1 || true

log "Purging Plymouth packages (safe on Ubuntu desktop; removes splash)"
apt-get update -y >/dev/null 2>&1 || true
apt-get purge -y plymouth plymouth-theme-ubuntu-text plymouth-theme-spinner >/dev/null 2>&1 || true
apt-get autoremove -y >/dev/null 2>&1 || true

# -----------------------------
# 3) Boot time: disable wait-online
# -----------------------------
log "Disabling NetworkManager-wait-online (removes unnecessary boot blocking)"
systemctl disable --now NetworkManager-wait-online.service >/dev/null 2>&1 || true

# -----------------------------
# 4) Boot time: mask udev settle (often pointless on desktops)
# -----------------------------
log "Masking systemd-udev-settle (avoid blocking boot on device settle)"
systemctl mask --now systemd-udev-settle.service >/dev/null 2>&1 || true

# -----------------------------
# 5) Snap: disable socket + optionally purge snapd
# -----------------------------
log "Disabling snapd.socket (prevents early snap namespace/mount churn)"
systemctl disable --now snapd.socket >/dev/null 2>&1 || true
systemctl stop snapd.service >/dev/null 2>&1 || true

# You said you purged snapd already. We'll attempt it anyway safely.
log "Purging snapd (no-op if already removed)"
apt-get purge -y snapd >/dev/null 2>&1 || true
apt-get autoremove -y >/dev/null 2>&1 || true

# Clean snap leftovers if any remain
if [[ -d /snap || -d /var/snap || -d /var/lib/snapd ]]; then
  log "Removing leftover snap directories (if present)"
  rm -rf /snap /var/snap /var/lib/snapd 2>/dev/null || true
fi

# -----------------------------
# 6) SSD maintenance: enable periodic TRIM
# -----------------------------
log "Enabling fstrim.timer (helps SSD performance over time)"
systemctl enable --now fstrim.timer >/dev/null 2>&1 || true

# -----------------------------
# 7) Optional GRUB hygiene:
#    - Remove quiet/splash (if present)
#    - Ensure stable external-SSD boot args remain intact
#    - Add usbcore.autosuspend=-1 (common Mac USB stability win)
#    NOTE: We DO NOT remove your existing PCI flags.
# -----------------------------
GRUB_FILE="/etc/default/grub"
if [[ -f "$GRUB_FILE" ]]; then
  log "Updating GRUB defaults (remove quiet/splash; add usbcore.autosuspend=-1 if missing)"
  cp -a "$GRUB_FILE" "${GRUB_FILE}.bak.$(date +%Y%m%d_%H%M%S)"

  # Read current GRUB_CMDLINE_LINUX_DEFAULT value (best-effort)
  current="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | head -n1 || true)"

  if [[ -z "$current" ]]; then
    warn "GRUB_CMDLINE_LINUX_DEFAULT not found; skipping GRUB_CMDLINE edits."
  else
    # Extract content between quotes (handles simple quoted values)
    cmdline="$(printf "%s" "$current" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/')"

    # Remove quiet/splash if present
    cmdline="$(echo "$cmdline" | sed -E 's/\bquiet\b//g; s/\bsplash\b//g' | tr -s ' ')"
    cmdline="$(echo "$cmdline" | sed -E 's/^ +| +$//g')"

    # Add usbcore.autosuspend=-1 if missing (helps external USB storage on Macs)
    if ! echo "$cmdline" | grep -q 'usbcore\.autosuspend=-1'; then
      cmdline="$cmdline usbcore.autosuspend=-1"
    fi

    # Write back
    # Use a conservative replace of the line.
    sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${cmdline}\"|g" "$GRUB_FILE"

    log "Regenerating GRUB config"
    update-grub >/dev/null
  fi
else
  warn "/etc/default/grub not found; skipping GRUB updates."
fi

# -----------------------------
# 8) Final status summary
# -----------------------------
log "Done. Quick status summary:"
echo "---- failed units ----"
systemctl --failed || true
echo
echo "---- key unit states ----"
systemctl is-enabled NetworkManager-wait-online.service 2>/dev/null || true
systemctl is-enabled snapd.socket 2>/dev/null || true
systemctl is-enabled fstrim.timer 2>/dev/null || true
systemctl status systemd-rfkill.service --no-pager 2>/dev/null | sed -n '1,6p' || true
echo
log "Recommended: reboot now to validate a clean, fast boot."
echo "Run after reboot:"
echo "  systemd-analyze"
echo "  systemd-analyze critical-chain"
