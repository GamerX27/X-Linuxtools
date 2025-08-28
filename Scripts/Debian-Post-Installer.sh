#!/bin/bash
# Exit immediately on error
set -e

export DEBIAN_FRONTEND=noninteractive

echo "Updating package list..."
apt update

echo "Installing KDE Standard..."
apt install -y kde-standard

echo "Installing Flatpak and Discover Flatpak Backend..."
apt install -y flatpak plasma-discover-backend-flatpak

echo "Installing fish, fastfetch, and VLC..."
apt install -y fish fastfetch vlc

echo "Adding Flathub repository (if not already added)..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "Cleaning up APT..."
apt autoremove -y
apt clean

# --- Optional Boot screen setup (Debian default) ---
read -p "Do you want to enable the Debian boot splash screen? [y/N]: " enable_splash
if [[ "$enable_splash" =~ ^[Yy]$ ]]; then
    echo "Installing Plymouth (Debian default boot splash)..."
    apt install -y plymouth plymouth-themes

    echo "Setting Debian default Plymouth theme..."
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        plymouth-set-default-theme debian-logo
    else
        echo "plymouth-set-default-theme not found; proceeding to update initramfs."
    fi

    echo "Updating initramfs so the splash applies on next boot..."
    update-initramfs -u

    echo "Debian default boot splash enabled."
else
    echo "Skipping boot splash setup."
fi
# ---------------------------------------------------

# Countdown before reboot
echo "Removing /etc/network/interfaces..."
sleep 2
rm -f /etc/network/interfaces

echo "Rebooting in:"
for i in 3 2 1; do
    echo "$i..."
    sleep 1
done

reboot
