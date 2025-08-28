#!/bin/bash

# Exit immediately on error
set -e

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
