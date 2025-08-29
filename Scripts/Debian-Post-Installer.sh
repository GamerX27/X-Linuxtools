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

echo "Installing fish, fastfetch, papirus theme and VLC..."
apt install -y fish fastfetch vlc papirus-icon-theme

echo "Adding Flathub repository (if not already added)..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "Cleaning up APT..."
apt autoremove -y
apt clean

# --- Optional Boot screen setup (Breeze theme) ---
read -p "Do you want to enable the Breeze boot splash screen? [y/N]: " enable_splash
if [[ "$enable_splash" =~ ^[Yy]$ ]]; then
    echo "Installing Plymouth and Breeze theme..."
    apt install -y plymouth plymouth-themes
    apt install -y plymouth-theme-breeze kde-config-plymouth

    echo "Ensuring GRUB has 'quiet splash'..."
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' /etc/default/grub
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> /etc/default/grub
    fi

    echo "Updating GRUB..."
    update-grub2

    echo "Setting Breeze theme for Plymouth..."
    plymouth-set-default-theme -R breeze

    echo "Breeze boot splash enabled."
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
