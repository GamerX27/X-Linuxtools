#!/usr/bin/env bash
# convert-to-sid.sh
# Convert current Debian install to Sid (unstable).
# Usage: sudo bash convert-to-sid.sh [--yes]

set -euo pipefail

AUTO_YES="no"
if [[ "${1:-}" == "--yes" ]]; then
  AUTO_YES="yes"
fi

#----- safety checks -----------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0 [--yes]"
  exit 1
fi

if [[ ! -f /etc/debian_version ]]; then
  echo "This doesn't look like a Debian system (missing /etc/debian_version). Aborting."
  exit 1
fi

echo "Detected Debian $(cat /etc/debian_version)"
echo "This will switch your system to Debian Sid (unstable)."
echo "Proceed only if you're comfortable with potential breakage."

#----- backups -----------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/root/apt-backup-$TS"
mkdir -p "$BACKUP_DIR"

if [[ -f /etc/apt/sources.list ]]; then
  cp -a /etc/apt/sources.list "$BACKUP_DIR/sources.list.bak"
fi

if [[ -d /etc/apt/sources.list.d ]]; then
  tar -C /etc/apt -czf "$BACKUP_DIR/sources.list.d.tgz" sources.list.d || true
fi

echo "Backups saved in: $BACKUP_DIR"

#----- write new sources.list --------------------------------------------------
# Binary + source entries for sid with main contrib non-free non-free-firmware
cat >/etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian sid main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian sid main contrib non-free non-free-firmware
EOF

echo "Wrote new /etc/apt/sources.list for Debian Sid."

# Optional: disable any extra .list files to avoid pin/mix issues
if compgen -G "/etc/apt/sources.list.d/*.list" > /dev/null; then
  echo "Disabling additional entries in /etc/apt/sources.list.d/ (saved to .disabled)..."
  for f in /etc/apt/sources.list.d/*.list; do
    mv "$f" "$f.disabled"
  done
fi

#----- update & preflight tools ------------------------------------------------
echo "Updating package lists..."
apt update

# Helpful tools to warn you about bad upgrades (optional but recommended)
if ! dpkg -s apt-listbugs >/dev/null 2>&1; then
  echo "Installing apt-listbugs and apt-listchanges (recommended safeguards)..."
  DEBIAN_FRONTEND=noninteractive apt install -y apt-listbugs apt-listchanges || true
fi

#----- upgrade -----------------------------------------------------------------
if [[ "$AUTO_YES" != "yes" ]]; then
  read -r -p $'Ready to upgrade to Sid. This may remove/replace many packages.\nPress ENTER to continue, or Ctrl+C to abort...'
fi

echo "Starting full upgrade to Debian Sid..."
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y

echo "Cleaning up..."
apt --purge autoremove -y
apt autoclean

echo "All done. Consider rebooting now:"
echo "  sudo reboot"
